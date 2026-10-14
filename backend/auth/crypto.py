"""
Cryptographic helpers using Python stdlib only.
No external dependencies required.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from typing import Optional

# ---------------------------------------------------------------------------
# Password / PIN hashing (PBKDF2-SHA256)
# ---------------------------------------------------------------------------

_ITERATIONS = 260_000  # OWASP 2023 recommendation for PBKDF2-SHA256


def hash_password(password: str) -> str:
    """Return a self-contained hash string: 'pbkdf2$iter$salt$hash'."""
    salt = secrets.token_hex(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), _ITERATIONS)
    return f"pbkdf2${_ITERATIONS}${salt}${dk.hex()}"


def verify_password(password: str, stored: str) -> bool:
    """Constant-time password verification."""
    try:
        _, iterations, salt, expected_hex = stored.split("$")
        dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), int(iterations))
        return hmac.compare_digest(dk.hex(), expected_hex)
    except Exception:
        return False


def hash_pin(pin: str) -> str:
    """Hash a numeric PIN the same way as passwords."""
    return hash_password(pin)


def verify_pin(pin: str, stored: str) -> bool:
    return verify_password(pin, stored)


# ---------------------------------------------------------------------------
# Session tokens (opaque bearer tokens, stored server-side)
# ---------------------------------------------------------------------------

def generate_token(nbytes: int = 32) -> str:
    return secrets.token_urlsafe(nbytes)


# ---------------------------------------------------------------------------
# Simple field-level encryption (XOR with SHA-256 key stream)
# Used for sensitive fields at rest in the JSON store.
# ---------------------------------------------------------------------------

def _derive_key(master_key: str, field_tag: str) -> bytes:
    return hashlib.sha256(f"{master_key}:{field_tag}".encode()).digest()


def encrypt_field(plaintext: str, master_key: str, field_tag: str = "") -> str:
    """XOR-encrypt a string field; returns base64-encoded ciphertext."""
    key = _derive_key(master_key, field_tag)
    pt_bytes = plaintext.encode()
    # Extend key stream using SHA-256 in counter mode
    key_stream = b""
    counter = 0
    while len(key_stream) < len(pt_bytes):
        key_stream += hashlib.sha256(key + counter.to_bytes(4, "big")).digest()
        counter += 1
    ct = bytes(a ^ b for a, b in zip(pt_bytes, key_stream))
    return base64.b64encode(ct).decode()


def decrypt_field(ciphertext: str, master_key: str, field_tag: str = "") -> str:
    """Decrypt a field encrypted with encrypt_field."""
    key = _derive_key(master_key, field_tag)
    ct = base64.b64decode(ciphertext.encode())
    key_stream = b""
    counter = 0
    while len(key_stream) < len(ct):
        key_stream += hashlib.sha256(key + counter.to_bytes(4, "big")).digest()
        counter += 1
    pt = bytes(a ^ b for a, b in zip(ct, key_stream))
    return pt.decode()
