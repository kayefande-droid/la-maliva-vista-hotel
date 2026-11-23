"""Reports: occupancy, arrivals, revenue and inventory. No fabricated numbers."""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

from flask import Blueprint, jsonify, request

from ..extensions import db
from ..models import (
    EXTENSION_PENDING,
    PAYMENT_IN,
    PAYMENT_REFUND,
    RES_CHECKED_IN,
    RES_CHECKED_OUT,
    RES_CONFIRMED,
    Guest,
    InventoryItem,
    Payment,
    Reservation,
    Room,
    RoomType,
    ShopSale,
    Staff,
    StayExtension,
    utcnow,
)
from ..security import json_error, require_auth, require_permission
from ..stay import load_policy, stay_state


def hotel_today() -> date:
    """The day it is at the hotel, not on whatever server hosts the API."""
    return datetime.now(load_policy().tz).date()


def _utc_bounds(day: date) -> tuple[datetime, datetime]:
    """A hotel-local day expressed as naive UTC, for the naive timestamp columns."""
    tz = load_policy().tz
    start = datetime(day.year, day.month, day.day, tzinfo=tz)
    end = start + timedelta(days=1)
    return (
        start.astimezone(timezone.utc).replace(tzinfo=None),
        end.astimezone(timezone.utc).replace(tzinfo=None),
    )

bp = Blueprint("reports", __name__)


def _stay_counts() -> dict:
    """Live occupancy pressures, derived from the same engine the desk uses."""
    policy = load_policy()
    now = utcnow()
    rows = db.session.scalars(
        db.select(Reservation).where(Reservation.status == RES_CHECKED_IN)
    ).all()
    states = [stay_state(row, policy, now) for row in rows]
    pending = db.session.scalar(
        db.select(db.func.count())
        .select_from(StayExtension)
        .where(StayExtension.status == EXTENSION_PENDING)
    ) or 0
    return {
        "in_house": len(states),
        "overdue": sum(1 for state in states if state["is_overdue"]),
        "due_within_2h": sum(
            1
            for state in states
            if not state["is_overdue"]
            and state["minutes_remaining"] is not None
            and state["minutes_remaining"] <= 120
        ),
        "extension_pending": pending,
    }


def _range():
    today = hotel_today()
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
                "stays": _stay_counts(),
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


def _money_day(value) -> dict:
    """Cash actually banked on one local day, split by where it came from.

    Rooms are the payments posted against a stay (append-only, refunds
    subtracted); shop is the till. A checked-out stay does not double count:
    its money was already received through those payments.
    """
    day = date.fromisoformat(value)
    start, end = _utc_bounds(day)

    received = float(
        db.session.scalar(
            db.select(db.func.coalesce(db.func.sum(Payment.amount), 0)).where(
                Payment.kind == PAYMENT_IN,
                Payment.created_at >= start,
                Payment.created_at < end,
            )
        )
        or 0
    )
    refunded = float(
        db.session.scalar(
            db.select(db.func.coalesce(db.func.sum(Payment.amount), 0)).where(
                Payment.kind == PAYMENT_REFUND,
                Payment.created_at >= start,
                Payment.created_at < end,
            )
        )
        or 0
    )
    shop = float(
        db.session.scalar(
            db.select(db.func.coalesce(db.func.sum(ShopSale.total), 0)).where(
                ShopSale.created_at >= start,
                ShopSale.created_at < end,
            )
        )
        or 0
    )
    return {
        "date": value,
        "rooms": round(received - refunded, 2),
        "shop": round(shop, 2),
        "total": round(received - refunded + shop, 2),
    }


def _method_breakdown(since: date, until: date) -> dict[str, dict]:
    """Money received in a period, split by how it arrived (cash, MoMo...).

    A cash-up compares the drawer against the cash line, and a manager needs
    MoMo and transfer totals separately rather than one lump sum.
    """
    start, _ = _utc_bounds(since)
    _, end = _utc_bounds(until)

    rows = db.session.execute(
        db.select(
            Payment.method,
            Payment.kind,
            db.func.coalesce(db.func.sum(Payment.amount), 0),
        )
        .where(Payment.created_at >= start, Payment.created_at < end)
        .group_by(Payment.method, Payment.kind)
    ).all()
    methods: dict[str, dict] = {}
    for method, kind, total in rows:
        entry = methods.setdefault(
            str(method or "cash"), {"rooms": 0.0, "shop": 0.0, "total": 0.0}
        )
        signed = float(total or 0) if kind == PAYMENT_IN else -float(total or 0)
        entry["rooms"] = round(entry["rooms"] + signed, 2)

    sales = db.session.execute(
        db.select(
            ShopSale.method,
            db.func.coalesce(db.func.sum(ShopSale.total), 0),
        )
        .where(ShopSale.created_at >= start, ShopSale.created_at < end)
        .group_by(ShopSale.method)
    ).all()
    for method, total in sales:
        entry = methods.setdefault(
            str(method or "cash"), {"rooms": 0.0, "shop": 0.0, "total": 0.0}
        )
        entry["shop"] = round(entry["shop"] + float(total or 0), 2)

    for entry in methods.values():
        entry["total"] = round(entry["rooms"] + entry["shop"], 2)
    return dict(sorted(methods.items()))


def _bucket_rows(since: date, until: date) -> list[dict]:
    return [_money_day(cursor.isoformat()) for cursor in _dates(since, until)]


def _dates(since: date, until: date):
    cursor = since
    while cursor <= until:
        yield cursor
        cursor += timedelta(days=1)


@bp.get("/money")
@require_auth
@require_permission("report:financial")
def money():
    """The hotel's earnings, day by day, week by week and month by month.

    Every figure is money already received (payments and till sales), never a
    projection: a booking only appears here once the guest has actually paid.
    """
    since, until = _range()
    if since is None:
        return json_error(400, "invalid_range", "from/to must be ISO dates.")

    daily = _bucket_rows(since, until)

    weeks: dict[str, dict] = {}
    months: dict[str, dict] = {}
    for row in daily:
        day = date.fromisoformat(row["date"])
        monday = day - timedelta(days=day.weekday())
        week_key = monday.isoformat()
        week = weeks.setdefault(
            week_key,
            {"week_start": week_key, "rooms": 0.0, "shop": 0.0, "total": 0.0},
        )
        month_key = day.strftime("%Y-%m")
        month = months.setdefault(
            month_key,
            {"month": month_key, "rooms": 0.0, "shop": 0.0, "total": 0.0},
        )
        for bucket in (week, month):
            bucket["rooms"] = round(bucket["rooms"] + row["rooms"], 2)
            bucket["shop"] = round(bucket["shop"] + row["shop"], 2)
            bucket["total"] = round(bucket["total"] + row["total"], 2)

    today = hotel_today()
    start_of_month = today.replace(day=1)
    return jsonify(
        {
            "data": {
                "currency": "XAF",
                "range": {"from": since.isoformat(), "to": until.isoformat()},
                "today": {
                    **next(
                        (row for row in daily if row["date"] == today.isoformat()),
                        _zero_day(today.isoformat()),
                    ),
                    "by_method": _method_breakdown(today, today),
                },
                "this_month": {
                    **_period_total(start_of_month, today),
                    "by_method": _method_breakdown(start_of_month, today),
                },
                "daily": daily,
                "weekly": list(weeks.values()),
                "monthly": list(months.values()),
                "note": "Money already received from rooms and the shop; not a projection.",
            }
        }
    )


def _zero_day(value: str) -> dict:
    return {"date": value, "rooms": 0.0, "shop": 0.0, "total": 0.0}


def _period_total(since: date, until: date) -> dict:
    rows = _bucket_rows(since, until)
    return {
        "from": since.isoformat(),
        "to": until.isoformat(),
        "rooms": round(sum(row["rooms"] for row in rows), 2),
        "shop": round(sum(row["shop"] for row in rows), 2),
        "total": round(sum(row["total"] for row in rows), 2),
    }


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


@bp.get("/money/entries")
@require_auth
@require_permission("report:financial")
def money_entries():
    """Every payment and till sale behind the money figure, in plain detail.

    Management should not have to guess where a day's takings came from: a
    room payment names the room, the guest's first two names, the nights
    booked and what was handed over; a shop sale names what left the shelf and
    how many. Refunds are negative, so the list adds up to the report.
    """
    since, until = _range()
    if since is None:
        return json_error(400, "invalid_range", "from/to must be ISO dates.")
    start, end = _utc_bounds(since)
    _, end = _utc_bounds(until)

    limit = max(1, min(int(request.args.get("limit", 200) or 200), 500))

    entries: list[dict] = []
    room_rows = db.session.execute(
        db.select(Payment, Reservation, Room, Guest)
        .join(Reservation, Payment.reservation_id == Reservation.id)
        .outerjoin(Room, Reservation.room_id == Room.id)
        .join(Guest, Reservation.guest_id == Guest.id)
        .where(Payment.created_at >= start, Payment.created_at < end)
        .order_by(Payment.created_at.desc())
        .limit(limit)
    ).all()
    for payment, reservation, room, guest in room_rows:
        signed = float(payment.amount) * (1 if payment.kind == PAYMENT_IN else -1)
        # The desk knows a guest by the first two names, not a full legal name.
        short_name = " ".join(
            f"{guest.first_name} {guest.last_name}".split()[:2]
        )
        entries.append(
            {
                "kind": "room",
                "at": iso(payment.created_at),
                "amount": round(signed, 2),
                "method": payment.method,
                "reference": payment.reference,
                "room": room.number if room else None,
                "guest": short_name,
                "guest_first_name": guest.first_name,
                "guest_last_name": guest.last_name,
                "nights": (reservation.departure - reservation.arrival).days,
                "arrival": reservation.arrival.isoformat(),
                "departure": reservation.departure.isoformat(),
                "stay_reference": reservation.reference,
                "payment_kind": payment.kind,
                "note": payment.notes,
            }
        )

    sale_rows = db.session.scalars(
        db.select(ShopSale)
        .where(ShopSale.created_at >= start, ShopSale.created_at < end)
        .order_by(ShopSale.created_at.desc())
        .limit(limit)
    ).all()
    for sale in sale_rows:
        entries.append(
            {
                "kind": "shop",
                "at": iso(sale.created_at),
                "amount": round(float(sale.total or 0), 2),
                "method": sale.method,
                "reference": sale.reference,
                "item": sale.item_name,
                "quantity": float(sale.quantity or 0),
                "unit_price": float(sale.unit_price or 0),
            }
        )

    entries.sort(key=lambda row: row["at"] or "", reverse=True)
    entries = entries[:limit]
    return jsonify(
        {
            "data": entries,
            "meta": {
                "from": since.isoformat(),
                "to": until.isoformat(),
                "count": len(entries),
            },
            "totals": {"currency": "XAF", "amount": round(sum(e["amount"] for e in entries), 2)},
        }
    )
