"""Reservations, arrivals and departures.

Every write is audited, room status is kept consistent with the reservation
lifecycle, and double-booking is prevented at the database query level.
"""
from __future__ import annotations

import secrets
from datetime import date, datetime, timedelta

from flask import Blueprint, g, jsonify, request

from ..extensions import db
from ..models import (
    RESERVATION_STATUSES,
    RES_CANCELLED,
    RES_CHECKED_IN,
    RES_CHECKED_OUT,
    RES_CONFIRMED,
    RES_NO_SHOW,
    RES_PENDING,
    ROOM_AVAILABLE,
    ROOM_CLEANING,
    ROOM_OCCUPIED,
    Guest,
    Notification,
    Reservation,
    Room,
    utcnow,
)
from ..models import PRICING_HOURLY
from ..security import audit, has_permission, json_error, require_auth, require_permission
from ..stay import (
    StayError,
    checkout_stay,
    compute_expected_checkout,
    load_policy,
    normalize_pricing,
    quote_charge,
    sync_alerts,
)
from ._util import body, iso, money, page_args, paginated

bp = Blueprint("reservations", __name__)

LIVE_STATUSES = (RES_PENDING, RES_CONFIRMED, RES_CHECKED_IN)


def _reference() -> str:
    return "R" + secrets.token_hex(4).upper()


def _parse_date(value, field: str):
    if isinstance(value, date) and not isinstance(value, datetime):
        return value
    try:
        return date.fromisoformat(str(value))
    except (TypeError, ValueError):
        raise ValueError(f"{field} must be an ISO date (YYYY-MM-DD).")


def serialize_reservation(row: Reservation) -> dict:
    return {
        "id": row.id,
        "reference": row.reference,
        "status": row.status,
        "arrival": row.arrival.isoformat(),
        "departure": row.departure.isoformat(),
        "nights": row.nights(),
        "adults": row.adults,
        "children": row.children,
        "rate_per_night": money(row.rate_per_night),
        "total_amount": money(row.total_amount),
        "currency": row.currency,
        "source": row.source,
        "notes": row.notes,
        "guest": {
            "id": row.guest.id,
            "reference": row.guest.reference,
            "display_name": row.guest.display_name,
            "phone": row.guest.phone,
        }
        if row.guest
        else None,
        "room": {"id": row.room.id, "number": row.room.number, "status": row.room.status}
        if row.room
        else None,
        "checked_in_at": iso(row.checked_in_at),
        "checked_out_at": iso(row.checked_out_at),
        "created_at": iso(row.created_at),
        "updated_at": iso(row.updated_at),
    }


def _overlaps(room_id: int, arrival: date, departure: date) -> bool:
    conflict = db.session.scalar(
        db.select(Reservation).where(
            Reservation.room_id == room_id,
            Reservation.status.in_(LIVE_STATUSES),
            Reservation.arrival < departure,
            Reservation.departure > arrival,
        )
    )
    return conflict is not None


@bp.get("")
@require_auth
@require_permission("reservation:read")
def list_reservations():
    limit, offset = page_args()
    query = db.select(Reservation)

    status = (request.args.get("status") or "").strip().lower()
    if status in RESERVATION_STATUSES:
        query = query.where(Reservation.status == status)

    room_id = request.args.get("room_id")
    if room_id:
        query = query.where(Reservation.room_id == int(room_id))

    guest_id = request.args.get("guest_id")
    if guest_id:
        query = query.where(Reservation.guest_id == int(guest_id))

    since = request.args.get("from")
    until = request.args.get("to")
    try:
        if since:
            query = query.where(Reservation.departure >= _parse_date(since, "from"))
        if until:
            query = query.where(Reservation.arrival <= _parse_date(until, "to"))
    except ValueError as error:
        return json_error(400, "invalid_date", str(error))

    total = db.session.scalar(db.select(db.func.count()).select_from(query.subquery())) or 0
    rows = db.session.scalars(
        query.order_by(Reservation.arrival.desc(), Reservation.id.desc()).limit(limit).offset(offset)
    ).all()
    return paginated([serialize_reservation(row) for row in rows], total, limit, offset)


@bp.get("/arrivals")
@require_auth
@require_permission("reservation:read")
def arrivals():
    today = date.today()
    rows = db.session.scalars(
        db.select(Reservation)
        .where(Reservation.arrival == today, Reservation.status.in_((RES_CONFIRMED, RES_PENDING)))
        .order_by(Reservation.room_id)
    ).all()
    return jsonify({"data": [serialize_reservation(row) for row in rows], "meta": {"date": today.isoformat()}})


@bp.get("/departures")
@require_auth
@require_permission("reservation:read")
def departures():
    today = date.today()
    rows = db.session.scalars(
        db.select(Reservation)
        .where(Reservation.departure <= today, Reservation.status == RES_CHECKED_IN)
        .order_by(Reservation.room_id)
    ).all()
    return jsonify({"data": [serialize_reservation(row) for row in rows], "meta": {"date": today.isoformat()}})


@bp.get("/<int:reservation_id>")
@require_auth
@require_permission("reservation:read")
def get_reservation(reservation_id: int):
    row = db.session.get(Reservation, reservation_id)
    if row is None:
        return json_error(404, "reservation_not_found", "No such reservation.")
    return jsonify({"data": serialize_reservation(row)})


@bp.post("")
@require_auth
@require_permission("reservation:write")
def create_reservation():
    data = body()

    # Idempotency: a retried create (flaky network) must not make a second booking.
    idem = str(data.get("idempotency_key") or "").strip()
    if idem:
        existing = db.session.scalar(
            db.select(Reservation).where(Reservation.idempotency_key == idem)
        )
        if existing is not None:
            return jsonify({"data": serialize_reservation(existing), "meta": {"idempotent": True}})

    guest = db.session.get(Guest, int(data.get("guest_id") or 0))
    if guest is None:
        return json_error(400, "unknown_guest", "That guest does not exist.")

    try:
        arrival = _parse_date(data.get("arrival"), "arrival")
        departure = _parse_date(data.get("departure"), "departure")
    except ValueError as error:
        return json_error(400, "invalid_date", str(error))

    if departure <= arrival:
        return json_error(400, "invalid_stay", "Departure must be after arrival.")

    room = db.session.get(Room, int(data.get("room_id"))) if data.get("room_id") else None
    if data.get("room_id") and room is None:
        return json_error(400, "unknown_room", "That room does not exist.")
    if room is not None and _overlaps(room.id, arrival, departure):
        return json_error(409, "room_unavailable", f"Room {room.number} is already booked for those dates.")

    nights = (departure - arrival).days
    rate = data.get("rate_per_night")
    if rate is None:
        rate = room.room_type.base_rate if room and room.room_type else 0
    rate = float(rate or 0)

    row = Reservation(
        reference=_reference(),
        guest_id=guest.id,
        room_id=room.id if room else None,
        arrival=arrival,
        departure=departure,
        adults=int(data.get("adults") or 1),
        children=int(data.get("children") or 0),
        status=data.get("status") if data.get("status") in RESERVATION_STATUSES else RES_CONFIRMED,
        rate_per_night=rate,
        total_amount=rate * nights,
        source=str(data.get("source") or "reception")[:32],
        notes=(data.get("notes") or None),
        idempotency_key=idem or None,
        created_by=g.staff.id,
    )
    db.session.add(row)
    db.session.flush()

    if room is not None and room.status == ROOM_AVAILABLE and row.status != RES_CHECKED_IN:
        pass  # room stays available until check-in; the booking is the claim

    audit(
        "reservation.created",
        "reservation",
        row.id,
        after={"reference": row.reference, "room": room.number if room else None},
    )
    db.session.commit()
    return jsonify({"data": serialize_reservation(row)}), 201


@bp.patch("/<int:reservation_id>")
@require_auth
@require_permission("reservation:write")
def update_reservation(reservation_id: int):
    row = db.session.get(Reservation, reservation_id)
    if row is None:
        return json_error(404, "reservation_not_found", "No such reservation.")
    if row.status in (RES_CHECKED_OUT, RES_CANCELLED):
        return json_error(409, "finalised", "Finalised reservations are corrected, not edited.")

    data = body()
    before = {
        "arrival": row.arrival.isoformat(),
        "departure": row.departure.isoformat(),
        "room_id": row.room_id,
        "status": row.status,
    }

    try:
        arrival = _parse_date(data.get("arrival"), "arrival") if data.get("arrival") else row.arrival
        departure = (
            _parse_date(data.get("departure"), "departure") if data.get("departure") else row.departure
        )
    except ValueError as error:
        return json_error(400, "invalid_date", str(error))
    if departure <= arrival:
        return json_error(400, "invalid_stay", "Departure must be after arrival.")

    room_id = int(data["room_id"]) if data.get("room_id") else row.room_id
    if room_id and _overlaps(room_id, arrival, departure):
        other = db.session.scalar(
            db.select(Reservation).where(
                Reservation.room_id == room_id,
                Reservation.id != row.id,
                Reservation.status.in_(LIVE_STATUSES),
                Reservation.arrival < departure,
                Reservation.departure > arrival,
            )
        )
        if other is not None:
            return json_error(409, "room_unavailable", "That room is already booked for those dates.")

    row.arrival = arrival
    row.departure = departure
    row.room_id = room_id or None
    if "adults" in data:
        row.adults = int(data["adults"])
    if "children" in data:
        row.children = int(data["children"])
    if "notes" in data:
        row.notes = data["notes"]
    if "rate_per_night" in data:
        row.rate_per_night = data["rate_per_night"]
    row.total_amount = float(row.rate_per_night or 0) * row.nights()
    if data.get("status") in RESERVATION_STATUSES and row.status not in (RES_CHECKED_IN,):
        row.status = data["status"]

    audit(
        "reservation.updated",
        "reservation",
        row.id,
        before=before,
        after={
            "arrival": row.arrival.isoformat(),
            "departure": row.departure.isoformat(),
            "room_id": row.room_id,
            "status": row.status,
        },
    )
    db.session.commit()
    return jsonify({"data": serialize_reservation(row)})


@bp.post("/<int:reservation_id>/check-in")
@require_auth
@require_permission("reservation:checkin")
def check_in(reservation_id: int):
    row = db.session.get(Reservation, reservation_id)
    if row is None:
        return json_error(404, "reservation_not_found", "No such reservation.")
    if row.status == RES_CHECKED_IN:
        return jsonify({"data": serialize_reservation(row), "meta": {"already_checked_in": True}})
    if row.status not in (RES_CONFIRMED, RES_PENDING):
        return json_error(409, "invalid_state", f"Cannot check in a {row.status} reservation.")
    if row.room is None:
        return json_error(409, "no_room", "Assign a room before checking in.")
    if row.room.status == ROOM_MAINTENANCE_BLOCKED:
        return json_error(409, "room_blocked", "That room is under maintenance.")

    # The stay clock is set here, once, from the server clock in hotel time.
    policy = load_policy()
    data = body()
    requested_pricing = str(data.get("pricing_type") or "").strip().lower()
    if requested_pricing == PRICING_HOURLY and not policy.hourly_enabled:
        return json_error(
            409,
            "hourly_unavailable",
            "Hourly stays are switched off in the accommodation policy.",
        )
    pricing = normalize_pricing(data.get("pricing_type") or row.pricing_type, policy)
    hours = data.get("stay_hours")
    try:
        hours = int(hours) if hours not in (None, "") else None
    except (TypeError, ValueError):
        return json_error(400, "invalid_stay_hours", "stay_hours must be a whole number.")
    if pricing == PRICING_HOURLY and not hours:
        return json_error(400, "invalid_stay_hours", "An hourly stay needs its hours.")

    row.pricing_type = pricing
    row.stay_hours = hours if pricing == PRICING_HOURLY else None
    if row.expected_checkout_at is None:
        row.expected_checkout_at = compute_expected_checkout(
            arrival=row.arrival,
            policy=policy,
            pricing_type=pricing,
            nights=row.nights(),
            hours=row.stay_hours,
        )
        row.original_checkout_at = row.expected_checkout_at
    if pricing == PRICING_HOURLY:
        row.total_amount = quote_charge(
            nightly_rate=float(row.rate_per_night or 0),
            pricing_type=PRICING_HOURLY,
            hours=row.stay_hours or 1,
            hourly_rate_percent=policy.hourly_rate_percent,
        )

    row.status = RES_CHECKED_IN
    row.checked_in_at = utcnow()
    row.checked_in_by = g.staff.id
    row.room.status = ROOM_OCCUPIED
    sync_alerts(row, policy)

    audit(
        "reservation.checked_in",
        "reservation",
        row.id,
        after={
            "room": row.room.number,
            "expected_checkout_at": row.expected_checkout_at.isoformat()
            if row.expected_checkout_at
            else None,
            "pricing_type": row.pricing_type,
        },
    )
    db.session.add(
        Notification(
            staff_id=None,
            kind="operations",
            title=f"Guest checked in — room {row.room.number}",
            body=f"{row.guest.display_name} is now in room {row.room.number}.",
        )
    )
    db.session.commit()
    return jsonify({"data": serialize_reservation(row)})


@bp.post("/<int:reservation_id>/check-out")
@require_auth
@require_permission("reservation:checkin")
def check_out(reservation_id: int):
    row = db.session.get(Reservation, reservation_id)
    if row is None:
        return json_error(404, "reservation_not_found", "No such reservation.")
    if row.status == RES_CHECKED_OUT:
        return jsonify({"data": serialize_reservation(row), "meta": {"already_checked_out": True}})
    if row.status != RES_CHECKED_IN:
        return json_error(409, "invalid_state", "Only an in-house guest can be checked out.")

    policy = load_policy()
    data = body()
    try:
        receipt = checkout_stay(
            row,
            staff_id=g.staff.id,
            policy=policy,
            note=data.get("note"),
            # This legacy endpoint has no payment capture of its own, so the
            # acting desk user is recorded as authorising any balance rather
            # than pretending the stay was settled.
            require_settlement=False,
        )
    except StayError as error:
        return json_error(error.status, error.code, error.message)

    audit(
        "reservation.checked_out",
        "reservation",
        row.id,
        after={
            "room": row.room.number if row.room else None,
            "receipt": row.receipt_reference,
            "balance": receipt["money"]["balance"],
        },
    )
    db.session.add(
        Notification(
            staff_id=None,
            kind="operations",
            title=f"Room {row.room.number if row.room else '-'} needs cleaning",
            body=f"{row.guest.display_name if row.guest else 'Guest'} checked out.",
        )
    )
    db.session.commit()
    return jsonify({"data": serialize_reservation(row), "receipt": receipt})


@bp.post("/<int:reservation_id>/cancel")
@require_auth
@require_permission("reservation:write")
def cancel_reservation(reservation_id: int):
    row = db.session.get(Reservation, reservation_id)
    if row is None:
        return json_error(404, "reservation_not_found", "No such reservation.")
    if row.status == RES_CHECKED_IN:
        return json_error(409, "invalid_state", "Check the guest out instead of cancelling.")

    row.status = RES_CANCELLED
    audit("reservation.cancelled", "reservation", row.id)
    db.session.commit()
    return jsonify({"data": serialize_reservation(row)})


ROOM_MAINTENANCE_BLOCKED = "maintenance"


@bp.post("/register")
@require_auth
@require_permission("reservation:write")
def register_guest_into_room():
    """Register a guest and put them straight into a room, in one step.

    The desk captures genuine identification, the guest record is sealed at
    creation, the reservation is created as checked-in and the room is marked
    occupied - so the pie chart, the rooms board and the guest book cannot
    disagree about who is where.
    """
    from .guests import (
        IdentityError,
        build_guest,
        guest_error,
        serialize_guest as serialize_guest_row,
    )

    data = body()
    details = data.get("guest") if isinstance(data.get("guest"), dict) else data

    try:
        room_id = int(data.get("room_id") or 0)
    except (TypeError, ValueError):
        room_id = 0
    if not room_id:
        return json_error(400, "invalid_room", "Choose the room the guest is taking.")

    try:
        nights = max(1, min(int(data.get("nights") or 1), 365))
    except (TypeError, ValueError):
        nights = 1

    room = db.session.get(Room, room_id)
    if room is None or not room.active:
        return json_error(404, "room_not_found", "No such room.")
    if room.status == ROOM_MAINTENANCE_BLOCKED:
        return json_error(409, "room_blocked", f"Room {room.number} is under maintenance.")

    today = date.today()
    departure = today + timedelta(days=nights)
    if _overlaps(room.id, today, departure):
        return json_error(
            409,
            "room_busy",
            f"Room {room.number} already has a live booking for those dates.",
        )

    try:
        guest = build_guest(details, staff_id=g.staff.id)
    except IdentityError as error:
        return guest_error(error)

    default_rate = float(room.room_type.base_rate) if room.room_type else 0.0
    rate = default_rate
    if "rate_per_night" in data and has_permission(g.staff.role, "room:price"):
        try:
            rate = float(data["rate_per_night"])
        except (TypeError, ValueError):
            return json_error(400, "invalid_rate", "rate_per_night must be a number.")
        if rate < 0:
            return json_error(400, "invalid_rate", "A nightly rate cannot be negative.")

    try:
        adults = max(1, int(data.get("adults") or 1))
        children = max(0, int(data.get("children") or 0))
    except (TypeError, ValueError):
        return json_error(400, "invalid_occupancy", "Adults and children must be numbers.")

    db.session.add(guest)
    db.session.flush()

    reservation = Reservation(
        reference=_reference(),
        guest_id=guest.id,
        room_id=room.id,
        arrival=today,
        departure=departure,
        adults=adults,
        children=children,
        status=RES_CHECKED_IN,
        rate_per_night=rate,
        total_amount=rate * nights,
        currency="XAF",
        source="reception",
        notes=(str(data.get("notes") or "")[:2000] or None),
        checked_in_at=utcnow(),
        checked_in_by=g.staff.id,
        created_by=g.staff.id,
    )
    db.session.add(reservation)

    # Registration puts the guest in the room immediately, so the clock starts
    # now: the agreed checkout is the policy checkout time N nights from today.
    policy = load_policy()
    reservation.pricing_type = "nightly"
    reservation.expected_checkout_at = compute_expected_checkout(
        arrival=today, policy=policy, pricing_type="nightly", nights=nights
    )
    reservation.original_checkout_at = reservation.expected_checkout_at

    room.status = ROOM_OCCUPIED
    db.session.flush()
    sync_alerts(reservation, policy)

    audit(
        "reservation.registered",
        "reservation",
        reservation.id,
        after={
            "guest": guest.reference,
            "room": room.number,
            "seal": guest.record_seal,
        },
    )
    db.session.add(
        Notification(
            staff_id=None,
            kind="operations",
            title=f"Guest registered - room {room.number}",
            body=f"{guest.display_name} was registered into room {room.number} for {nights} night(s).",
        )
    )
    db.session.commit()

    return (
        jsonify(
            {
                "data": {
                    "guest": serialize_guest_row(
                        guest, has_permission(g.staff.role, "guest:restricted")
                    ),
                    "reservation": serialize_reservation(reservation),
                }
            }
        ),
        201,
    )
