"""Copy hotel data from the legacy SQLite database into the new schema.

The legacy monolith (`app.py`) and the new API use different table shapes, so
this maps one onto the other explicitly rather than copying tables across.

Dry run (default) prints exactly what would be written and touches nothing:

    cd backend
    python scripts/migrate_from_sqlite.py --source ../instance/lamaliva.db

Apply it, creating the schema first when the target is empty:

    python scripts/migrate_from_sqlite.py --source ../instance/lamaliva.db \
        --apply --create-schema

The target comes from `LAMALIVA_DATABASE_URL` (PostgreSQL in production). The
source is read with plain `sqlite3`, so the legacy file is never modified.

Re-running is safe: rooms, staff, guests and reservations are matched on their
natural keys (room number, username, guest reference, reservation reference)
and skipped when already present.
"""
from __future__ import annotations

import argparse
import os
import sqlite3
import sys
from datetime import date, datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from lamaliva import create_app  # noqa: E402
from lamaliva.extensions import db  # noqa: E402
from lamaliva.models import (  # noqa: E402
    RES_CANCELLED,
    RES_CHECKED_IN,
    RES_CHECKED_OUT,
    RES_CONFIRMED,
    RES_NO_SHOW,
    RES_PENDING,
    ROLE_ADMIN,
    ROLE_RECEPTION,
    ROOM_AVAILABLE,
    ROOM_CLEANING,
    ROOM_MAINTENANCE,
    ROOM_OCCUPIED,
    ROOM_RESERVED,
    STATUS_ACTIVE,
    Guest,
    Reservation,
    Room,
    RoomType,
    Staff,
)

# --- Legacy value maps -------------------------------------------------
ROOM_STATUS = {
    "available": ROOM_AVAILABLE,
    "occupied": ROOM_OCCUPIED,
    "maintenance": ROOM_MAINTENANCE,
    "cleaning": ROOM_CLEANING,
    "reserved": ROOM_RESERVED,
}

RES_STATUS = {
    "pending": RES_PENDING,
    "confirmed": RES_CONFIRMED,
    "checked-in": RES_CHECKED_IN,
    "checked_in": RES_CHECKED_IN,
    "checked-out": RES_CHECKED_OUT,
    "checked_out": RES_CHECKED_OUT,
    "cancelled": RES_CANCELLED,
    "canceled": RES_CANCELLED,
    "no-show": RES_NO_SHOW,
    "no_show": RES_NO_SHOW,
}

# Only real staff accounts carry over. The legacy `user` table mixed guests and
# throwaway test accounts into the same table; those are deliberately skipped.
STAFF_ROLE = {"admin": ROLE_ADMIN, "staff": ROLE_RECEPTION}


def _text(value) -> str | None:
    if value is None:
        return None
    value = str(value).strip()
    return value or None


def _to_date(value) -> date | None:
    """Legacy columns are datetimes stored as text; the new schema wants dates."""
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    raw = str(value).strip()
    if not raw:
        return None
    for pattern in ("%Y-%m-%d %H:%M:%S.%f", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(raw[:26], pattern).date()
        except ValueError:
            continue
    return datetime.fromisoformat(raw).date()


def read_source(path: str) -> dict[str, list[dict]]:
    if not os.path.exists(path):
        raise SystemExit(f"Source database not found: {path}")
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    try:
        existing = {
            row[0]
            for row in con.execute(
                "select name from sqlite_master where type='table'"
            )
        }
        out: dict[str, list[dict]] = {}
        for table in ("user", "room", "guest", "reservation"):
            if table not in existing:
                out[table] = []
                continue
            out[table] = [dict(row) for row in con.execute(f"select * from {table}")]
        return out
    finally:
        con.close()


def split_name(full: str) -> tuple[str, str]:
    parts = (full or "").split()
    if not parts:
        return ("Guest", "Guest")
    first = parts[0]
    last = " ".join(parts[1:]) if len(parts) > 1 else parts[0]
    return (first[:80], last[:80])


def build_plan(source: dict[str, list[dict]]) -> dict[str, list[dict]]:
    """Turn legacy rows into plain dicts shaped like the new models."""
    staff: list[dict] = []
    for row in source.get("user", []):
        role = STAFF_ROLE.get(str(row.get("role") or "").strip().lower())
        if role is None:
            continue
        username = _text(row.get("username"))
        email = _text(row.get("email"))
        if not username or not email:
            continue
        staff.append(
            {
                "username": username[:64],
                "email": email[:160],
                "full_name": username[:160],
                "password_hash": _text(row.get("password_hash")) or "",
                "role": role,
            }
        )

    # Room types come from the distinct `room_type` strings on the rooms.
    types: dict[str, dict] = {}
    for row in source.get("room", []):
        name = _text(row.get("room_type")) or "Standard"
        price = float(row.get("price") or 0)
        entry = types.setdefault(
            name,
            {
                "name": name[:64],
                "capacity": 2,
                "base_rate": price,
                "description": _text(row.get("description")),
            },
        )
        entry["base_rate"] = min(entry["base_rate"], price) if price else entry["base_rate"]

    rooms: list[dict] = []
    for row in source.get("room", []):
        number = _text(row.get("room_number"))
        if not number:
            continue
        type_name = _text(row.get("room_type")) or "Standard"
        status = ROOM_STATUS.get(
            str(row.get("status") or "").strip().lower(), ROOM_AVAILABLE
        )
        rooms.append(
            {
                "number": number[:12],
                "type_name": type_name,
                "floor": int(number[0]) if number[:1].isdigit() else None,
                "status": status,
                "image_url": _text(row.get("image_url")),
                "notes": _text(row.get("description")),
            }
        )

    guests: list[dict] = []
    legacy_guest_id: dict[int, str] = {}
    for row in source.get("guest", []):
        old_id = row.get("id")
        first, last = split_name(_text(row.get("name")) or "Guest")
        reference = f"G{int(old_id):05d}" if isinstance(old_id, int) else f"G{len(guests) + 1:05d}"
        legacy_guest_id[int(old_id)] = reference
        guests.append(
            {
                "reference": reference,
                "first_name": first,
                "last_name": last,
                "email": (_text(row.get("email")) or "")[:160] or None,
                "phone": (_text(row.get("phone")) or "")[:40] or None,
            }
        )

    legacy_room_number = {
        int(row["id"]): _text(row.get("room_number"))
        for row in source.get("room", [])
        if row.get("id") is not None
    }

    reservations: list[dict] = []
    for row in source.get("reservation", []):
        old_id = row.get("id")
        guest_ref = legacy_guest_id.get(int(row.get("guest_id") or 0))
        if guest_ref is None:
            continue
        arrival = _to_date(row.get("check_in"))
        departure = _to_date(row.get("check_out"))
        if arrival is None or departure is None or departure <= arrival:
            continue
        total = float(row.get("amount") or 0)
        nights = max((departure - arrival).days, 1)
        reservations.append(
            {
                "reference": f"R{int(old_id):05d}" if isinstance(old_id, int) else f"R{len(reservations) + 1:05d}",
                "guest_reference": guest_ref,
                "room_number": legacy_room_number.get(int(row.get("room_id") or 0)),
                "arrival": arrival,
                "departure": departure,
                "status": RES_STATUS.get(
                    str(row.get("status") or "").strip().lower(), RES_CONFIRMED
                ),
                "total_amount": round(total, 2),
                "rate_per_night": round(total / nights, 2),
            }
        )

    return {
        "staff": staff,
        "room_types": list(types.values()),
        "rooms": rooms,
        "guests": guests,
        "reservations": reservations,
    }


def print_plan(plan: dict[str, list[dict]], target: str) -> None:
    print(f"Target: {target}")
    print(f"  room types    {len(plan['room_types'])}")
    for t in plan["room_types"]:
        print(f"    - {t['name']} (base rate {t['base_rate']:.0f})")
    print(f"  rooms         {len(plan['rooms'])}")
    for r in plan["rooms"]:
        print(f"    - {r['number']}  {r['type_name']:<10} {r['status']}")
    print(f"  staff         {len(plan['staff'])}")
    for s in plan["staff"]:
        print(f"    - {s['username']} <{s['email']}> role={s['role']}")
    print(f"  guests        {len(plan['guests'])}")
    print(f"  reservations  {len(plan['reservations'])}")
    for r in plan["reservations"]:
        print(
            f"    - {r['reference']} room {r['room_number']} "
            f"{r['arrival']} -> {r['departure']} {r['status']} "
            f"{r['total_amount']:.0f}"
        )


def apply_plan(plan: dict[str, list[dict]]) -> dict[str, int]:
    created = {"room_types": 0, "rooms": 0, "staff": 0, "guests": 0, "reservations": 0}
    skipped = {key: 0 for key in created}

    type_by_name: dict[str, RoomType] = {}
    for entry in plan["room_types"]:
        existing = db.session.scalar(
            db.select(RoomType).where(RoomType.name == entry["name"])
        )
        if existing is not None:
            type_by_name[entry["name"]] = existing
            skipped["room_types"] += 1
            continue
        row = RoomType(
            name=entry["name"],
            capacity=entry["capacity"],
            base_rate=entry["base_rate"],
            description=entry["description"],
        )
        db.session.add(row)
        db.session.flush()
        type_by_name[entry["name"]] = row
        created["room_types"] += 1

    room_by_number: dict[str, Room] = {}
    for entry in plan["rooms"]:
        existing = db.session.scalar(
            db.select(Room).where(Room.number == entry["number"])
        )
        if existing is not None:
            room_by_number[entry["number"]] = existing
            skipped["rooms"] += 1
            continue
        row = Room(
            number=entry["number"],
            room_type_id=type_by_name[entry["type_name"]].id,
            floor=entry["floor"],
            status=entry["status"],
            notes=entry["notes"],
        )
        db.session.add(row)
        db.session.flush()
        room_by_number[entry["number"]] = row
        created["rooms"] += 1

    for entry in plan["staff"]:
        existing = db.session.scalar(
            db.select(Staff).where(Staff.username == entry["username"])
        )
        if existing is not None:
            skipped["staff"] += 1
            continue
        if db.session.scalar(db.select(Staff).where(Staff.email == entry["email"])):
            skipped["staff"] += 1
            continue
        db.session.add(
            Staff(
                username=entry["username"],
                email=entry["email"],
                full_name=entry["full_name"],
                # The legacy Argon2id hash verifies unchanged; forcing a change
                # means the carried-over credential cannot linger.
                password_hash=entry["password_hash"],
                role=entry["role"],
                status=STATUS_ACTIVE,
                must_change_password=True,
            )
        )
        created["staff"] += 1

    guest_by_ref: dict[str, Guest] = {}
    for entry in plan["guests"]:
        existing = db.session.scalar(
            db.select(Guest).where(Guest.reference == entry["reference"])
        )
        if existing is not None:
            guest_by_ref[entry["reference"]] = existing
            skipped["guests"] += 1
            continue
        row = Guest(
            reference=entry["reference"],
            first_name=entry["first_name"],
            last_name=entry["last_name"],
            email=entry["email"],
            phone=entry["phone"],
        )
        db.session.add(row)
        db.session.flush()
        guest_by_ref[entry["reference"]] = row
        created["guests"] += 1

    for entry in plan["reservations"]:
        existing = db.session.scalar(
            db.select(Reservation).where(Reservation.reference == entry["reference"])
        )
        if existing is not None:
            skipped["reservations"] += 1
            continue
        guest = guest_by_ref.get(entry["guest_reference"])
        if guest is None:
            skipped["reservations"] += 1
            continue
        room = room_by_number.get(entry["room_number"] or "")
        db.session.add(
            Reservation(
                reference=entry["reference"],
                guest_id=guest.id,
                room_id=room.id if room is not None else None,
                arrival=entry["arrival"],
                departure=entry["departure"],
                status=entry["status"],
                rate_per_night=entry["rate_per_night"],
                total_amount=entry["total_amount"],
                source="legacy-sqlite",
            )
        )
        created["reservations"] += 1

    db.session.commit()
    return {"created": created, "skipped": skipped}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, help="Legacy SQLite database")
    parser.add_argument(
        "--apply", action="store_true", help="Write to the target (default: dry run)"
    )
    parser.add_argument(
        "--create-schema",
        action="store_true",
        help="Create missing tables on the target before writing",
    )
    args = parser.parse_args(argv)

    source = read_source(args.source)
    plan = build_plan(source)

    app = create_app()
    target = app.config["SQLALCHEMY_DATABASE_URI"]
    print_plan(plan, target)

    if not args.apply:
        print("\nDry run: nothing written. Re-run with --apply to migrate.")
        return 0

    with app.app_context():
        if args.create_schema:
            db.create_all()
            print("\nSchema ensured (db.create_all()).")
        result = apply_plan(plan)
        print("\nWritten:")
        for key, value in result["created"].items():
            print(f"  {key:<13} {value}")
        print("Already present (skipped):")
        for key, value in result["skipped"].items():
            print(f"  {key:<13} {value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
