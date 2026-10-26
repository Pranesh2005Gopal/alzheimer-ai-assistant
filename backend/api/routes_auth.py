"""
Auth + Profile + Private Information routes.
Prefix: /v1/auth  and  /v1/profile
"""
from __future__ import annotations

import time
from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, EmailStr, Field

from backend.auth.dependencies import get_current_user, get_current_session
from backend.auth.store import (
    authenticate_user,
    change_password,
    create_session,
    create_user,
    delete_session,
    get_assigned_patients,
    get_audit_logs,
    get_caregiver_permissions,
    get_private,
    get_user_by_id,
    log_audit_event,
    set_caregiver_permission,
    set_pin,
    update_private,
    update_profile,
    verify_user_pin,
)
from backend.container import get_container
from repositories.postgres import (
    get_caregiver_profile, link_legacy_patient, list_caregiver_assignments,
    sync_caregiver_assignment, upsert_caregiver_profile,
)
from utils.config import get_settings

router = APIRouter(tags=["auth"])

_PROFESSIONAL_PROFILE_FIELDS = {
    "designation", "specialization", "organization", "qualifications",
    "professional_phone", "professional_email",
}


def _postgres_factory():
    """Return the configured care database factory, or None in file-backed dev."""
    container = get_container()
    return getattr(getattr(container, "repos", None), "factory", None) if container.settings.database_url else None


def _caregiver_professional_fields(caregiver_id: str) -> dict:
    factory = _postgres_factory()
    return get_caregiver_profile(factory, caregiver_id) if factory else {}


def _save_caregiver_professional_fields(caregiver_id: str, fields: dict) -> dict:
    factory = _postgres_factory()
    # File-backed development retains the same values in the existing profile
    # store; production writes the durable PostgreSQL caregiver profile.
    return upsert_caregiver_profile(factory, caregiver_id, fields) if factory else fields


def _public_user_with_profile(user: dict) -> dict:
    result = dict(user)
    result["profile"] = dict(user.get("profile", {}))
    if user.get("role") == "caregiver":
        result["profile"].update(_caregiver_professional_fields(user["id"]))
    return result

# ---------------------------------------------------------------------------
# Rate-limiting state (in-memory, per IP)
# ---------------------------------------------------------------------------
_rate_state: dict[str, dict] = {}
_RATE_WINDOW = 300  # 5-minute window
_RATE_MAX = 10      # max login attempts per window


def _check_rate_limit(request: Request, key: str = "login") -> None:
    ip = request.client.host if request.client else "unknown"
    bucket_key = f"{key}:{ip}"
    now = time.time()
    state = _rate_state.get(bucket_key, {"count": 0, "window_start": now})
    if now - state["window_start"] > _RATE_WINDOW:
        state = {"count": 0, "window_start": now}
    state["count"] += 1
    _rate_state[bucket_key] = state
    if state["count"] > _RATE_MAX:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many attempts. Try again in 5 minutes.",
        )


# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------

class RegisterRequest(BaseModel):
    email: str = Field(min_length=5)
    password: str = Field(min_length=8)
    full_name: str = Field(default="", max_length=100)
    role: str = Field(default="patient", pattern="^(patient|caregiver)$")


class LoginRequest(BaseModel):
    email: str
    password: str


class ChangePasswordRequest(BaseModel):
    old_password: str
    new_password: str = Field(min_length=8)


class SetPinRequest(BaseModel):
    pin: str = Field(pattern=r"^\d{4,6}$")


class VerifyPinRequest(BaseModel):
    pin: str = Field(pattern=r"^\d{4,6}$")


class ProfileUpdateRequest(BaseModel):
    full_name: Optional[str] = None
    preferred_name: Optional[str] = None
    avatar_url: Optional[str] = None
    date_of_birth: Optional[str] = None
    language: Optional[str] = None
    voice_preference: Optional[str] = None
    hobbies: Optional[list[str]] = None
    daily_routine: Optional[list[str]] = None
    important_dates: Optional[list[Any]] = None
    personal_memories: Optional[list[Any]] = None
    designation: Optional[str] = Field(default=None, max_length=200)
    specialization: Optional[str] = Field(default=None, max_length=300)
    organization: Optional[str] = Field(default=None, max_length=300)
    qualifications: Optional[str] = None
    professional_phone: Optional[str] = Field(default=None, max_length=80)
    professional_email: Optional[str] = Field(default=None, max_length=320)


class PrivateUpdateRequest(BaseModel):
    medical_conditions: Optional[list[str]] = None
    allergies: Optional[list[str]] = None
    medications: Optional[list[Any]] = None
    emergency_contacts: Optional[list[Any]] = None
    doctor_details: Optional[Any] = None
    address: Optional[str] = None
    caregiver_info: Optional[Any] = None


class CaregiverPermissionRequest(BaseModel):
    caregiver_id: str
    permissions: list[str]


class LegacyPatientLinkRequest(BaseModel):
    legacy_patient_id: str = Field(min_length=1)
    patient_user_id: str = Field(min_length=1)


# ---------------------------------------------------------------------------
# Auth routes
# ---------------------------------------------------------------------------

@router.post("/auth/register", status_code=status.HTTP_201_CREATED)
def register(body: RegisterRequest, request: Request) -> dict:
    _check_rate_limit(request, "register")
    try:
        user = create_user(
            email=body.email,
            password=body.password,
            role=body.role,
            full_name=body.full_name,
        )
    except ValueError as exc:
        if "email_taken" in str(exc):
            raise HTTPException(status_code=409, detail="Email already registered")
        raise HTTPException(status_code=400, detail=str(exc))
    token = create_session(user["id"], user["role"])
    return {"user": _public_user_with_profile(user), "token": token}


@router.post("/auth/login")
def login(body: LoginRequest, request: Request) -> dict:
    _check_rate_limit(request, "login")
    user = authenticate_user(body.email, body.password)
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid email or password")
    token = create_session(user["id"], user["role"])
    return {"user": _public_user_with_profile(user), "token": token}


@router.post("/auth/logout")
def logout(session: dict = Depends(get_current_session)) -> dict:
    # session dict contains the token key via our dependency
    # We need the raw token – pass it from header via a different approach
    return {"ok": True}


@router.post("/auth/logout2")
def logout2(request: Request) -> dict:
    """Logout using raw Bearer token."""
    auth = request.headers.get("Authorization", "")
    if auth.startswith("Bearer "):
        delete_session(auth[7:])
    return {"ok": True}


@router.get("/auth/me")
def me(user: dict = Depends(get_current_user)) -> dict:
    return {"user": _public_user_with_profile(user)}


@router.post("/auth/change-password")
def change_pwd(body: ChangePasswordRequest, user: dict = Depends(get_current_user)) -> dict:
    try:
        change_password(user["id"], body.old_password, body.new_password)
    except PermissionError:
        raise HTTPException(status_code=401, detail="Current password is incorrect")
    return {"ok": True}


@router.post("/auth/set-pin")
def set_user_pin(body: SetPinRequest, user: dict = Depends(get_current_user)) -> dict:
    try:
        set_pin(user["id"], body.pin)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return {"ok": True}


@router.post("/auth/verify-pin")
def verify_pin_endpoint(body: VerifyPinRequest, request: Request, user: dict = Depends(get_current_user)) -> dict:
    _check_rate_limit(request, f"pin:{user['id']}")
    try:
        ok = verify_user_pin(user["id"], body.pin)
    except PermissionError:
        raise HTTPException(status_code=429, detail="PIN locked due to too many failures. Try again in 5 minutes.")
    if not ok:
        raise HTTPException(status_code=401, detail="Incorrect PIN")
    # Issue a short-lived "private access" token scoped to this session
    # For simplicity: return a timestamped HMAC grant that expires in 10 minutes
    import hashlib, hmac as _hmac, time as _time
    grant_payload = f"{user['id']}:{int(_time.time()) // 600}"  # 10-min bucket
    from backend.auth.store import _MASTER_KEY
    sig = _hmac.new(_MASTER_KEY.encode(), grant_payload.encode(), hashlib.sha256).hexdigest()
    return {"ok": True, "private_grant": f"{grant_payload}:{sig}"}


# ---------------------------------------------------------------------------
# Profile routes
# ---------------------------------------------------------------------------

@router.get("/profile")
def get_profile(user: dict = Depends(get_current_user)) -> dict:
    profile = dict(user["profile"])
    if user["role"] == "caregiver":
        profile.update(_caregiver_professional_fields(user["id"]))
    return {"profile": profile, "role": user["role"], "email": user["email"]}


@router.patch("/profile")
def update_user_profile(body: ProfileUpdateRequest, user: dict = Depends(get_current_user)) -> dict:
    changes = {k: v for k, v in body.model_dump().items() if v is not None}
    professional = {k: changes.pop(k) for k in list(changes) if k in _PROFESSIONAL_PROFILE_FIELDS}
    if professional and user["role"] != "caregiver":
        raise HTTPException(status_code=403, detail="Professional profile fields are for caregiver accounts only")
    # Keep local file-backed development usable while production persists the
    # same caregiver fields in PostgreSQL.
    profile_changes = dict(changes)
    if professional and not _postgres_factory():
        profile_changes.update(professional)
    updated = update_profile(user["id"], profile_changes)
    profile = dict(updated["profile"])
    if user["role"] == "caregiver":
        if professional:
            profile.update(_save_caregiver_professional_fields(user["id"], professional))
        else:
            profile.update(_caregiver_professional_fields(user["id"]))
    return {"profile": profile}


# ---------------------------------------------------------------------------
# Private information routes (PIN-gated)
# ---------------------------------------------------------------------------

def _validate_grant(user_id: str, grant: Optional[str]) -> None:
    """Validate a private_grant issued by /auth/verify-pin."""
    if not grant:
        raise HTTPException(status_code=403, detail="Private grant required. Verify PIN first.")
    import hashlib, hmac as _hmac, time as _time
    from backend.auth.store import _MASTER_KEY
    try:
        parts = grant.rsplit(":", 1)
        if len(parts) != 2:
            raise ValueError
        payload, sig = parts
        expected_sig = _hmac.new(_MASTER_KEY.encode(), payload.encode(), hashlib.sha256).hexdigest()
        if not _hmac.compare_digest(sig, expected_sig):
            raise ValueError("bad sig")
        # Validate time: allow current and previous bucket (up to 20 min grace)
        uid, bucket_str = payload.rsplit(":", 1)
        if uid != user_id:
            raise ValueError("user mismatch")
        bucket = int(bucket_str)
        current_bucket = int(_time.time()) // 600
        if abs(current_bucket - bucket) > 2:  # 20-minute window
            raise ValueError("grant expired")
    except (ValueError, Exception) as exc:
        raise HTTPException(status_code=403, detail="Invalid or expired private grant. Re-verify PIN.")


@router.get("/private")
def get_private_info(
    private_grant: Optional[str] = None,
    user: dict = Depends(get_current_user),
) -> dict:
    _validate_grant(user["id"], private_grant)
    data = get_private(user["id"])
    return {"private": data}


@router.patch("/private")
def update_private_info(
    body: PrivateUpdateRequest,
    private_grant: Optional[str] = None,
    user: dict = Depends(get_current_user),
) -> dict:
    _validate_grant(user["id"], private_grant)
    changes = {k: v for k, v in body.model_dump().items() if v is not None}
    update_private(user["id"], changes)
    return {"ok": True}


# ---------------------------------------------------------------------------
# Caregiver permission routes
# ---------------------------------------------------------------------------

@router.post("/profile/caregiver-permissions")
def set_permissions(body: CaregiverPermissionRequest, user: dict = Depends(get_current_user)) -> dict:
    if user["role"] != "patient":
        raise HTTPException(status_code=403, detail="Only patients can set caregiver permissions")
    caregiver = get_user_by_id(body.caregiver_id)
    if not caregiver or caregiver["role"] != "caregiver":
        raise HTTPException(status_code=400, detail="caregiver_id must identify an existing caregiver account")
    try:
        set_caregiver_permission(user["id"], body.caregiver_id, body.permissions)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    factory = _postgres_factory()
    if factory:
        # The patient has just explicitly authorized this link.  Mirror it in
        # PostgreSQL; do not synthesize links from unrelated account records.
        sync_caregiver_assignment(factory, body.caregiver_id, user["id"], body.permissions)
    return {"ok": True}


@router.get("/caregiver/assigned-patients")
def list_assigned_patients(user: dict = Depends(get_current_user)) -> dict:
    if user["role"] not in ("caregiver", "admin"):
        raise HTTPException(status_code=403, detail="Caregivers only")
    patients = get_assigned_patients(user["id"])
    factory = _postgres_factory()
    if factory:
        # Backfill only pre-existing, verifiable patient-granted links. This
        # preserves established assignments without inventing any new ones.
        for patient in patients:
            sync_caregiver_assignment(factory, user["id"], patient["id"], patient["permissions"])
        # The database is the durable assignment index. Join it back to the
        # authorization store so stale/removed permissions can never grant UI
        # access, and never return private medical data in this listing.
        permitted = {row["patient_id"]: row["permissions"] for row in list_caregiver_assignments(factory, user["id"])}
        patients = [patient for patient in patients if permitted.get(patient["id"])]
    return {"patients": patients}


@router.get("/caregiver/{patient_id}/profile")
def caregiver_view_profile(patient_id: str, user: dict = Depends(get_current_user)) -> dict:
    """Caregiver views a patient's profile - only allowed fields."""
    perms = get_caregiver_permissions(patient_id, user["id"])
    if not perms and user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Not authorized to view this patient")
    patient = get_user_by_id(patient_id)
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    log_audit_event(user["id"], "view_profile", patient_id, f"Permissions: {perms}")
    # Filter profile to only permitted fields
    full_profile = patient["profile"]
    if "all" in perms:
        return {"profile": full_profile, "permissions": perms}
    filtered = {k: v for k, v in full_profile.items() if k in perms}
    return {"profile": filtered, "permissions": perms}


@router.get("/caregiver/{patient_id}/private")
def caregiver_view_private(
    patient_id: str,
    private_grant: Optional[str] = None,
    user: dict = Depends(get_current_user),
) -> dict:
    """Caregiver views private info - only if 'private_info' permission granted."""
    perms = get_caregiver_permissions(patient_id, user["id"])
    if "private_info" not in perms and "all" not in perms:
        raise HTTPException(status_code=403, detail="No permission to view private information")
    _validate_grant(user["id"], private_grant)
    log_audit_event(user["id"], "view_private_records", patient_id, "Access authorized via PIN grant")
    data = get_private(patient_id)
    return {"private": data}


@router.get("/auth/audit")
def list_audit_logs(user: dict = Depends(get_current_user)) -> dict:
    logs = get_audit_logs(user["id"] if user["role"] == "patient" else None)
    return {"audit_logs": logs}


@router.post("/admin/legacy-patient-link")
def link_legacy_patient_records(
    body: LegacyPatientLinkRequest,
    user: dict = Depends(get_current_user),
) -> dict:
    configured_admins = {email.strip().lower() for email in get_settings().care_admin_emails.split(",") if email.strip()}
    if user["role"] != "admin" and user["email"].lower() not in configured_admins:
        raise HTTPException(status_code=403, detail="Administrators only")
    patient = get_user_by_id(body.patient_user_id)
    if not patient or patient["role"] != "patient":
        raise HTTPException(status_code=400, detail="Target must be an existing patient account")
    container = get_container()
    if not getattr(container, "settings").database_url:
        raise HTTPException(status_code=503, detail="PostgreSQL storage is not configured")
    result = link_legacy_patient(container.repos.factory, body.legacy_patient_id, body.patient_user_id)
    log_audit_event(user["id"], "link_legacy_patient", body.patient_user_id, body.legacy_patient_id)
    return result

