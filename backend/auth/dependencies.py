"""
FastAPI dependency helpers for authentication and authorization.
"""
from __future__ import annotations

from typing import Optional

from dataclasses import dataclass
from fastapi import Depends, Header, HTTPException, Query, status

from backend.auth.store import get_caregiver_permissions, get_session, get_user_by_id


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


@dataclass(frozen=True)
class PatientAccess:
    patient_id: str
    user: dict


@dataclass(frozen=True)
class ChatAccess:
    """Authenticated owner of a private assistant conversation.

    This deliberately never accepts a client-provided owner or selected
    patient id. Care workflows use ``PatientAccess`` separately.
    """
    account_id: str
    role: str
    user: dict


def get_chat_access(user: dict = Depends(get_current_user)) -> ChatAccess:
    if user["role"] not in ("patient", "caregiver", "admin"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unsupported account role")
    return ChatAccess(account_id=user["id"], role=user["role"], user=user)


def get_patient_access(
    patient_id: str | None = Query(default=None),
    user: dict = Depends(get_current_user),
) -> PatientAccess:
    """Resolve one patient only after authenticating the caller.

    Patients are always limited to their own user id. Caregivers must name a
    patient explicitly and have an existing permission link from that patient.
    """
    if user["role"] == "patient":
        if patient_id and patient_id != user["id"]:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Patients can access only their own records")
        return PatientAccess(patient_id=user["id"], user=user)
    if user["role"] in ("caregiver", "admin"):
        if not patient_id:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="patient_id is required for caregiver access")
        if user["role"] != "admin" and not get_caregiver_permissions(patient_id, user["id"]):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Caregiver is not authorized for this patient")
        return PatientAccess(patient_id=patient_id, user=user)
    raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unsupported account role")
