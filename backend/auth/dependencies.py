"""
FastAPI dependency helpers for authentication and authorization.
"""
from __future__ import annotations

from typing import Optional

from fastapi import Depends, Header, HTTPException, status

from backend.auth.store import get_session, get_user_by_id


def _get_bearer(authorization: Optional[str] = Header(default=None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return authorization[7:]


def get_current_session(token: str = Depends(_get_bearer)) -> dict:
    session = get_session(token)
    if session is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session expired or invalid",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return session


def get_current_user(session: dict = Depends(get_current_session)) -> dict:
    user = get_user_by_id(session["user_id"])
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user


def require_patient(user: dict = Depends(get_current_user)) -> dict:
    if user["role"] not in ("patient", "admin"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Patients only")
    return user


def require_caregiver(user: dict = Depends(get_current_user)) -> dict:
    if user["role"] not in ("caregiver", "admin"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Caregivers only")
    return user
