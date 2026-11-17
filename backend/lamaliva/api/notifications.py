"""Notifications and hotel settings."""
from __future__ import annotations

from flask import Blueprint, g, jsonify, request

from ..extensions import db
from ..models import HotelSetting, Notification, utcnow
from ..security import audit, json_error, require_auth, require_permission
from ._util import body, iso, page_args, paginated

bp = Blueprint("notifications", __name__)


@bp.get("/notifications")
@require_auth
def list_notifications():
    limit, offset = page_args()
    query = db.select(Notification).where(
        db.or_(Notification.staff_id == g.staff.id, Notification.staff_id.is_(None))
    )
    unread_only = (request.args.get("unread") or "").lower() in {"1", "true", "yes"}
    if unread_only:
        query = query.where(Notification.read_at.is_(None))

    total = db.session.scalar(db.select(db.func.count()).select_from(query.subquery())) or 0
    rows = db.session.scalars(
        query.order_by(Notification.created_at.desc()).limit(limit).offset(offset)
    ).all()
    return paginated(
        [
            {
                "id": row.id,
                "kind": row.kind,
                "title": row.title,
                "body": row.body,
                "read_at": iso(row.read_at),
                "created_at": iso(row.created_at),
            }
            for row in rows
        ],
        total,
        limit,
        offset,
    )


@bp.post("/notifications/<int:notification_id>/read")
@require_auth
def mark_read(notification_id: int):
    row = db.session.get(Notification, notification_id)
    if row is None:
        return json_error(404, "notification_not_found", "No such notification.")
    if row.staff_id not in (None, g.staff.id):
        return json_error(403, "forbidden", "That notification belongs to another account.")
    row.read_at = utcnow()
    db.session.commit()
    return jsonify({"data": {"id": row.id, "read_at": iso(row.read_at)}})


settings_bp = Blueprint("settings", __name__)


def serialize_settings(row: HotelSetting) -> dict:
    return {
        "name": row.name,
        "address": row.address,
        "phone": row.phone,
        "email": row.email,
        "tax_rate": float(row.tax_rate or 0),
        "currency": row.currency,
        "maps_url": row.maps_url,
        "checkin_time": row.checkin_time,
        "checkout_time": row.checkout_time,
    }


@settings_bp.get("")
@require_auth
@require_permission("settings:read")
def get_settings():
    row = db.session.scalar(db.select(HotelSetting).limit(1))
    if row is None:
        return jsonify({"data": None})
    return jsonify({"data": serialize_settings(row)})


@settings_bp.patch("")
@require_auth
@require_permission("settings:write")
def update_settings():
    row = db.session.scalar(db.select(HotelSetting).limit(1))
    if row is None:
        row = HotelSetting()
        db.session.add(row)

    data = body()
    before = serialize_settings(row)
    for field in ("name", "address", "phone", "email", "currency", "maps_url", "checkin_time", "checkout_time"):
        if field in data:
            setattr(row, field, data[field])
    if "tax_rate" in data:
        row.tax_rate = data["tax_rate"]

    audit("settings.updated", "hotel_setting", row.id or 0, before=before, after=serialize_settings(row))
    db.session.commit()
    return jsonify({"data": serialize_settings(row)})
