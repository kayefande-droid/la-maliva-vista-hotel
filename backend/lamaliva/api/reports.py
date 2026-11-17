"""Reports: occupancy, arrivals, revenue and inventory. No fabricated numbers."""
from __future__ import annotations

from datetime import date, timedelta

from flask import Blueprint, jsonify, request

from ..extensions import db
from ..models import (
    RES_CHECKED_IN,
    RES_CHECKED_OUT,
    RES_CONFIRMED,
    InventoryItem,
    Reservation,
    Room,
    RoomType,
    Staff,
)
from ..security import json_error, require_auth, require_permission

bp = Blueprint("reports", __name__)


def _range():
    today = date.today()
    try:
        since = date.fromisoformat(request.args.get("from") or (today - timedelta(days=30)).isoformat())
        until = date.fromisoformat(request.args.get("to") or today.isoformat())
    except ValueError:
        return None, None
    return since, until


@bp.get("/overview")
@require_auth
@require_permission("report:read")
def overview():
    today = date.today()
    total_rooms = db.session.scalar(
        db.select(db.func.count()).select_from(Room).where(Room.active.is_(True))
    ) or 0
    occupied = db.session.scalar(
        db.select(db.func.count()).select_from(Room).where(Room.status == "occupied")
    ) or 0
    available = db.session.scalar(
        db.select(db.func.count()).select_from(Room).where(Room.status == "available")
    ) or 0
    maintenance = db.session.scalar(
        db.select(db.func.count()).select_from(Room).where(Room.status == "maintenance")
    ) or 0

    arrivals_today = db.session.scalar(
        db.select(db.func.count())
        .select_from(Reservation)
        .where(Reservation.arrival == today, Reservation.status.in_((RES_CONFIRMED,)))
    ) or 0
    departures_today = db.session.scalar(
        db.select(db.func.count())
        .select_from(Reservation)
        .where(Reservation.departure <= today, Reservation.status == RES_CHECKED_IN)
    ) or 0
    in_house = db.session.scalar(
        db.select(db.func.count())
        .select_from(Reservation)
        .where(Reservation.status == RES_CHECKED_IN)
    ) or 0

    low_stock = db.session.scalar(
        db.select(db.func.count())
        .select_from(InventoryItem)
        .where(InventoryItem.active.is_(True), InventoryItem.quantity <= InventoryItem.reorder_level)
    ) or 0

    inventory_units = float(
        db.session.scalar(
            db.select(
                db.func.coalesce(db.func.sum(InventoryItem.quantity), 0)
            ).where(InventoryItem.active.is_(True))
        )
        or 0
    )
    inventory_value = float(
        db.session.scalar(
            db.select(
                db.func.coalesce(
                    db.func.sum(InventoryItem.quantity * InventoryItem.unit_cost), 0
                )
            ).where(InventoryItem.active.is_(True))
        )
        or 0
    )

    return jsonify(
        {
            "data": {
                "date": today.isoformat(),
                "rooms": {
                    "total": total_rooms,
                    "occupied": occupied,
                    "available": available,
                    "maintenance": maintenance,
                    "occupancy_rate": round((occupied / total_rooms) * 100, 1) if total_rooms else 0,
                },
                "today": {
                    "arrivals": arrivals_today,
                    "departures": departures_today,
                    "in_house": in_house,
                },
                "alerts": {"low_stock_items": low_stock},
                "inventory": {
                    "items": db.session.scalar(
                        db.select(db.func.count())
                        .select_from(InventoryItem)
                        .where(InventoryItem.active.is_(True))
                    )
                    or 0,
                    "low_stock": low_stock,
                    "units": round(inventory_units, 2),
                    "value": round(inventory_value, 2),
                },
            }
        }
    )


@bp.get("/occupancy")
@require_auth
@require_permission("report:read")
def occupancy():
    since, until = _range()
    if since is None:
        return json_error(400, "invalid_range", "from/to must be ISO dates.")

    rows = db.session.execute(
        db.select(RoomType.name, db.func.count(Room.id))
        .join(Room, Room.room_type_id == RoomType.id, isouter=True)
        .group_by(RoomType.name)
    ).all()

    daily = []
    cursor = since
    total_rooms = db.session.scalar(
        db.select(db.func.count()).select_from(Room).where(Room.active.is_(True))
    ) or 0
    while cursor <= until:
        occupied = db.session.scalar(
            db.select(db.func.count())
            .select_from(Reservation)
            .where(
                Reservation.status.in_((RES_CHECKED_IN, RES_CHECKED_OUT)),
                Reservation.arrival <= cursor,
                Reservation.departure > cursor,
            )
        ) or 0
        daily.append(
            {
                "date": cursor.isoformat(),
                "occupied": occupied,
                "rate": round((occupied / total_rooms) * 100, 1) if total_rooms else 0,
            }
        )
        cursor += timedelta(days=1)

    return jsonify(
        {
            "data": {
                "by_type": [{"room_type": name or "Unassigned", "rooms": count} for name, count in rows],
                "daily": daily,
                "range": {"from": since.isoformat(), "to": until.isoformat()},
            }
        }
    )


@bp.get("/revenue")
@require_auth
@require_permission("report:financial")
def revenue():
    since, until = _range()
    if since is None:
        return json_error(400, "invalid_range", "from/to must be ISO dates.")

    total = db.session.scalar(
        db.select(db.func.coalesce(db.func.sum(Reservation.total_amount), 0)).where(
            Reservation.status == RES_CHECKED_OUT,
            Reservation.arrival >= since,
            Reservation.arrival <= until,
        )
    )
    bookings = db.session.scalar(
        db.select(db.func.count()).select_from(Reservation).where(
            Reservation.arrival >= since, Reservation.arrival <= until
        )
    ) or 0
    nights = db.session.scalar(
        db.select(db.func.coalesce(db.func.sum(Reservation.departure - Reservation.arrival), 0)).where(
            Reservation.arrival >= since, Reservation.arrival <= until
        )
    )

    return jsonify(
        {
            "data": {
                "currency": "XAF",
                "range": {"from": since.isoformat(), "to": until.isoformat()},
                "checked_out_revenue": float(total or 0),
                "bookings": bookings,
                "nights_sold": int(nights or 0),
                "note": "Revenue counts checked-out stays only; it is not a projection.",
            }
        }
    )


@bp.get("/staff-activity")
@require_auth
@require_permission("report:read")
def staff_activity():
    rows = db.session.execute(
        db.select(Staff.username, Staff.role, db.func.count(Reservation.id))
        .join(Reservation, Reservation.created_by == Staff.id, isouter=True)
        .group_by(Staff.username, Staff.role)
    ).all()
    return jsonify(
        {
            "data": [
                {"username": username, "role": role, "reservations_created": count}
                for username, role, count in rows
            ]
        }
    )
