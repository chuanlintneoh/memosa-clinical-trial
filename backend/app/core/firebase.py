from firebase_admin import credentials, firestore, storage
import firebase_admin
import os

from app.core.config import FIREBASE_BUCKET_NAME

firebase_path = (
    "/secrets/firebase-admin-key.json"
    if os.path.exists("/secrets/firebase-admin-key.json")
    else "secrets/firebase-admin-key.json"
)
cred = credentials.Certificate(firebase_path)
firebase_app = firebase_admin.initialize_app(cred)

bucket = storage.bucket(FIREBASE_BUCKET_NAME)
db = firestore.client()