from typing import List
from fastapi import APIRouter, HTTPException, Request, Depends

from app.api.invite_manager import InviteManager
from app.api.auth import verify_token
from app.models.invite_code import (
    InviteCodeCreate,
    InviteCodeValidate,
    InviteCodeResponse,
    InviteCodeRevoke
)
from app.models.user import UserRole

invite_router = APIRouter()

def verify_admin(request: Request):
    """Dependency to verify that the user is an admin"""
    uid, role, email, _, verified = verify_token(request, UserRole.admin)
    if not verified:
        raise HTTPException(status_code=403, detail="Only admins can perform this action")
    return uid, role, email

@invite_router.post("/generate", response_model=InviteCodeResponse)
def generate_invite_code(
    data: InviteCodeCreate,
    admin_info: tuple = Depends(verify_admin)
):
    """
    Generate a new invite code (Admin only)

    - **restricted_email**: Optional - restrict code to specific email
    - **restricted_role**: Optional - restrict code to specific role
    - **max_uses**: Maximum times code can be used (0 = unlimited)
    - **expires_in_days**: Days until code expires
    """
    uid, _, _ = admin_info

    try:
        invite_data = InviteManager.create_invite_code(
            created_by_uid=uid,
            restricted_email=data.restricted_email,
            restricted_role=data.restricted_role.value if data.restricted_role else None,
            max_uses=data.max_uses,
            expires_in_days=data.expires_in_days
        )

        # Convert to response model
        response = InviteCodeResponse(
            code=invite_data["code"],
            created_at=invite_data["created_at"],
            created_by=invite_data["created_by"],
            expires_at=invite_data["expires_at"],
            restricted_email=invite_data.get("restricted_email"),
            restricted_role=invite_data.get("restricted_role"),
            max_uses=invite_data["max_uses"],
            times_used=invite_data["times_used"],
            is_active=invite_data["is_active"],
            is_expired=False  # Just created, cannot be expired
        )

        return response

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error generating invite code: {str(e)}")

@invite_router.post("/validate")
def validate_invite_code(data: InviteCodeValidate):
    """
    Validate an invite code (Public endpoint for registration)

    - **code**: The invite code to validate
    - **email**: Email of the user trying to register
    - **role**: Role the user wants to register with
    """
    is_valid, error_message = InviteManager.validate_code(
        code=data.code,
        email=data.email,
        role=data.role.value
    )

    if not is_valid:
        raise HTTPException(status_code=400, detail=error_message)

    return {"valid": True, "message": "Invite code is valid"}

@invite_router.get("/list", response_model=List[InviteCodeResponse])
def list_invite_codes(
    request: Request,
    admin_info: tuple = Depends(verify_admin)
):
    """
    List all invite codes created by the current admin (Admin only)
    """
    uid, _, _ = admin_info

    try:
        codes = InviteManager.list_codes(created_by_uid=uid)

        response = []
        for code_data in codes:
            response.append(InviteCodeResponse(
                code=code_data["code"],
                created_at=code_data["created_at"],
                created_by=code_data["created_by"],
                expires_at=code_data["expires_at"],
                restricted_email=code_data.get("restricted_email"),
                restricted_role=code_data.get("restricted_role"),
                max_uses=code_data["max_uses"],
                times_used=code_data["times_used"],
                is_active=code_data["is_active"],
                is_expired=code_data.get("is_expired", False)
            ))

        return response

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error listing invite codes: {str(e)}")

@invite_router.get("/list/all", response_model=List[InviteCodeResponse])
def list_all_invite_codes(
    request: Request,
    admin_info: tuple = Depends(verify_admin)
):
    """
    List ALL invite codes in the system (Admin only)
    """
    try:
        codes = InviteManager.list_codes()  # No filter = all codes

        response = []
        for code_data in codes:
            response.append(InviteCodeResponse(
                code=code_data["code"],
                created_at=code_data["created_at"],
                created_by=code_data["created_by"],
                expires_at=code_data["expires_at"],
                restricted_email=code_data.get("restricted_email"),
                restricted_role=code_data.get("restricted_role"),
                max_uses=code_data["max_uses"],
                times_used=code_data["times_used"],
                is_active=code_data["is_active"],
                is_expired=code_data.get("is_expired", False)
            ))

        return response

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error listing invite codes: {str(e)}")

@invite_router.delete("/revoke")
def revoke_invite_code(
    data: InviteCodeRevoke,
    admin_info: tuple = Depends(verify_admin)
):
    """
    Revoke (deactivate) an invite code (Admin only)

    - **code**: The invite code to revoke
    """
    success = InviteManager.revoke_code(data.code)

    if not success:
        raise HTTPException(status_code=404, detail="Invite code not found")

    return {"message": f"Invite code {data.code} has been revoked"}

@invite_router.get("/{code}", response_model=InviteCodeResponse)
def get_invite_code_details(
    code: str,
    admin_info: tuple = Depends(verify_admin)
):
    """
    Get details of a specific invite code (Admin only)
    """
    code_data = InviteManager.get_code_details(code)

    if not code_data:
        raise HTTPException(status_code=404, detail="Invite code not found")

    response = InviteCodeResponse(
        code=code_data["code"],
        created_at=code_data["created_at"],
        created_by=code_data["created_by"],
        expires_at=code_data["expires_at"],
        restricted_email=code_data.get("restricted_email"),
        restricted_role=code_data.get("restricted_role"),
        max_uses=code_data["max_uses"],
        times_used=code_data["times_used"],
        is_active=code_data["is_active"],
        is_expired=code_data.get("is_expired", False)
    )

    return response