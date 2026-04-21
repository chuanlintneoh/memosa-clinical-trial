from fastapi import HTTPException, Request
from firebase_admin import auth
from typing import Optional, Tuple

from app.models.user import UserRole

def verify_token(
    request: Request,
    verify_role: Optional[UserRole] = None,
) -> Tuple[str, str, str, dict, bool]:
    try:
        token = request.headers.get("Authorization", "").replace("Bearer ", "")
        decoded = auth.verify_id_token(token)
        uid = decoded["uid"]
        role = decoded.get("role")
        email = decoded["email"]

        if verify_role is None:
            return uid, role, email, decoded, True
        return uid, role, email, decoded, (role == verify_role)

    except Exception as e:
        raise HTTPException(status_code=401, detail="Invalid or expired token") from e