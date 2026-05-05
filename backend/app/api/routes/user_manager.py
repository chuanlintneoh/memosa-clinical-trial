from fastapi import APIRouter, Query, Request
from fastapi.responses import JSONResponse
from typing import Optional

from app.api.auth import verify_token
from app.api.user_manager import UserManager
from app.models.user import UserRole

user_router = APIRouter()

@user_router.get("/users/list")
def get_users(
    request: Request,
    limit: int = Query(5),
    start_after_id: str = Query(None),
    search_role: str = Query(None),
    name: str = Query(None)
):
    uid, role, _, _, verified = verify_token(request, UserRole.admin)
    if not verified:
        return JSONResponse(content={"error": "Unauthorized"}, status_code=403)

    result, status, success = UserManager.get_users(
        limit=limit,
        start_after_id=start_after_id,
        role=search_role,
        name=name
    )
    return JSONResponse(content={"users": result, "status": status}, status_code=(200 if success else 500))

@user_router.get("/user/get/{user_id}")
def get_user_by_id(
    user_id: str,
    request: Request
):
    uid, role, _, _, verified = verify_token(request, UserRole.admin)
    if not verified:
        return JSONResponse(content={"error": "Unauthorized"}, status_code=403)

    user, status, success = UserManager.get_user_by_id(user_id)

    return JSONResponse(content={"user": user, "status": status}, status_code=(200 if success else 500))

@user_router.delete("/user/delete")
def delete_user(
    request: Request,
    user_id: str = Query(...),
    hard_delete: bool = Query(False)
):
    uid, role, _, _, verified = verify_token(request, UserRole.admin)
    if not verified:
        return JSONResponse(content={"error": "Unauthorized"}, status_code=403)

    status, success = UserManager.delete_user(user_id, hard_delete)

    return JSONResponse(content={"status": status}, status_code=(200 if success else 500))

@user_router.patch("/user/reactivate")
def reactivate_user(
    request: Request,
    user_id: str
):
    uid, role, _, _, verified = verify_token(request, UserRole.admin)
    if not verified:
        return JSONResponse(content={"error": "Unauthorized"}, status_code=403)

    user_id, status, success = UserManager.reactivate_user(user_id)

    return JSONResponse(content={"user_id": user_id, "status": status}, status_code=(200 if success else 500))

@user_router.patch("/user/edit")
async def edit_user(
    request: Request,
    user_id: str = Query(...)
):
    uid, role, _, _, verified = verify_token(request, UserRole.admin)
    if not verified:
        return JSONResponse(content={"error": "Unauthorized"}, status_code=403)

    updates = await request.json()
    user_id, status, success = UserManager.edit_user(user_id, updates)
    return JSONResponse(content={"user_id": user_id, "status": status}, status_code=(200 if success else 500))