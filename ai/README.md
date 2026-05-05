# AI Module (`/ai`)

This service hosts the image-classification model used in the MeMoSA clinical trial to generate lesion-type predictions for each submitted case image.

## Purpose

The AI module validates a deep learning diagnostic workflow by producing structured predictions that can be compared against:

- clinician diagnoses,
- coordinator-curated ground truth,
- and biopsy/COE outcomes when available.

Current inference labels are:

- `CANCER`
- `OPMD`
- `OTHER`

The loaded checkpoint is configured in `app/core/config.py` and can be updated for future trial phases.

## Inference Pipeline

1. API receives a JSON payload with base64-encoded image list.
2. Base64 images are decoded to RGB `PIL.Image`.
3. Images are transformed by model-specific preprocessing (resize + normalize + tensor conversion).
4. Batched forward pass is executed with PyTorch.
5. Class decision uses threshold-aware logic (if configured), otherwise argmax.
6. Predictions are returned as a list aligned to input image order.

## Integration with Backend

The backend submits image batches to this module after decrypting encrypted case blobs.

Integration contract:

- **Caller**: backend AI queue/DbManager flow
- **Route**: `POST /inference/predict`
- **Request**: JSON with `images: string[]` (base64-encoded image bytes)
- **Response**: JSON with `predictions: string[]`

The backend then writes these predictions into the `diagnoses[*].ai_lesion_type` fields in Firestore.

## Data Specifications

### Input Schema

| Field    | Type       | Required | Description                                                                                             |
| -------- | ---------- | -------- | ------------------------------------------------------------------------------------------------------- |
| `images` | `string[]` | Yes      | List of base64-encoded image payloads. In production, backend currently sends 9 lesion images per case. |

### Output Schema

| Field         | Type       | Description                                                                 |
| ------------- | ---------- | --------------------------------------------------------------------------- |
| `predictions` | `string[]` | Ordered class predictions for each input image (`CANCER`, `OPMD`, `OTHER`). |

### Example Request

```json
{
  "images": ["<base64-image-1>", "<base64-image-2>"]
}
```

### Example Response

```json
{
  "predictions": ["OPMD", "OTHER"]
}
```

## Tech Stack

| Area              | Technology                     | Role                                                  |
| ----------------- | ------------------------------ | ----------------------------------------------------- |
| API               | FastAPI, Uvicorn               | Exposes inference endpoint and service health routes. |
| ML Runtime        | PyTorch, torchvision           | Loads and runs DenseNet/EfficientNet checkpoints.     |
| Image Processing  | Pillow, albumentations, OpenCV | Decode and preprocess images before inference.        |
| Packaging         | Docker                         | Deployable container for local or Cloud Run hosting.  |
| Cloud Integration | Google Cloud Storage client    | Pulls model artifact to `/tmp/models` in Cloud Run.   |

## Local Setup

```bash
cd ai
python -m venv venv-ai
source venv-ai/Scripts/activate   # Git Bash on Windows
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8001
```

Docs URL: `http://127.0.0.1:8001/docs`

## Environment Variables

Use `.env` (based on `ai/.env.example`):

| Variable               | Required               | Purpose                                                                               |
| ---------------------- | ---------------------- | ------------------------------------------------------------------------------------- |
| `GOOGLE_CLOUD_PROJECT` | Required for Cloud Run | Used to resolve model storage bucket when runtime is Cloud Run (`K_SERVICE` present). |

Model selection and thresholds are currently managed directly in `app/core/config.py`.

## Deployment

### Docker (local/offline)

From repository root:

```bash
docker build -t memosa-ct-ai ai/
docker run --rm -it -p 8001:8080 \
  -v "$(pwd)/ai/models:/ai/models" \
  --env-file ai/.env \
  --name ai-service \
  memosa-ct-ai
```

### Cloud Run Notes

1. Upload/update model artifacts to your GCS path, e.g. `memosa_ai_models/<model>.pth`.
2. Grant the Cloud Run service account read access to model objects.
3. Ensure `GOOGLE_CLOUD_PROJECT` is configured.
4. Deploy container and verify `GET /` and `POST /inference/predict`.

## Module Layout

```text
ai/
├── app/
│   ├── main.py                # FastAPI app entry
│   ├── api/inference.py       # Prediction endpoint
│   ├── core/config.py         # Model path, labels, thresholds, env
│   ├── core/models.py         # Model classes + predict_batch logic
│   └── core/dataloader.py     # Inference dataset wrapper
├── models/                    # Local model files for development
├── requirements.txt
├── Dockerfile
└── README.md
```
