"""Notifications and hotel settings."""
from __future__ import annotations

from flask import Blueprint, g, jsonify, request

from ..extensions import db
from ..models import HotelSetting, Notification, utcnow
from ..security import audit, json_error, require_auth, require_permission
from ..stay import FIXED_OFFSET_HOURS, StayPolicy
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
        # Accommodation and checkout policy. New values apply to stays created
        # afterwards; an existing stay keeps the clock it agreed to.
        "policy": StayPolicy.from_row(row).as_dict(),
    }


POLICY_INT_FIELDS = {
    "hourly_rate_percent": (0, 300),
    "grace_minutes": (0, 1440),
    "deposit_percent": (0, 100),
}
POLICY_MONEY_FIELDS = ("late_checkout_fee", "early_checkin_fee")
POLICY_BOOL_FIELDS = (
    "nightly_enabled",
    "hourly_enabled",
    "payment_before_occupancy",
    "extension_approval_required",
    "overdue_manager_alert",
)


def _valid_hhmm(value) -> bool:
    try:
        hours, minutes = str(value).split(":")
        return 0 <= int(hours) <= 23 and 0 <= int(minutes) <= 59
    except (TypeError, ValueError):
        return False


@settings_bp.get("")
@require_auth
@require_permission("settings:read")
def get_settings():
    row = db.session.scalar(db.select(HotelSetting).limit(1))
    if row is None:
        # The hotel always has a policy. Materialise the defaults rather than
        # returning null, so clients never have to guess at check-out times.
        row = HotelSetting()
        db.session.add(row)
        db.session.commit()
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
    for field in ("name", "address", "phone", "email", "currency", "maps_url"):
        if field in data:
            setattr(row, field, data[field])
    if "tax_rate" in data:
        row.tax_rate = data["tax_rate"]

    for field in ("checkin_time", "checkout_time"):
        if field in data:
            if not _valid_hhmm(data[field]):
                return json_error(400, "invalid_time", f"{field} must be HH:MM.")
            setattr(row, field, str(data[field]))

    if "timezone" in data:
        zone = str(data["timezone"] or "").strip()
        if zone not in FIXED_OFFSET_HOURS:
            return json_error(
                400,
                "invalid_timezone",
                "Supported timezones: " + ", ".join(sorted(FIXED_OFFSET_HOURS)) + ".",
            )
        row.timezone = zone

    for field, (low, high) in POLICY_INT_FIELDS.items():
        if field not in data:
            continue
        try:
            value = int(data[field])
        except (TypeError, ValueError):
            return json_error(400, "invalid_policy", f"{field} must be a whole number.")
        if not low <= value <= high:
            return json_error(400, "invalid_policy", f"{field} must be between {low} and {high}.")
        setattr(row, field, value)

    for field in POLICY_MONEY_FIELDS:
        if field not in data:
            continue
        try:
            value = float(data[field] or 0)
        except (TypeError, ValueError):
            return json_error(400, "invalid_policy", f"{field} must be a number.")
        if value < 0:
            return json_error(400, "invalid_policy", f"{field} cannot be negative.")
        setattr(row, field, value)

    for field in POLICY_BOOL_FIELDS:
        if field in data:
            setattr(row, field, bool(data[field]))

    if "checkout_alert_minutes" in data:
        raw = data["checkout_alert_minutes"]
        if not isinstance(raw, list) or not raw or len(raw) > 12:
            return json_error(
                400, "invalid_policy", "checkout_alert_minutes must be 1-12 minute offsets."
            )
        try:
            minutes = sorted({int(value) for value in raw}, reverse=True)
        except (TypeError, ValueError):
            return json_error(400, "invalid_policy", "Alert offsets must be whole minutes.")
        if any(abs(value) > 60 * 24 * 30 for value in minutes):
            return json_error(400, "invalid_policy", "Alert offsets must be within 30 days.")
        row.checkout_alert_minutes = minutes

    audit("settings.updated", "hotel_setting", row.id or 0, before=before, after=serialize_settings(row))
    db.session.commit()
    return jsonify({"data": serialize_settings(row)})
