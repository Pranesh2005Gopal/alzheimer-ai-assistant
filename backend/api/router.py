from fastapi import APIRouter

from backend.api.routes_auth import router as auth_router
from backend.api.routes_care import router as care_router
from backend.api.routes_overview import router as overview_router
from backend.api.routes_text import router as text_router
from backend.api.routes_vision import router as vision_router
from backend.api.routes_voice import router as voice_router

api_router = APIRouter(prefix="/v1")
api_router.include_router(auth_router)
api_router.include_router(voice_router)
api_router.include_router(text_router)
api_router.include_router(overview_router)
api_router.include_router(vision_router)
api_router.include_router(care_router)
