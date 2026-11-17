"""Authentication: sign in, refresh, sign out, profile, password change."""
from __future__ import annotations

import hashlib
from datetime import datetime, timezone

from flask import Blueprint, current_app, g, jsonify, request

from ..extensions import db
from ..models import (
    STATUS_ACTIVE,
    Device,
    RefreshToken,
    Staff,
    expires,
    utcnow,
)
from ..security import (
    audit,
    create_access_token,
    hash_password,
    json_error,
    needs_rehash,
    new_refresh_token,
    password_policy_error,
    require_auth,
    role_permissions,
    verify_password,
)

bp = Blueprint("auth", __name__)


def _body() -> dict:
    data = request.get_json(silent=True)
    return data if isinstance(data, dict) else {}


def _find_staff(identifier: str) -> Staff | None:
    if not identifier:
        return None
    identifier = identifier.strip()
    return db.session.scalar(
        db.select(Staff).where(
            db.or_(
                db.func.lower(Staff.username) == identifier.lower(),
                db.func.lower(Staff.email) == identifier.lower(),
            )
        )
    )


def _staff_payload(staff: Staff) -> dict:
    return {
        "id": staff.id,
        "username": staff.username,
        "email": staff.email,
        "full_name": staff.full_name,
        "role": staff.role,
        "status": staff.status,
        "must_change_password": staff.must_change_password,
        "totp_enabled": staff.totp_enabled,
        "last_login_at": staff.last_login_at.isoformat() + "Z" if staff.last_login_at else None,
    }


def _device_payload(device: Device) -> dict:
    return {
        "public_id": device.public_id,
        "name": device.name,
        "platform": device.platform,
        "last_seen_at": device.last_seen_at.isoformat() + "Z" if device.last_seen_at else None,
    }


def _issue_tokens(staff: Staff, device: Device) -> dict:
    access, access_expires = create_access_token(staff, device)
    raw_refresh, refresh_hash = new_refresh_token()
    row = RefreshToken(
        token_hash=refresh_hash,
        staff_id=staff.id,
        device_id=device.id,
        family_id=hashlib.sha256(raw_refresh.encode()).hexdigest()[:32],
        expires_at=expires(current_app.config["REFRESH_TOKEN_TTL"]),
    )
    db.session.add(row)
    return {
        "access_token": access,
        "token_type": "Bearer",
        "expires_in": int((access_expires - datetime.now(timezone.utc)).total_seconds()),
        "expires_at": access_expires.isoformat(),
        "refresh_token": raw_refresh,
        "refresh_expires_at": row.expires_at.isoformat() + "Z",
    }


@bp.post("/login")
def login():
    data = _body()
    identifier = str(data.get("username") or data.get("email") or "")
    password = str(data.get("password") or "")
    device_info = data.get("device") or {}
    if not isinstance(device_info, dict):
        device_info = {}

    staff = _find_staff(identifier)
    # Same response for unknown account and wrong password: no account probing.
    if staff is None:
        return json_error(401, "invalid_credentials", "Incorrect username or password.")

    if staff.is_locked():
        return json_error(423, "account_locked", "Too many failed attempts. Try again later.")

    if not verify_password(staff.password_hash, password):
        staff.failed_logins = (staff.failed_logins or 0) + 1
        if staff.failed_logins >= current_app.config["LOGIN_MAX_FAILURES"]:
            from datetime import timedelta

            staff.locked_until = utcnow() + timedelta(
                minutes=current_app.config["LOGIN_LOCK_MINUTES"]
            )
            staff.failed_logins = 0
            db.session.add(staff)
            db.session.commit()
            return json_error(
                423, "account_locked", "Too many failed attempts. Account locked for 15 minutes."
            )
        db.session.add(staff)
        db.session.commit()
        return json_error(401, "invalid_credentials", "Incorrect username or password.")

    if staff.status != STATUS_ACTIVE:
        return json_error(403, "account_suspended", "This account is suspended.")

    fingerprint = str(device_info.get("fingerprint") or "").strip() or f"unregistered-{staff.id}"
    device = db.session.scalar(
        db.select(Device).where(
            Device.staff_id == staff.id, Device.fingerprint == fingerprint
        )
    )
    if device is not None and device.is_revoked:
        return json_error(403, "device_revoked", "This device has been revoked by an administrator.")

    if device is None:
        device = Device(
            staff_id=staff.id,
            name=str(device_info.get("name") or "Unknown device")[:120],
            platform=str(device_info.get("platform") or "unknown")[:24],
            fingerprint=fingerprint[:128],
            app_version=str(device_info.get("app_version") or "")[:32] or None,
        )
        db.session.add(device)
    device.last_seen_at = utcnow()
    db.session.flush()

    staff.failed_logins = 0
    staff.locked_until = None
    staff.last_login_at = utcnow()
    if needs_rehash(staff.password_hash):
        staff.password_hash = hash_password(password)

    tokens = _issue_tokens(staff, device)
    audit("auth.login", "staff", staff.id, after={"device": device.public_id})
    db.session.commit()

    return jsonify(
        {
            "data": {
                "staff": _staff_payload(staff),
                "permissions": sorted(role_permissions(staff.role)),
                "device": _device_payload(device),
                **tokens,
            }
        }
    )


@bp.post("/refresh")
def refresh():
    raw = str(_body().get("refresh_token") or "")
    if not raw:
        return json_error(400, "missing_refresh_token", "refresh_token is required.")

    from ..security import hash_token

    row = db.session.scalar(
        db.select(RefreshToken).where(RefreshToken.token_hash == hash_token(raw))
    )
    if row is None:
        return json_error(401, "invalid_refresh_token", "Refresh token is not recognised.")

    if row.revoked_at is not None or row.used_at is not None:
        # Reuse of a spent token means the token leaked: kill the whole family.
        db.session.query(RefreshToken).filter(
            RefreshToken.family_id == row.family_id, RefreshToken.revoked_at.is_(None)
        ).update({"revoked_at": utcnow()}, synchronize_session=False)
        db.session.commit()
        return json_error(
            401, "refresh_token_reused", "Session revoked. Sign in again."
        )

    if row.expires_at <= utcnow():
        row.revoked_at = utcnow()
        db.session.commit()
        return json_error(401, "refresh_token_expired", "Session expired. Sign in again.")

    staff = db.session.get(Staff, row.staff_id)
    device = db.session.get(Device, row.device_id)
    if staff is None or device is None or device.is_revoked or not staff.is_active():
        return json_error(403, "session_revoked", "This session is no longer valid.")

    row.used_at = utcnow()
    row.revoked_at = utcnow()
    device.last_seen_at = utcnow()
    tokens = _issue_tokens(staff, device)
    # Keep the rotation family stable for reuse detection.
    newest = db.session.scalar(
        db.select(RefreshToken).order_by(RefreshToken.id.desc()).limit(1)
    )
    if newest is not None:
        newest.family_id = row.family_id
    db.session.commit()

    return jsonify({"data": {"staff": _staff_payload(staff), **tokens}})


@bp.post("/logout")
@require_auth
def logout():
    raw = str(_body().get("refresh_token") or "")
    if raw:
        from ..security import hash_token

        row = db.session.scalar(
            db.select(RefreshToken).where(RefreshToken.token_hash == hash_token(raw))
        )
        if row is not None and row.staff_id == g.staff.id:
            row.revoked_at = utcnow()
    audit("auth.logout", "staff", g.staff.id)
    db.session.commit()
    return jsonify({"data": {"signed_out": True}})


@bp.get("/me")
@require_auth
def me():
    return jsonify(
        {
            "data": {
                "staff": _staff_payload(g.staff),
                "permissions": sorted(role_permissions(g.staff.role)),
                "device": _device_payload(g.device),
            }
        }
    )


@bp.post("/change-password")
@require_auth
def change_password():
    data = _body()
    current = str(data.get("current_password") or "")
    new = str(data.get("new_password") or "")

    if not verify_password(g.staff.password_hash, current):
        return json_error(403, "wrong_password", "Current password is incorrect.")

    problem = password_policy_error(new)
    if problem:
        return json_error(400, "weak_password", problem)
    if verify_password(g.staff.password_hash, new):
        return json_error(400, "password_reused", "Choose a password you have not used here.")

    g.staff.password_hash = hash_password(new)
    g.staff.must_change_password = False
    g.staff.password_changed_at = utcnow()
    # Invalidate every other session; keep this device signed in.
    g.staff.tokens_valid_from = utcnow()
    db.session.query(RefreshToken).filter(
        RefreshToken.staff_id == g.staff.id,
        RefreshToken.device_id != g.device.id,
        RefreshToken.revoked_at.is_(None),
    ).update({"revoked_at": utcnow()}, synchronize_session=False)

    audit("auth.password_changed", "staff", g.staff.id)
    db.session.commit()

    tokens = _issue_tokens(g.staff, g.device)
    db.session.commit()
    return jsonify({"data": {"changed": True, "staff": _staff_payload(g.staff), **tokens}})
