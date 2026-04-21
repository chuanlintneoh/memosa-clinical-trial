from dateutil import parser
from fastapi import APIRouter, BackgroundTasks, Query, Request
from fastapi.responses import JSONResponse
# from fastapi.responses import StreamingResponse
from typing import Any, Dict

from app.api.auth import verify_token
from app.api.bootstrap import dbmanager
from app.models.user import UserRole

dbmanager_router = APIRouter()

@dbmanager_router.post("/case/create")
async def create_case(
    request: Request,
    background_tasks: BackgroundTasks,
    case_id: str = Query(...)
):
    uid, role, _, _, verified = verify_token(request, UserRole.study_coordinator)
    if not verified:
        return JSONResponse(content={"error": "Unauthorized"}, status_code=403)
    
    try:
        # 1. receives case data
        data: Dict[str, Any] = await request.json()
        data["created_at"] = parser.isoparse(data["created_at"])
        if uid != data["created_by"]:
            return JSONResponse(content={"error": "Unauthorized"}, status_code=403)

        # 2. check field existences
        encrypted_aes = data.get("encrypted_aes", {})
        if not encrypted_aes:
            return JSONResponse(content={"error": "Missing encrypted AES key"}, status_code=400)

        # 3. ensure case_id is unique
        case_id = dbmanager.uniquify_id(case_id)

        # 4. store case in cache
        dbmanager.pending_cases[case_id] = data

        # 5. queue job for AI diagnosis
        background_tasks.add_task(dbmanager.enqueue_ai_job, case_id, data)

        return JSONResponse(content={"case_id": case_id}, status_code=200)

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)

@dbmanager_router.get("/case/get/{case_id}")
def get_case(case_id: str, request: Request):
    _, role, _, _, verified = verify_token(request, UserRole.study_coordinator)
    if not verified:
        return JSONResponse(content={"error": "Unauthorized"}, status_code=403)
    return dbmanager.get_case_by_id(case_id)

@dbmanager_router.patch("/case/edit")
async def edit_case(
    request: Request,
    case_id: str = Query(...)
):
    _, role, _, _, verified = verify_token(request, UserRole.study_coordinator)
    if not verified:
        return JSONResponse(content={"error": "Unauthorized"}, status_code=403)

    updates = await request.json()
    case_id, status = dbmanager.edit_case_by_id(case_id, updates)
    return JSONResponse(content={"case_id": case_id, "status": status}, status_code=200)

@dbmanager_router.get("/cases/list")
def list_cases(
    request: Request,
    date_range: str = Query(None),
    custom_start: str = Query(None),
    custom_end: str = Query(None),
    created_by_me: bool = Query(False),
    limit: int = Query(5),
    start_after_id: str = Query(None)
):
    """
    Get a paginated list of cases with optional filters.

    Query Parameters:
        - date_range: Optional - "today", "this_week", "this_month", or "custom"
        - custom_start: Optional - ISO date string (YYYY-MM-DD) for custom range start
        - custom_end: Optional - ISO date string (YYYY-MM-DD) for custom range end
        - created_by_me: Optional boolean - if True, filter to only cases created by current user (default: False)
        - limit: Optional int - number of cases to return
        - start_after_id: Optional string - case ID to start after for pagination

    Returns:
        {
            "cases": [...],
            "next_cursor": "case_id" or null,
            "has_more": boolean
        }
    """
    uid, role, _, _, verified = verify_token(request, UserRole.study_coordinator)
    if not verified:
        return JSONResponse(content={"error": "Unauthorized"}, status_code=403)

    try:
        result = dbmanager.get_cases_list(
            current_user_uid=uid,
            date_range=date_range,
            custom_start=custom_start,
            custom_end=custom_end,
            created_by_me=created_by_me,
            limit=limit,
            start_after_id=start_after_id
        )
        return JSONResponse(content=result, status_code=200)
    except Exception as e:
        print(f"[DbManager Routes] Error listing cases: {str(e)}")
        return JSONResponse(content={"error": str(e)}, status_code=500)

@dbmanager_router.get("/cases/undiagnosed/{clinician_id}")
def get_undiagnosed_cases(clinician_id: str, request: Request):
    uid, role, _, _, verified = verify_token(request, UserRole.clinician)
    if uid != clinician_id or not verified:
        return JSONResponse(content={"error": "Unauthorized"}, status_code=403)
    return dbmanager.get_undiagnosed_cases(clinician_id)

@dbmanager_router.patch("/case/diagnose")
async def diagnose_case(
    request: Request,
    case_id: str = Query(...)
):
    uid, role, _, _, verified = verify_token(request, UserRole.clinician)
    if not verified:
        return JSONResponse(content={"error": "Unauthorized"}, status_code=403)

    body = await request.json()
    diagnoses = body.get("diagnoses", [])
    filtered = [diag for diag in diagnoses if uid in diag]
    if not filtered:
        return JSONResponse(content={"error": "Unauthorized"}, status_code=403)

    case_id, status = dbmanager.submit_case_diagnosis(case_id, filtered)
    return JSONResponse(content={"case_id": case_id, "status": status}, status_code=200)

# @dbmanager_router.get("/cases/export")
# async def export_mastersheet(include_all: bool = False):
#     buf, timestamp = await dbmanager.export_bundle(include_all=include_all)
#     return StreamingResponse(
#         buf,
#         media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
#         headers={"Content-Disposition": f"attachment; filename=mastersheet_{timestamp}.xlsx"}
#     )

@dbmanager_router.post("/bundle/export")
async def export_bundle(request: Request, include_all: bool = False, expiry_days: int = 1):
    user_id, role, _, _, verified = verify_token(request, UserRole.admin)
    if not verified:
        print(f"[DbManager Routes] Rejected request from user ({role}) {user_id} to export bundle")
        return JSONResponse(content={"error": "Unauthorized"}, status_code=403)

    print(f"[DbManager Routes] Received and processing request from {role} user ({role}) {user_id} to export bundle")
    
    try:
        url, password, timestamp = await dbmanager.export_bundle(include_all=include_all, signed_url=True, expiry_seconds=expiry_days * 24 * 3600)
        if not url:
            return {
                "status": "failed",
                "error": "No url returned"
            }
        return {
            "status": "success",
            "url": url,
            "password": password,
            "timestamp": timestamp,
            "expiry_days": expiry_days,
            "include_all": include_all,
        }
    except Exception as e:
        print(f"[DbManager] Failed to generate/download bundle: {e}")
        return {
            "status": "failed",
            "error": str(e)
        }

# @dbmanager_router.get("/bundle/email")
# async def email_bundle(email: str, include_all: bool = False):
#     try:
#         password = await dbmanager.export_bundle(include_all=include_all, email=email)
#         return {
#             "status": "success" if password != "NULL" else "failed",
#             "password": password if password != "NULL" else None,
#             "email": email,
#             "include_all": include_all,
#         }
#     except Exception as e:
#         print(f"[DbManager] Failed to generate/email bundle: {e}")
#         return {
#             "status": f"failed: {e}",
#             "email": email,
#             "include_all": include_all,
#         }
    
# AIQueue flow:
# 1. AIQueue receives new cases from DbManager and adds them to the queue
# 2. AIQueue flush cases to AI diagnosis service for batch inference (time interval or max cases reached)
# 3. AIQueue wait with timeout for AI diagnosis service to return results
# 4. AIQueue append diagnosis results to case id (no results / exceed timeout = "FAILED") and send back to DbManager

# the tasks of dbmanager include:
# - store newly created case
# - arrange new job to ai queue service for new case created
# - query for case using case id
# - edit existing case
# - query for list of undiagnosed cases for a clinician using clinician id
# - store diagnosis/diagnoses newly created by a clinician
# - query for list of all cases for admins