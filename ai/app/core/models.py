from abc import ABC, abstractmethod
import albumentations as A
from albumentations.pytorch import ToTensorV2
import cv2
import numpy as np
import torch
from torch import nn
import torch.nn.functional as F
from torch.utils.data import DataLoader
from torchvision import models
from typing import List

class BaseModel(nn.Module, ABC):
    """Base class for all models with common functionality"""
    
    def __init__(self, num_classes, pretrained=True, version=None, freeze_base=False, dataset=None, model_name=None, label_mapping=None):
        super().__init__()

        self.num_classes = num_classes
        self.pretrained = pretrained
        self.version = version
        self.freeze_base = freeze_base
        self.dataset = dataset
        self.model_name = model_name
        self.label_mapping = label_mapping
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

        self.model = None
        self.mean = None
        self.std = None
        
    @classmethod
    def load_from_checkpoint(cls, path):
        """Factory method to create model from checkpoint"""
        device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        checkpoint = torch.load(path, map_location=device, weights_only=False)
        model = cls(
            num_classes=checkpoint['num_classes'],
            pretrained=True, # hardcoded
            version=checkpoint["model_version"],
            dataset=checkpoint["model_dataset"],
            model_name=checkpoint["model_name"],
            label_mapping=checkpoint.get("label_mapping")
        )

        # Older models saved ONLY self.model.state_dict(), so keys lack the 'model.' prefix.
        state_dict = checkpoint['model_state_dict']
        # Check if this is a NEW checkpoint (keys already have the 'model.' prefix)
        # or an OLD checkpoint (keys belong directly to the inner network)
        is_new_format = any(k.startswith("model.") for k in state_dict.keys())

        if is_new_format:
            model.load_state_dict(state_dict)
        else:
            # Fallback to original logic for old checkpoint: Load the weights directly into the inner network.
            # TODO: delete this block when older models are no longer in use
            print("Detected old model weights structure (Model wrapped in model.model)")
            model.model.load_state_dict(state_dict)
            
        return model

    @abstractmethod
    def _get_preprocessing_pipeline(self, input_size, augment=False):
        pass

    def forward(self, x):
        if self.model is None:
            raise NotImplementedError("self.model is not initialized.")
        return self.model(x)
    
    def predict_batch(self, dataloader: DataLoader, thresholds: list = None) -> List[str]:
        self.eval()
        predictions = []
        
        with torch.no_grad():
            for images in dataloader:
                images = images.to(self.device)
                outputs = self(images)

                probs = F.softmax(outputs, dim=1).cpu().numpy()
                batch_preds = []
                for row in probs:
                    if thresholds is None:
                        batch_preds.append(np.argmax(row))
                        continue

                    passed = [i for i, thr in enumerate(thresholds) if row[i] >= thr]
                    if len(passed) == 1:
                        batch_preds.append(passed[0])
                    elif len(passed) == 0:
                        batch_preds.append(np.argmax(row))
                    else:
                        distances = []
                        for i in passed:
                            denom = max(1 - thresholds[i], 1e-12)
                            dist = (row[i] - thresholds[i]) / denom
                            distances.append((i, dist))
                        best_class, _ = max(distances, key=lambda x: (x[1], row[x[0]]))
                        batch_preds.append(best_class)

                predictions.extend([self.label_mapping[i] for i in batch_preds])

        return predictions

class DenseNetClassifier(BaseModel):
    def __init__(
        self,
        num_classes=6,
        pretrained=True,
        version="121",
        dataset=None,
        model_name=None,
        label_mapping=None
    ):
        super().__init__(
            num_classes=num_classes,
            pretrained=pretrained,
            version=version,
            dataset=dataset,
            model_name=model_name,
            label_mapping=label_mapping
        )

        model_fn = getattr(models, f"densenet{self.version}", None)
        if not model_fn:
            raise ValueError(f"DenseNet version '{self.version}' is not supported.")

        model_metadata = models.get_model_weights(model_fn).DEFAULT
        input_size = model_metadata.transforms().crop_size[0]
        self.mean = model_metadata.transforms().mean
        self.std = model_metadata.transforms().std
        
        self.weights = model_metadata
        self.model = self._load_model(model_fn=model_fn)

        self.preprocess = self._get_preprocessing_pipeline(input_size=input_size)

    def _load_model(self, model_fn):
        """
        Load the DenseNet model with pretrained weights.
        """
        model = model_fn(weights=self.weights if self.pretrained else None)

        in_features = model.classifier.in_features
        model.classifier = nn.Sequential(
            nn.Dropout(p=0.5, inplace=True),
            nn.Linear(in_features, self.num_classes),
        )
        return model.to(self.device)

    def _get_preprocessing_pipeline(self, input_size):
        """
        Define the preprocessing steps for input images.
        """
        transformation = A.Compose([
            A.Resize(height=input_size, width=input_size, interpolation=cv2.INTER_CUBIC),
            A.Normalize(mean=self.mean, std=self.std),
            ToTensorV2()
        ])
            
        return transformation

class EfficientNetClassifier(BaseModel):
    def __init__(
        self,
        num_classes=6,
        pretrained=True,
        version="b3",
        dataset=None,
        model_name=None,
        label_mapping=None
    ):
        """
        Initialize the EfficientNet model.
        Supported efficient Net versions:  "bo", ..., "b7"
        """
        super().__init__(
            num_classes=num_classes,
            pretrained=pretrained,
            version=version,
            dataset=dataset,
            model_name=model_name,
            label_mapping=label_mapping
        )

        model_fn = getattr(models, f"efficientnet_{self.version}", None)
        if not model_fn:
            raise ValueError(f"EfficientNet version '{self.version}' is not supported.")

        model_metadata = models.get_model_weights(model_fn).DEFAULT
        input_size = model_metadata.transforms().crop_size[0]
        self.mean = model_metadata.transforms().mean
        self.std = model_metadata.transforms().std

        self.weights = model_metadata
        self.model = self._load_model(model_fn=model_fn)

        self.preprocess = self._get_preprocessing_pipeline(input_size=input_size)

    def _load_model(self, model_fn):
        """
        Load the EfficientNet model with pretrained weights.
        """
        model = model_fn(weights=self.weights if self.pretrained else None)

        in_features = model.classifier[1].in_features
        model.classifier = nn.Sequential(
            nn.Dropout(p=0.5, inplace=True),
            nn.Linear(in_features, self.num_classes),
        )
        return model.to(self.device)

    def _get_preprocessing_pipeline(self, input_size):
        """
        Define the preprocessing steps for input images.
        """
        transformation = A.Compose([
            A.Resize(height=input_size, width=input_size, interpolation=cv2.INTER_CUBIC),
            A.Normalize(mean=self.mean, std=self.std),
            ToTensorV2()
        ])
        
        return transformation

class_to_model = {
    "EfficientNetClassifier": EfficientNetClassifier,
    "DenseNetClassifier": DenseNetClassifier,
}