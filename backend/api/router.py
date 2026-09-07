from fastapi import APIRouter

from backend.api.routes_overview import router as overview_router
from backend.api.routes_text import router as text_router
from backend.api.routes_voice import router as voice_router

api_router = APIRouter(prefix="/v1")
api_router.include_router(voice_router)
api_router.include_router(text_router)
api_router.include_router(overview_router)
