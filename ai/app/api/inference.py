import base64
from fastapi import APIRouter, HTTPException, Request
from io import BytesIO
from PIL import Image
import torch
from torch.utils.data import DataLoader

from app.core import models
from app.core.config import MODEL, MODEL_PATH, THRESHOLDS
from app.core.dataloader import InferenceDataset

router = APIRouter()

model_path = f"{MODEL_PATH}/{MODEL}"
checkpoint = torch.load(model_path, map_location=torch.device("cuda" if torch.cuda.is_available() else "cpu"))
model = models.class_to_model[checkpoint["model_type"]].load_from_checkpoint(model_path)

label_mapping = {}
thresholds = []
if THRESHOLDS is not None:
    threshold_items = THRESHOLDS.split(",")
    for i, thres in enumerate(sorted(threshold_items)):
        label, value = thres.split(":", 1)

        label_mapping[i] = str(label).upper()
        thresholds.append(float(value))
else:
    # Hardcoded fallback
    label_mapping = {
        0: "CANCER",
        1: "OPMD",
        2: "OTHER"
    }

# Compare label mapping stored in model
if model.label_mapping is not None:
    if model.label_mapping != label_mapping:
        print(f"CRITICAL: Mapping mismatch!")
        print(f"Model expects: {model.label_mapping}")
        print(f"Provided via string: {label_mapping}")
else:
    print("No label mapping stored in model")
    model.label_mapping = label_mapping

@router.post("/predict")
async def predict(request: Request):
    try:
        body = await request.json()
        image_b64_list = body.get("images", [])
        if not image_b64_list or not isinstance(image_b64_list, list):
            raise ValueError("Missing or invalid 'images' list in request.")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid JSON body: {e}")
    
    images = []
    for b64_str in image_b64_list:
        try:
            img_bytes = base64.b64decode(b64_str)
            img = Image.open(BytesIO(img_bytes)).convert("RGB")
            images.append(img)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"Image decoding failed: {e}")
    
    dataset = InferenceDataset(images, transform=model.preprocess)
    dataloader = DataLoader(dataset, batch_size=3, shuffle=False)
    predictions = model.predict_batch(dataloader=dataloader, thresholds=thresholds)

    return {"predictions": predictions}