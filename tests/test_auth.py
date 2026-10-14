"""
Tests for authentication and profile features.
Run with: pytest tests/test_auth.py -v
"""
from __future__ import annotations

import json
import os
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

# ---------------------------------------------------------------------------
# Patch the store paths before importing anything from backend.auth
# ---------------------------------------------------------------------------

_TMP_DIR = tempfile.mkdtemp()
_USERS_PATH = Path(_TMP_DIR) / "users.json"
_SESSIONS_PATH = Path(_TMP_DIR) / "sessions.json"


@pytest.fixture(autouse=True)
def _patch_store_paths(monkeypatch, tmp_path):
    """Redirect user/session files to a temp directory for isolation."""
    users_p = tmp_path / "users.json"
    sessions_p = tmp_path / "sessions.json"
    import backend.auth.store as store_mod
    monkeypatch.setattr(store_mod, "_STORE_PATH", users_p)
    monkeypatch.setattr(store_mod, "_SESSIONS_PATH", sessions_p)
    monkeypatch.setattr(store_mod, "_SESSIONS", {})
    monkeypatch.setattr(store_mod, "_PIN_ATTEMPTS", {})


# ---------------------------------------------------------------------------
# Crypto tests
# ---------------------------------------------------------------------------

class TestCrypto:
    def test_password_hash_verify(self):
        from backend.auth.crypto import hash_password, verify_password
        h = hash_password("correct-horse-battery-staple")
        assert verify_password("correct-horse-battery-staple", h)
        assert not verify_password("wrong-password", h)

    def test_pin_hash_verify(self):
        from backend.auth.crypto import hash_pin, verify_pin
        h = hash_pin("1234")
        assert verify_pin("1234", h)
        assert not verify_pin("4321", h)

    def test_encrypt_decrypt(self):
        from backend.auth.crypto import encrypt_field, decrypt_field
        plaintext = "Test sensitive value"
        ct = encrypt_field(plaintext, "test-key", "field")
        assert ct != plaintext
        assert decrypt_field(ct, "test-key", "field") == plaintext

    def test_token_uniqueness(self):
        from backend.auth.crypto import generate_token
        tokens = {generate_token() for _ in range(20)}
        assert len(tokens) == 20


# ---------------------------------------------------------------------------
# User store tests
# ---------------------------------------------------------------------------

class TestUserStore:
    def test_create_and_authenticate(self):
        from backend.auth.store import create_user, authenticate_user
        user = create_user("alice@example.com", "password123", full_name="Alice Smith")
        assert user["email"] == "alice@example.com"
        assert user["role"] == "patient"
        assert "password_hash" not in user  # safe_user strips it

        authenticated = authenticate_user("alice@example.com", "password123")
        assert authenticated is not None
        assert authenticated["id"] == user["id"]

    def test_wrong_password(self):
        from backend.auth.store import create_user, authenticate_user
        create_user("bob@example.com", "correct-pass")
        result = authenticate_user("bob@example.com", "wrong-pass")
        assert result is None

    def test_duplicate_email(self):
        from backend.auth.store import create_user
        create_user("dup@example.com", "pass1234")
        with pytest.raises(ValueError, match="email_taken"):
            create_user("dup@example.com", "pass5678")

    def test_update_profile(self):
        from backend.auth.store import create_user, update_profile
        user = create_user("carol@example.com", "pass1234", full_name="Carol")
        updated = update_profile(user["id"], {"full_name": "Carol Jones", "hobbies": ["reading", "gardening"]})
        assert updated["profile"]["full_name"] == "Carol Jones"
        assert updated["profile"]["hobbies"] == ["reading", "gardening"]

    def test_pin_set_and_verify(self):
        from backend.auth.store import create_user, set_pin, verify_user_pin
        user = create_user("dave@example.com", "pass1234")
        set_pin(user["id"], "4321")
        assert verify_user_pin(user["id"], "4321")
        assert not verify_user_pin(user["id"], "1234")

    def test_invalid_pin_format(self):
        from backend.auth.store import create_user, set_pin
        user = create_user("eve@example.com", "pass1234")
        with pytest.raises(ValueError):
            set_pin(user["id"], "abc")
        with pytest.raises(ValueError):
            set_pin(user["id"], "123")  # too short

    def test_private_info_encrypted(self, tmp_path):
        from backend.auth.store import create_user, update_private, get_private
        import backend.auth.store as store_mod
        user = create_user("frank@example.com", "pass1234")
        update_private(user["id"], {
            "medical_conditions": ["Alzheimer's disease", "Hypertension"],
            "allergies": ["Penicillin"],
            "address": "123 Main St, Springfield",
        })
        data = get_private(user["id"])
        assert data["medical_conditions"] == ["Alzheimer's disease", "Hypertension"]
        assert data["allergies"] == ["Penicillin"]
        assert data["address"] == "123 Main St, Springfield"
        # Verify it's stored encrypted (not plaintext in file)
        raw = json.loads(store_mod._STORE_PATH.read_text())
        for u in raw:
            if u["id"] == user["id"]:
                for k, v in u["private"].items():
                    assert v != data.get(k), f"Field {k!r} stored as plaintext!"

    def test_session_lifecycle(self):
        from backend.auth.store import create_user, create_session, get_session, delete_session
        user = create_user("session@example.com", "pass1234")
        token = create_session(user["id"], "patient")
        assert token and len(token) > 20
        session = get_session(token)
        assert session is not None
        assert session["user_id"] == user["id"]
        delete_session(token)
        assert get_session(token) is None

    def test_caregiver_permissions(self):
        from backend.auth.store import create_user, set_caregiver_permission, get_caregiver_permissions
        patient = create_user("patient@example.com", "pass1234", role="patient")
        caregiver = create_user("carer@example.com", "pass1234", role="caregiver")
        set_caregiver_permission(patient["id"], caregiver["id"], ["full_name", "hobbies"])
        perms = get_caregiver_permissions(patient["id"], caregiver["id"])
        assert "full_name" in perms
        assert "hobbies" in perms


# ---------------------------------------------------------------------------
# FastAPI route tests
# ---------------------------------------------------------------------------

@pytest.fixture
def client():
    from fastapi import FastAPI
    from fastapi.testclient import TestClient
    from backend.api.routes_auth import router as auth_router
    app = FastAPI()
    app.include_router(auth_router, prefix="/v1")
    return TestClient(app)


class TestAuthRoutes:
    def test_register_and_login(self, client):
        # Register
        resp = client.post("/v1/auth/register", json={
            "email": "test@memory.care",
            "password": "SecurePass123",
            "full_name": "Test User",
            "role": "patient",
        })
        assert resp.status_code == 201
        data = resp.json()
        assert "token" in data
        assert data["user"]["email"] == "test@memory.care"
        token = data["token"]

        # Me endpoint
        resp = client.get("/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
        assert resp.status_code == 200
        assert resp.json()["user"]["role"] == "patient"

        # Login
        resp = client.post("/v1/auth/login", json={
            "email": "test@memory.care",
            "password": "SecurePass123",
        })
        assert resp.status_code == 200
        assert "token" in resp.json()

    def test_wrong_password_login(self, client):
        client.post("/v1/auth/register", json={
            "email": "wrong@memory.care", "password": "RightPass123",
            "full_name": "W", "role": "patient",
        })
        resp = client.post("/v1/auth/login", json={
            "email": "wrong@memory.care", "password": "WrongPass456",
        })
        assert resp.status_code == 401

    def test_duplicate_email(self, client):
        body = {"email": "dup2@memory.care", "password": "pass12345", "full_name": "D"}
        client.post("/v1/auth/register", json=body)
        resp = client.post("/v1/auth/register", json=body)
        assert resp.status_code == 409

    def test_unauthorized_without_token(self, client):
        resp = client.get("/v1/auth/me")
        assert resp.status_code == 401

    def test_profile_update(self, client):
        resp = client.post("/v1/auth/register", json={
            "email": "profile@memory.care", "password": "SecurePass123",
            "full_name": "Profile User",
        })
        token = resp.json()["token"]
        headers = {"Authorization": f"Bearer {token}"}

        resp = client.patch("/v1/profile", json={"hobbies": ["chess", "reading"]}, headers=headers)
        assert resp.status_code == 200
        assert resp.json()["profile"]["hobbies"] == ["chess", "reading"]

    def test_pin_set_and_verify(self, client):
        resp = client.post("/v1/auth/register", json={
            "email": "pin@memory.care", "password": "SecurePass123",
            "full_name": "Pin User",
        })
        token = resp.json()["token"]
        headers = {"Authorization": f"Bearer {token}"}

        # Set PIN
        resp = client.post("/v1/auth/set-pin", json={"pin": "1234"}, headers=headers)
        assert resp.status_code == 200

        # Verify PIN → get grant
        resp = client.post("/v1/auth/verify-pin", json={"pin": "1234"}, headers=headers)
        assert resp.status_code == 200
        grant = resp.json()["private_grant"]
        assert grant

        # Access private info with grant
        resp = client.get("/v1/private", params={"private_grant": grant}, headers=headers)
        assert resp.status_code == 200

    def test_wrong_pin_rejected(self, client):
        resp = client.post("/v1/auth/register", json={
            "email": "wrongpin@memory.care", "password": "SecurePass123",
            "full_name": "W",
        })
        token = resp.json()["token"]
        headers = {"Authorization": f"Bearer {token}"}
        client.post("/v1/auth/set-pin", json={"pin": "9999"}, headers=headers)

        resp = client.post("/v1/auth/verify-pin", json={"pin": "1111"}, headers=headers)
        assert resp.status_code == 401

    def test_private_without_grant_rejected(self, client):
        resp = client.post("/v1/auth/register", json={
            "email": "nogrant@memory.care", "password": "SecurePass123",
            "full_name": "N",
        })
        token = resp.json()["token"]
        headers = {"Authorization": f"Bearer {token}"}

        resp = client.get("/v1/private", headers=headers)
        assert resp.status_code == 403
