"""The 50-character authorization key.

Rules implemented here:
* generated with `secrets` from a 32-character unambiguous alphabet, exactly 50 chars
* only an argon2 hash is stored; the plaintext is returned in one response and never logged
* displayed for three minutes (`display_until`), and the app hides it on a countdown
* single use, expires on the daily rotation schedule, and re-issued only after fresh password auth
* issuing, verifying, expiring and revoking a key are all audited
* the normal session is untouched by any of this
"""
from __future__ import annotations

from flask import Blueprint, current_app, g, jsonify, request

from ..extensions import db
from ..models import AuthKey, utcnow
from ..security import (
    audit,
    generate_auth_key,
    has_permission,
    hash_auth_key,
    json_error,
    key_prefix,
    require_auth,
    verify_auth_key,
    verify_password,
)

bp = Blueprint("auth_keys", __name__)


def _meta(row: AuthKey) -> dict:
    return {
        "id": row.id,
        "prefix": row.key_prefix,
        "purpose": row.purpose,
        "issued_at": row.issued_at.isoformat() + "Z",
        "expires_at": row.expires_at.isoformat() + "Z",
        "display_until": row.display_until.isoformat() + "Z",
        "used_at": row.used_at.isoformat() + "Z" if row.used_at else None,
        "revoked_at": row.revoked_at.isoformat() + "Z" if row.revoked_at else None,
        "state": "used" if row.used_at else ("revoked" if row.revoked_at else ("expired" if not row.is_live() else "live")),
    }


@bp.post("")
@require_auth
def issue_key():
    """Issue a fresh key. Requires the account password again, then replaces any live key."""
    if not has_permission(g.staff.role, "staff:read"):
        return json_error(403, "forbidden", "Your role cannot issue authorization keys.")

    data = request.get_json(silent=True) or {}
    password = str(data.get("password") or "")
    if not password:
        return json_error(
            400, "reauthentication_required", "Confirm your password to issue a key."
        )
    if not verify_password(g.staff.password_hash, password):
        audit("auth_key.issue_denied", "staff", g.staff.id)
        db.session.commit()
        return json_error(403, "reauthentication_failed", "Password is incorrect.")

    # Retire the previous live key: only one active key per staff member.
    now = utcnow()
    db.session.query(AuthKey).filter(
        AuthKey.staff_id == g.staff.id, AuthKey.revoked_at.is_(None), AuthKey.used_at.is_(None)
    ).update({"revoked_at": now}, synchronize_session=False)

    raw = generate_auth_key()
    row = AuthKey(
        staff_id=g.staff.id,
        key_hash=hash_auth_key(raw),
        key_prefix=key_prefix(raw),
        purpose=str(data.get("purpose") or "sensitive-operations")[:48],
        issued_at=now,
        expires_at=now + current_app.config["AUTH_KEY_TTL"],
        display_until=now + current_app.config["AUTH_KEY_DISPLAY_TTL"],
        issued_by_device_id=g.device.id,
    )
    db.session.add(row)
    db.session.flush()
    audit("auth_key.issued", "auth_key", row.id, after={"prefix": row.key_prefix})

    payload = _meta(row)
    payload["key"] = raw  # the only time the plaintext exists in a response
    return jsonify({"data": payload}), 201


@bp.get("/current")
@require_auth
def current_key():
    row = db.session.scalar(
        db.select(AuthKey)
        .where(AuthKey.staff_id == g.staff.id)
        .order_by(AuthKey.id.desc())
        .limit(1)
    )
    if row is None:
        return jsonify({"data": None})
    return jsonify({"data": _meta(row)})


@bp.post("/verify")
@require_auth
def verify_key():
    """Consume a key for one sensitive action. Single use."""
    data = request.get_json(silent=True) or {}
    raw = str(data.get("key") or "").strip()
    action = str(data.get("action") or "sensitive-action")[:64]
    if not raw:
        return json_error(400, "missing_key", "key is required.")

    candidates = db.session.scalars(
        db.select(AuthKey)
        .where(AuthKey.staff_id == g.staff.id)
        .order_by(AuthKey.id.desc())
        .limit(10)
    ).all()

    for row in candidates:
        if not verify_auth_key(row.key_hash, raw):
            continue
        if row.revoked_at is not None:
            return json_error(400, "key_revoked", "This key has been replaced by a newer one.")
        if row.used_at is not None:
            return json_error(400, "key_used", "This key has already been used.")
        if row.expires_at <= utcnow():
            return json_error(400, "key_expired", "This key has expired. Issue a new one.")

        row.used_at = utcnow()
        audit("auth_key.used", "auth_key", row.id, after={"action": action})
        db.session.commit()
        return jsonify({"data": {"authorized": True, "action": action, "used_at": row.used_at.isoformat() + "Z"}})

    audit("auth_key.verify_failed", "staff", g.staff.id, after={"action": action})
    db.session.commit()
    return json_error(400, "key_invalid", "That key is not valid for your account.")


@bp.post("/revoke")
@require_auth
def revoke_key():
    row = db.session.scalar(
        db.select(AuthKey)
        .where(AuthKey.staff_id == g.staff.id, AuthKey.revoked_at.is_(None))
        .order_by(AuthKey.id.desc())
        .limit(1)
    )
    if row is None:
        return json_error(404, "no_live_key", "There is no live key to revoke.")
    row.revoked_at = utcnow()
    audit("auth_key.revoked", "auth_key", row.id)
    db.session.commit()
    return jsonify({"data": _meta(row)})
