"""Registered devices: list, revoke. A revoked device cannot refresh or act."""
from __future__ import annotations

from flask import Blueprint, g, jsonify, request

from ..extensions import db
from ..models import Device, RefreshToken, Staff, utcnow
from ..security import audit, json_error, require_auth, require_permission

bp = Blueprint("devices", __name__)


def _payload(device: Device, owner: Staff | None = None) -> dict:
    return {
        "public_id": device.public_id,
        "name": device.name,
        "platform": device.platform,
        "app_version": device.app_version,
        "last_seen_at": device.last_seen_at.isoformat() + "Z" if device.last_seen_at else None,
        "created_at": device.created_at.isoformat() + "Z",
        "revoked_at": device.revoked_at.isoformat() + "Z" if device.revoked_at else None,
        "owner": {"id": owner.id, "username": owner.username} if owner else None,
        "current": owner is not None and device.id == getattr(g.get("device"), "id", None),
    }


@bp.get("")
@require_auth
def list_devices():
    # A staff member always sees their own devices; device:read widens it to all.
    if "device:read" in __import__("lamaliva.security", fromlist=["x"]).role_permissions(g.staff.role):
        rows = db.session.scalars(db.select(Device).order_by(Device.created_at.desc())).all()
        owner_ids = {row.staff_id for row in rows}
        owners = {
            staff.id: staff
            for staff in db.session.scalars(db.select(Staff).where(Staff.id.in_(owner_ids))).all()
        } if owner_ids else {}
        return jsonify({"data": [_payload(row, owners.get(row.staff_id)) for row in rows]})

    rows = db.session.scalars(
        db.select(Device).where(Device.staff_id == g.staff.id).order_by(Device.created_at.desc())
    ).all()
    return jsonify({"data": [_payload(row, g.staff) for row in rows]})


@bp.post("/<public_id>/revoke")
@require_auth
def revoke_device(public_id: str):
    device = db.session.scalar(db.select(Device).where(Device.public_id == public_id))
    if device is None:
        return json_error(404, "device_not_found", "No such device.")

    is_owner = device.staff_id == g.staff.id
    from ..security import has_permission

    if not is_owner and not has_permission(g.staff.role, "device:read"):
        return json_error(403, "forbidden", "You cannot revoke this device.")

    if device.is_revoked:
        return jsonify({"data": _payload(device), "meta": {"already_revoked": True}})

    reason = str((request.get_json(silent=True) or {}).get("reason") or "revoked by user")[:160]
    device.revoked_at = utcnow()
    device.revoked_reason = reason
    db.session.query(RefreshToken).filter(
        RefreshToken.device_id == device.id, RefreshToken.revoked_at.is_(None)
    ).update({"revoked_at": utcnow()}, synchronize_session=False)

    audit("device.revoked", "device", device.public_id, after={"reason": reason})
    db.session.commit()
    return jsonify({"data": _payload(device)})


@bp.post("/register")
@require_auth
def register_device():
    """Register an additional device for the signed-in staff member."""
    data = request.get_json(silent=True) or {}
    fingerprint = str(data.get("fingerprint") or "").strip()
    if not fingerprint:
        return json_error(400, "missing_fingerprint", "fingerprint is required.")

    existing = db.session.scalar(
        db.select(Device).where(Device.staff_id == g.staff.id, Device.fingerprint == fingerprint)
    )
    if existing is not None:
        if existing.is_revoked:
            return json_error(403, "device_revoked", "This device was revoked by an administrator.")
        return jsonify({"data": _payload(existing, g.staff)})

    device = Device(
        staff_id=g.staff.id,
        name=str(data.get("name") or "New device")[:120],
        platform=str(data.get("platform") or "unknown")[:24],
        fingerprint=fingerprint[:128],
        app_version=str(data.get("app_version") or "")[:32] or None,
    )
    db.session.add(device)
    audit("device.registered", "device", device.public_id, after={"name": device.name})
    db.session.commit()
    return jsonify({"data": _payload(device, g.staff)}), 201
