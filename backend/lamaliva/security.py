"""Authentication, authorization and the 50-character key.

Design rules enforced here:
* Passwords are argon2id hashes. No plaintext password is ever stored or logged.
* Access tokens are short-lived JWTs bound to a specific registered device.
* Refresh tokens are opaque, hashed at rest, rotated on use, with reuse detection.
* The 50-character key is generated with `secrets`, hashed at rest, single-use,
  expires on the daily rotation schedule, and is returned exactly once.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import re
import secrets
from datetime import datetime, timezone
from functools import wraps

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError
from flask import current_app, g, jsonify, request

from .extensions import db

_hasher = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=4, hash_len=32)

# --- Permission matrix -------------------------------------------------
# Admin holds the highest authority; every other role is explicit so nothing
# is granted by accident.
#
# Deliberate splits, because the hotel asked for them explicitly:
# * `staff:manage` (create staff accounts) and `room:price` (change rates) are
#   admin-only: they are not granted to any other role here.
# * `inventory:movement` records stock in/out/adjust as an append-only ledger;
#   `inventory:manage` (create/edit items) is admin-only, so a shift worker can
#   move stock but cannot rewrite what an item is.
PERMISSIONS: dict[str, set[str]] = {
    "admin": {"*"},
    "manager": {
        "guest:read", "guest:write", "guest:restricted",
        "room:read", "room:write",
        "reservation:read", "reservation:write", "reservation:checkin",
        # Approving an extension or authorising an outstanding balance moves
        # money and room time, so it stays with management.
        "reservation:approve",
        "inventory:read", "inventory:movement",
        "staff:read", "device:read", "audit:read",
        "report:read", "report:financial",
        "notification:read", "settings:read",
    },
    "receptionist": {
        "guest:read", "guest:write",
        "room:read",
        "reservation:read", "reservation:write", "reservation:checkin",
        "inventory:read", "inventory:movement",
        "report:read", "notification:read", "settings:read",
    },
    "housekeeping": {
        "guest:read", "room:read", "room:write", "reservation:read",
        "inventory:read", "inventory:movement", "notification:read",
    },
    "inventory": {
        "inventory:read", "inventory:movement", "room:read",
        "report:read", "notification:read",
    },
}


def role_permissions(role: str) -> set[str]:
    return PERMISSIONS.get(role, set())


def has_permission(role: str, permission: str) -> bool:
    granted = role_permissions(role)
    return "*" in granted or permission in granted


# --- Record integrity ------------------------------------------------
def seal_record(payload: dict, *, purpose: str = "record") -> str:
    """A tamper-evident seal over a record's fields.

    Keyed with the application secret, so a row edited directly in the database
    can no longer be proven to match what the desk registered. The seal is
    stored beside the record and re-checked whenever it is displayed.
    """
    key = str(current_app.config.get("SECRET_KEY") or "").encode("utf-8")
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)
    return hmac.new(key, f"{purpose}:{canonical}".encode("utf-8"), hashlib.sha256).hexdigest()


def hash_identity(value: str) -> str:
    """One-way fingerprint of an ID number, used to stop the same document
    being registered twice without storing a second copy of it."""
    key = str(current_app.config.get("SECRET_KEY") or "").encode("utf-8")
    normalised = "".join(str(value).split()).upper()
    return hmac.new(key, f"identity:{normalised}".encode("utf-8"), hashlib.sha256).hexdigest()


# --- Passwords ---------------------------------------------------------
def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password_hash: str, password: str) -> bool:
    if not password_hash or not password:
        return False
    try:
        return _hasher.verify(password_hash, password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def needs_rehash(password_hash: str) -> bool:
    try:
        return _hasher.check_needs_rehash(password_hash)
    except InvalidHashError:
        return True


def password_policy_error(password: str) -> str | None:
    minimum = current_app.config["PASSWORD_MIN_LENGTH"]
    if len(password or "") < minimum:
        return f"Password must be at least {minimum} characters."
    if not re.search(r"[A-Z]", password):
        return "Password must contain an uppercase letter."
    if not re.search(r"[a-z]", password):
        return "Password must contain a lowercase letter."
    if not re.search(r"\d", password):
        return "Password must contain a digit."
    if password.lower() in {"password", "lamaliva", "admin"}:
        return "Password is too predictable."
    return None


# --- Tokens ------------------------------------------------------------
def _now() -> datetime:
    return datetime.now(timezone.utc)


def create_access_token(staff, device) -> tuple[str, datetime]:
    now = _now()
    ttl = current_app.config["ACCESS_TOKEN_TTL"]
    expires_at = now + ttl
    payload = {
        "iss": current_app.config["JWT_ISSUER"],
        "sub": str(staff.id),
        "did": device.public_id,
        "role": staff.role,
        "jti": secrets.token_hex(16),
        "iat": int(now.timestamp()),
        "exp": int(expires_at.timestamp()),
        "typ": "access",
    }
    token = jwt.encode(
        payload, current_app.config["SECRET_KEY"], algorithm=current_app.config["JWT_ALGORITHM"]
    )
    return token, expires_at


def decode_access_token(token: str) -> dict:
    return jwt.decode(
        token,
        current_app.config["SECRET_KEY"],
        algorithms=[current_app.config["JWT_ALGORITHM"]],
        issuer=current_app.config["JWT_ISSUER"],
        options={"require": ["exp", "iat", "sub", "did"]},
    )


def new_refresh_token() -> tuple[str, str]:
    raw = secrets.token_urlsafe(48)
    return raw, hashlib.sha256(raw.encode()).hexdigest()


def hash_token(raw: str) -> str:
    return hashlib.sha256(raw.encode()).hexdigest()


# --- The 50-character authorization key --------------------------------
def generate_auth_key() -> str:
    alphabet = current_app.config["AUTH_KEY_ALPHABET"]
    length = current_app.config["AUTH_KEY_LENGTH"]
    return "".join(secrets.choice(alphabet) for _ in range(length))


def hash_auth_key(raw: str) -> str:
    return _hasher.hash(raw)


def verify_auth_key(stored_hash: str, raw: str) -> bool:
    return verify_password(stored_hash, raw)


def key_prefix(raw: str) -> str:
    """First 6 characters, safe to write to audit logs for identification."""
    return raw[:6]


# --- Request context helpers ------------------------------------------
def json_error(status: int, code: str, detail: str, **extra):
    body = {"type": f"about:blank#{code}", "title": code.replace("_", " "), "status": status, "detail": detail}
    body.update(extra)
    return jsonify(body), status


def current_token_payload() -> dict:
    return g.get("claims") or {}


def require_auth(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        header = request.headers.get("Authorization", "")
        if not header.lower().startswith("bearer "):
            return json_error(401, "unauthorized", "Missing bearer token.")
        token = header.split(" ", 1)[1].strip()
        try:
            claims = decode_access_token(token)
        except jwt.ExpiredSignatureError:
            return json_error(401, "token_expired", "Access token has expired.")
        except jwt.InvalidTokenError:
            return json_error(401, "invalid_token", "Access token is not valid.")

        from .models import Device, Staff

        staff = db.session.get(Staff, int(claims["sub"]))
        if staff is None or not staff.is_active() or staff.is_locked():
            return json_error(403, "account_unavailable", "This account is not available.")
        if claims["iat"] < int(staff.tokens_valid_from.replace(tzinfo=timezone.utc).timestamp()):
            return json_error(401, "token_revoked", "Session was invalidated. Sign in again.")

        device = db.session.scalar(db.select(Device).where(Device.public_id == claims["did"]))
        if device is None or device.is_revoked or device.staff_id != staff.id:
            return json_error(403, "device_revoked", "This device is not authorised.")

        device.last_seen_at = datetime.now(timezone.utc).replace(tzinfo=None)
        g.staff = staff
        g.device = device
        g.claims = claims
        return fn(*args, **kwargs)

    return wrapper


def require_permission(permission: str):
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            staff = g.get("staff")
            if staff is None:
                return json_error(401, "unauthorized", "Authentication required.")
            if not has_permission(staff.role, permission):
                return json_error(
                    403,
                    "forbidden",
                    f"Role '{staff.role}' lacks permission '{permission}'.",
                    required_permission=permission,
                )
            return fn(*args, **kwargs)

        return wrapper

    return decorator


def audit(action: str, entity: str, entity_id=None, before=None, after=None, **meta):
    """Record an auditable action. Never pass secrets into these fields."""
    from .models import AuditLog  # local import avoids a cycle

    staff = g.get("staff")
    device = g.get("device")
    entry = AuditLog(
        actor_id=getattr(staff, "id", None),
        actor_name=getattr(staff, "username", None),
        action=action,
        entity=entity,
        entity_id=str(entity_id) if entity_id is not None else None,
        before=before,
        after=after,
        meta=meta or None,
        ip=(request.remote_addr if request else None),
        device_id=getattr(device, "id", None),
    )
    db.session.add(entry)
    return entry
