"""
File-backed user store.  All data lives in data/users.json.
Schema per user:
{
  "id": str,
  "email": str,
  "password_hash": str,
  "pin_hash": str | null,
  "role": "patient" | "caregiver",
  "profile": { ... },
  "private": { ... encrypted fields ... },
  "caregiver_permissions": { "user_id": [permission, ...] },
  "created_at": iso-str
}
"""
from __future__ import annotations

import json
import time
import uuid
from pathlib import Path
from threading import Lock
from typing import Any, Optional

from backend.auth.crypto import (
    decrypt_field,
    encrypt_field,
    generate_token,
    hash_password,
    hash_pin,
    verify_password,
    verify_pin,
)

_STORE_PATH = Path(__file__).resolve().parent.parent.parent / "data" / "users.json"
_SESSIONS_PATH = Path(__file__).resolve().parent.parent.parent / "data" / "sessions.json"

# Master encryption key for private fields (loaded from env or derived)
import os as _os
_MASTER_KEY = _os.environ.get("AUTH_ENCRYPT_KEY", "alzheimer-dev-key-change-in-prod")

_LOCK = Lock()
_SESSION_LOCK = Lock()

# In-memory session store: token -> {user_id, created_at, last_seen}
_SESSIONS: dict[str, dict] = {}
_SESSION_TTL = 86400 * 7  # 7 days

# PIN brute-force protection: user_id -> {failures, locked_until}
_PIN_ATTEMPTS: dict[str, dict] = {}
_PIN_MAX_FAILURES = 5
_PIN_LOCK_SECONDS = 300  # 5 minutes


# ---------------------------------------------------------------------------
# Persistence helpers
# ---------------------------------------------------------------------------

def _load_users() -> list[dict]:
    if not _STORE_PATH.exists():
        return []
    try:
        return json.loads(_STORE_PATH.read_text(encoding="utf-8"))
    except Exception:
        return []


def _save_users(users: list[dict]) -> None:
    _STORE_PATH.parent.mkdir(parents=True, exist_ok=True)
    _STORE_PATH.write_text(json.dumps(users, indent=2, ensure_ascii=False), encoding="utf-8")


def _load_sessions() -> dict[str, dict]:
    if not _SESSIONS_PATH.exists():
        return {}
    try:
        return json.loads(_SESSIONS_PATH.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _save_sessions(sessions: dict[str, dict]) -> None:
    _SESSIONS_PATH.parent.mkdir(parents=True, exist_ok=True)
    _SESSIONS_PATH.write_text(json.dumps(sessions, indent=2, ensure_ascii=False), encoding="utf-8")


# Load sessions at startup
_SESSIONS.update(_load_sessions())


# ---------------------------------------------------------------------------
# User CRUD
# ---------------------------------------------------------------------------

def create_user(
    email: str,
    password: str,
    role: str = "patient",
    full_name: str = "",
) -> dict:
    with _LOCK:
        users = _load_users()
        if any(u["email"].lower() == email.lower() for u in users):
            raise ValueError("email_taken")
        user_id = uuid.uuid4().hex[:16]
        user = {
            "id": user_id,
            "email": email.lower().strip(),
            "password_hash": hash_password(password),
            "pin_hash": None,
            "role": role,
            "profile": {
                "full_name": full_name,
                "preferred_name": full_name.split()[0] if full_name else "",
                "avatar_url": "",
                "date_of_birth": "",
                "language": "en",
                "voice_preference": "female",
                "hobbies": [],
                "daily_routine": [],
                "important_dates": [],
                "personal_memories": [],
            },
            "private": {},           # encrypted at rest
            "caregiver_permissions": {},
            "created_at": _now_iso(),
        }
        users.append(user)
        _save_users(users)
        return _safe_user(user)


def authenticate_user(email: str, password: str) -> Optional[dict]:
    with _LOCK:
        users = _load_users()
        for u in users:
            if u["email"].lower() == email.lower():
                if verify_password(password, u["password_hash"]):
                    return _safe_user(u)
                return None
        return None


def get_user_by_id(user_id: str) -> Optional[dict]:
    with _LOCK:
        users = _load_users()
        for u in users:
            if u["id"] == user_id:
                return _safe_user(u)
        return None


def update_profile(user_id: str, profile_update: dict) -> dict:
    with _LOCK:
        users = _load_users()
        for u in users:
            if u["id"] == user_id:
                allowed = {
                    "full_name", "preferred_name", "avatar_url", "date_of_birth",
                    "language", "voice_preference", "hobbies", "daily_routine",
                    "important_dates", "personal_memories",
                }
                for k, v in profile_update.items():
                    if k in allowed:
                        u["profile"][k] = v
                _save_users(users)
                return _safe_user(u)
        raise ValueError("user_not_found")


def set_pin(user_id: str, pin: str) -> None:
    if not pin.isdigit() or len(pin) not in (4, 6):
        raise ValueError("pin_must_be_4_or_6_digits")
    with _LOCK:
        users = _load_users()
        for u in users:
            if u["id"] == user_id:
                u["pin_hash"] = hash_pin(pin)
                _save_users(users)
                return
        raise ValueError("user_not_found")


def verify_user_pin(user_id: str, pin: str) -> bool:
    """Verify PIN with brute-force protection. Returns True if correct."""
    now = time.time()
    state = _PIN_ATTEMPTS.get(user_id, {"failures": 0, "locked_until": 0})
    if now < state["locked_until"]:
        raise PermissionError("pin_locked")

    with _LOCK:
        users = _load_users()
        for u in users:
            if u["id"] == user_id:
                if u.get("pin_hash") is None:
                    return False
                ok = verify_pin(pin, u["pin_hash"])
                if ok:
                    _PIN_ATTEMPTS.pop(user_id, None)
                else:
                    state["failures"] = state.get("failures", 0) + 1
                    if state["failures"] >= _PIN_MAX_FAILURES:
                        state["locked_until"] = now + _PIN_LOCK_SECONDS
                    _PIN_ATTEMPTS[user_id] = state
                return ok
        return False


def get_private(user_id: str) -> dict:
    """Return decrypted private fields."""
    with _LOCK:
        users = _load_users()
        for u in users:
            if u["id"] == user_id:
                return _decrypt_private(u.get("private", {}), user_id)
        return {}


def update_private(user_id: str, private_update: dict) -> None:
    """Encrypt and store private fields."""
    allowed = {
        "medical_conditions", "allergies", "medications",
        "emergency_contacts", "doctor_details", "address", "caregiver_info",
    }
    with _LOCK:
        users = _load_users()
        for u in users:
            if u["id"] == user_id:
                existing = _decrypt_private(u.get("private", {}), user_id)
                for k, v in private_update.items():
                    if k in allowed:
                        existing[k] = v
                u["private"] = _encrypt_private(existing, user_id)
                _save_users(users)
                return
        raise ValueError("user_not_found")


def set_caregiver_permission(patient_id: str, caregiver_id: str, permissions: list[str]) -> None:
    with _LOCK:
        users = _load_users()
        for u in users:
            if u["id"] == patient_id:
                u["caregiver_permissions"][caregiver_id] = permissions
                _save_users(users)
                return
        raise ValueError("user_not_found")


def get_caregiver_permissions(patient_id: str, caregiver_id: str) -> list[str]:
    with _LOCK:
        users = _load_users()
        for u in users:
            if u["id"] == patient_id:
                return u.get("caregiver_permissions", {}).get(caregiver_id, [])
        return []


def get_assigned_patients(caregiver_id: str) -> list[dict]:
    with _LOCK:
        users = _load_users()
        assigned = []
        for u in users:
            if u.get("role") == "patient":
                perms = u.get("caregiver_permissions", {}).get(caregiver_id, [])
                if perms:
                    assigned.append({
                        "id": u["id"],
                        "email": u["email"],
                        "name": u.get("profile", {}).get("full_name") or u.get("profile", {}).get("preferred_name") or "Patient",
                        "preferred_name": u.get("profile", {}).get("preferred_name") or "Patient",
                        "avatar_url": u.get("profile", {}).get("avatar_url") or "",
                        "permissions": perms,
                    })
        return assigned


_AUDIT_LOGS_PATH = Path(__file__).resolve().parent.parent.parent / "data" / "audit_logs.json"


def _load_audit_logs() -> list[dict]:
    if not _AUDIT_LOGS_PATH.exists():
        return []
    try:
        return json.loads(_AUDIT_LOGS_PATH.read_text(encoding="utf-8"))
    except Exception:
        return []


def _save_audit_logs(logs: list[dict]) -> None:
    _AUDIT_LOGS_PATH.parent.mkdir(parents=True, exist_ok=True)
    _AUDIT_LOGS_PATH.write_text(json.dumps(logs, indent=2, ensure_ascii=False), encoding="utf-8")


def log_audit_event(user_id: str, action: str, target: str, details: str = "") -> dict:
    with _LOCK:
        logs = _load_audit_logs()
        event = {
            "id": uuid.uuid4().hex[:12],
            "user_id": user_id,
            "action": action,
            "target": target,
            "details": details,
            "timestamp": _now_iso(),
        }
        logs.append(event)
        _save_audit_logs(logs[-200:])
        return event


def get_audit_logs(user_id: Optional[str] = None) -> list[dict]:
    with _LOCK:
        logs = _load_audit_logs()
        if user_id:
            return list(reversed([l for l in logs if l.get("user_id") == user_id]))
        return list(reversed(logs[-50:]))


def change_password(user_id: str, old_password: str, new_password: str) -> None:
    with _LOCK:
        users = _load_users()
        for u in users:
            if u["id"] == user_id:
                if not verify_password(old_password, u["password_hash"]):
                    raise PermissionError("wrong_password")
                u["password_hash"] = hash_password(new_password)
                _save_users(users)
                return
        raise ValueError("user_not_found")


# ---------------------------------------------------------------------------
# Session management
# ---------------------------------------------------------------------------

def create_session(user_id: str, role: str) -> str:
    token = generate_token()
    with _SESSION_LOCK:
        _SESSIONS[token] = {
            "user_id": user_id,
            "role": role,
            "created_at": _now_iso(),
            "last_seen": time.time(),
        }
        _save_sessions(_SESSIONS)
    return token


def get_session(token: str) -> Optional[dict]:
    with _SESSION_LOCK:
        s = _SESSIONS.get(token)
        if s is None:
            return None
        if time.time() - s["last_seen"] > _SESSION_TTL:
            del _SESSIONS[token]
            _save_sessions(_SESSIONS)
            return None
        s["last_seen"] = time.time()
        _save_sessions(_SESSIONS)
        return s


def delete_session(token: str) -> None:
    with _SESSION_LOCK:
        _SESSIONS.pop(token, None)
        _save_sessions(_SESSIONS)


def purge_expired_sessions() -> None:
    now = time.time()
    with _SESSION_LOCK:
        expired = [t for t, s in _SESSIONS.items() if now - s["last_seen"] > _SESSION_TTL]
        for t in expired:
            del _SESSIONS[t]
        if expired:
            _save_sessions(_SESSIONS)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _now_iso() -> str:
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _safe_user(u: dict) -> dict:
    """Strip secret fields before returning to callers."""
    return {
        "id": u["id"],
        "email": u["email"],
        "role": u["role"],
        "profile": u.get("profile", {}),
        "caregiver_permissions": u.get("caregiver_permissions", {}),
        "created_at": u.get("created_at", ""),
        "has_pin": bool(u.get("pin_hash")),
    }


def _encrypt_private(data: dict, user_id: str) -> dict:
    result = {}
    for k, v in data.items():
        serialized = json.dumps(v, ensure_ascii=False)
        result[k] = encrypt_field(serialized, _MASTER_KEY, f"{user_id}:{k}")
    return result


def _decrypt_private(encrypted: dict, user_id: str) -> dict:
    result = {}
    for k, v in encrypted.items():
        try:
            result[k] = json.loads(decrypt_field(v, _MASTER_KEY, f"{user_id}:{k}"))
        except Exception:
            result[k] = v  # Return raw if decryption fails
    return result
