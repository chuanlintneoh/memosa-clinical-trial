from fastapi import FastAPI, Request

from app.api.routes.auth import auth_router
from app.api.routes.dbmanager import dbmanager_router
from app.api.routes.invite_manager import invite_router
from app.api.routes.user_manager import user_router

app = FastAPI()

app.include_router(auth_router, prefix="/auth", tags=["Authentication"])
app.include_router(dbmanager_router, prefix="/dbmanager", tags=["DbManager"])
app.include_router(invite_router, prefix="/invite-manager", tags=["InviteManager"])
app.include_router(user_router, prefix="/user-manager", tags=["UserManager"])

@app.get("/")
def read_root(request: Request):
    docs_url = str(request.base_url) + "docs"
    return {"message": "FastAPI backend is live! Go to $docs_url for API documentation.", "docs_url": docs_url}