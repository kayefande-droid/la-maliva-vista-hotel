"""Rooms and room types."""
from __future__ import annotations

from flask import Blueprint, jsonify, request

from ..extensions import db
from ..models import (
    RES_CANCELLED,
    ROOM_AVAILABLE,
    ROOM_OCCUPIED,
    ROOM_STATUSES,
    Reservation,
    Room,
    RoomType,
)
from ..security import audit, json_error, require_auth, require_permission
from ._util import body, iso, money, page_args, paginated

bp = Blueprint("rooms", __name__)


def _usage() -> dict[int, dict]:
    """How hard each room has worked: stays on record and nights sold.

    Cancelled bookings never happened, so they are left out; the ranking is
    what the hotel actually used, not what was pencilled in.
    """
    rows = db.session.execute(
        db.select(
            Reservation.room_id,
            db.func.count(Reservation.id),
            db.func.coalesce(
                db.func.sum(
                    db.func.julianday(Reservation.departure)
                    - db.func.julianday(Reservation.arrival)
                ),
                0,
            ),
        )
        .where(
            Reservation.room_id.is_not(None),
            Reservation.status != RES_CANCELLED,
        )
        .group_by(Reservation.room_id)
    ).all()
    return {
        room_id: {"stays": int(stays or 0), "nights": int(round(nights or 0))}
        for room_id, stays, nights in rows
    }


def serialize_room(room: Room, usage: dict | None = None) -> dict:
    used = (usage or {}).get(room.id, {"stays": 0, "nights": 0})
    return {
        "id": room.id,
        "number": room.number,
        "floor": room.floor,
        "status": room.status,
        "housekeeping": room.housekeeping,
        "maintenance_note": room.maintenance_note,
        "notes": room.notes,
        "active": room.active,
        "usage": used,
        "room_type": {
            "id": room.room_type.id,
            "name": room.room_type.name,
            "capacity": room.room_type.capacity,
            "base_rate": money(room.room_type.base_rate),
            "size_sqm": float(room.room_type.size_sqm or 0) or None,
        }
        if room.room_type
        else None,
        "updated_at": iso(room.updated_at),
    }


@bp.get("")
@require_auth
def list_rooms():
    usage = _usage()
    limit, offset = page_args()
    query = db.select(Room).where(Room.active.is_(True))

    status = request_status()
    if status:
        query = query.where(Room.status == status)
    floor = request_floor()
    if floor is not None:
        query = query.where(Room.floor == floor)

    total = db.session.scalar(
        db.select(db.func.count()).select_from(query.subquery())
    )
    rows = db.session.scalars(query.order_by(Room.number)).all()

    # Staff asked for the rooms that earn most to come first: rank by nights
    # sold, then stays, then room number, so the list is stable between shifts.
    sort = (request.args.get("sort") or "").strip().lower()
    if sort in ("usage", "popular", "most-booked"):
        rows = sorted(
            rows,
            key=lambda room: (
                -int(usage.get(room.id, {}).get("nights", 0)),
                -int(usage.get(room.id, {}).get("stays", 0)),
                room.number,
            ),
        )
        rows = rows[offset: offset + limit]
    else:
        rows = rows[offset: offset + limit]

    return paginated(
        [serialize_room(room, usage) for room in rows], total or 0, limit, offset
    )


@bp.post("/<int:room_id>/clean")
@require_auth
@require_permission("room:clean")
def mark_cleaned(room_id: int):
    """Housekeeping finished: the room goes back into the free pool.

    Cleaning is a task, not a room state a guest sees. Once it is done the
    room is available again exactly like the rooms nobody has touched.
    """
    room = db.session.get(Room, room_id)
    if room is None:
        return json_error(404, "room_not_found", "No such room.")
    if room.status == ROOM_OCCUPIED:
        return json_error(
            409,
            "room_occupied",
            "A guest is still in this room; check them out before marking it clean.",
        )

    before = {"status": room.status, "housekeeping": room.housekeeping}
    room.status = ROOM_AVAILABLE
    room.housekeeping = "clean"
    audit(
        "room.cleaned",
        "room",
        room.id,
        before=before,
        after={"status": room.status, "housekeeping": room.housekeeping},
    )
    db.session.commit()
    return jsonify({"data": serialize_room(room, _usage())})


def request_status():
    from flask import request

    value = (request.args.get("status") or "").strip().lower()
    return value if value in ROOM_STATUSES else None


def request_floor():
    from flask import request

    raw = request.args.get("floor")
    try:
        return int(raw) if raw not in (None, "") else None
    except (TypeError, ValueError):
        return None


@bp.get("/<int:room_id>")
@require_auth
def get_room(room_id: int):
    room = db.session.get(Room, room_id)
    if room is None:
        return json_error(404, "room_not_found", "No such room.")
    return jsonify({"data": serialize_room(room, _usage())})


@bp.post("")
@require_auth
@require_permission("room:write")
def create_room():
    data = body()
    number = str(data.get("number") or "").strip()
    if not number:
        return json_error(400, "missing_number", "A room number is required.")
    if db.session.scalar(db.select(Room).where(Room.number == number)) is not None:
        return json_error(409, "duplicate_room", f"Room {number} already exists.")

    room_type_id = data.get("room_type_id")
    if room_type_id and db.session.get(RoomType, int(room_type_id)) is None:
        return json_error(400, "unknown_room_type", "That room type does not exist.")

    room = Room(
        number=number[:12],
        room_type_id=int(room_type_id) if room_type_id else None,
        floor=int(data.get("floor") or 0) or None,
        notes=(data.get("notes") or None),
    )
    db.session.add(room)
    db.session.flush()
    audit("room.created", "room", room.id, after={"number": room.number})
    db.session.commit()
    return jsonify({"data": serialize_room(room)}), 201


@bp.patch("/<int:room_id>")
@require_auth
@require_permission("room:write")
def update_room(room_id: int):
    room = db.session.get(Room, room_id)
    if room is None:
        return json_error(404, "room_not_found", "No such room.")

    data = body()
    before = {"status": room.status, "housekeeping": room.housekeeping, "notes": room.notes}

    status = data.get("status")
    if status is not None:
        if status not in ROOM_STATUSES:
            return json_error(400, "invalid_status", f"status must be one of {list(ROOM_STATUSES)}")
        room.status = status
    if "housekeeping" in data:
        room.housekeeping = str(data["housekeeping"])[:20]
    if "maintenance_note" in data:
        room.maintenance_note = (data["maintenance_note"] or None)
    if "notes" in data:
        room.notes = (data["notes"] or None)
    if "floor" in data and data["floor"] is not None:
        room.floor = int(data["floor"])
    if "room_type_id" in data and data["room_type_id"]:
        room.room_type_id = int(data["room_type_id"])

    audit(
        "room.updated",
        "room",
        room.id,
        before=before,
        after={"status": room.status, "housekeeping": room.housekeeping, "notes": room.notes},
    )
    db.session.commit()
    return jsonify({"data": serialize_room(room, _usage())})


@bp.get("/types")
@require_auth
def list_room_types():
    rows = db.session.scalars(db.select(RoomType).order_by(RoomType.name)).all()
    return jsonify(
        {
            "data": [
                {
                    "id": row.id,
                    "name": row.name,
                    "capacity": row.capacity,
                    "base_rate": money(row.base_rate),
                    "size_sqm": float(row.size_sqm or 0) or None,
                    "description": row.description,
                    "rooms": len(row.rooms),
                }
                for row in rows
            ]
        }
    )


@bp.post("/types")
@require_auth
@require_permission("room:write")
def create_room_type():
    data = body()
    name = str(data.get("name") or "").strip()
    if not name:
        return json_error(400, "missing_name", "A room type name is required.")
    if db.session.scalar(db.select(RoomType).where(RoomType.name == name)) is not None:
        return json_error(409, "duplicate_room_type", "That room type already exists.")

    row = RoomType(
        name=name[:64],
        capacity=int(data.get("capacity") or 2),
        base_rate=data.get("base_rate") or 0,
        size_sqm=data.get("size_sqm") or None,
        description=(data.get("description") or None),
    )
    db.session.add(row)
    db.session.flush()
    audit("room_type.created", "room_type", row.id, after={"name": row.name})
    db.session.commit()
    return jsonify({"data": {"id": row.id, "name": row.name}}), 201


@bp.patch("/types/<int:type_id>")
@require_auth
@require_permission("room:price")
def update_room_type(type_id: int):
    """Change a room type's nightly rate. Administrator only.

    Prices are the one thing the hotel wanted kept behind the admin role, so
    this endpoint asks for `room:price`, which no other role holds.
    """
    row = db.session.get(RoomType, type_id)
    if row is None:
        return json_error(404, "room_type_not_found", "No such room type.")

    data = body()
    before = {"name": row.name, "base_rate": money(row.base_rate)}
    if "name" in data:
        name = str(data.get("name") or "").strip()
        if not name:
            return json_error(400, "missing_name", "A room type name is required.")
        row.name = name[:64]
    if "capacity" in data:
        try:
            row.capacity = max(1, int(data["capacity"]))
        except (TypeError, ValueError):
            return json_error(400, "invalid_capacity", "capacity must be a whole number.")
    if "base_rate" in data:
        try:
            rate = float(data["base_rate"])
        except (TypeError, ValueError):
            return json_error(400, "invalid_rate", "base_rate must be a number.")
        if rate < 0:
            return json_error(400, "invalid_rate", "A nightly rate cannot be negative.")
        row.base_rate = rate
    if "size_sqm" in data:
        row.size_sqm = data["size_sqm"] or None
    if "description" in data:
        row.description = data["description"] or None

    audit(
        "room_type.updated",
        "room_type",
        row.id,
        before=before,
        after={"name": row.name, "base_rate": money(row.base_rate)},
    )
    db.session.commit()
    return jsonify(
        {
            "data": {
                "id": row.id,
                "name": row.name,
                "capacity": row.capacity,
                "base_rate": money(row.base_rate),
                "size_sqm": float(row.size_sqm) if row.size_sqm else None,
                "description": row.description,
            }
        }
    )
