from fastapi import APIRouter, HTTPException, Request
from firebase_admin import auth, firestore

from app.api.auth import verify_token
from app.api.invite_manager import InviteManager
from app.core.firebase import db
from app.models.user import RegisterUser

auth_router = APIRouter()

@auth_router.post("/register")
def register_user(data: RegisterUser):
    try:
        # Validate invite code first
        is_valid, error_message = InviteManager.validate_code(
            code=data.invite_code,
            email=data.email,
            role=data.role.value
        )

        if not is_valid:
            raise HTTPException(status_code=400, detail=error_message)

        # Create user in Firebase Authentication
        user = auth.create_user(
            email=data.email,
            password=data.password,
            display_name=data.full_name
        )

        # Consume the invite code (increment usage count)
        InviteManager.consume_code(data.invite_code, user.uid)

        # Store role as custom user claim
        auth.set_custom_user_claims(user.uid, {"role": data.role.value})
        # Create user document in Firestore
        user_data = {
            "created_at": firestore.SERVER_TIMESTAMP,
            "email": data.email,
            "name": data.full_name,
            "role": data.role.value,
            "invite_code_used": data.invite_code
        }
        db.collection("users").document(user.uid).set(user_data)

        response_data = {
            "uid": user.uid,
            "email": data.email,
            "name": data.full_name,
            "role": data.role.value
        }

        return response_data
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@auth_router.get("/login")
def login_user(request: Request):
    uid, role, email, _ = verify_token(request)
    try:
        user_doc = db.collection("users").document(uid).get()
        if not user_doc.exists:
            raise HTTPException(status_code=404, detail="User document not found")
        user_data = user_doc.to_dict()
        name = user_data.get("name", "")

        response = {
            "uid": uid,
            "email": email,
            "role": role,
            "name": name,
        }
        return response
    except Exception as e:
        raise HTTPException(status_code=401, detail=str(e))