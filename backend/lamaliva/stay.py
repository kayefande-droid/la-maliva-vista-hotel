"""The stay clock: policy, expiry, money and alerts.

Occupancy state is derived from the server clock every time it is read, never
stored, so the Windows and Android clients can never disagree with each other
or with the desk.

Expiry is not checkout. A stay that runs past `expected_checkout_at` becomes
overdue but the room stays occupied, the reservation stays checked in, and only
the desk can check the guest out — after which housekeeping still has to
release the room. Nothing in this module frees a room on a timer.
"""
from __future__ import annotations

import secrets
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone

from .extensions import db
from .models import (
    EXTENSION_APPROVED,
    EXTENSION_PENDING,
    EXTENSION_REJECTED,
    PAYMENT_IN,
    PAYMENT_REFUND,
    PAY_PAID,
    PAY_PARTIAL,
    PAY_REFUNDED,
    PAY_UNPAID,
    PRICING_CUSTOM,
    PRICING_HOURLY,
    PRICING_NIGHTLY,
    PRICING_TYPES,
    RES_CHECKED_IN,
    RES_CHECKED_OUT,
    RES_CANCELLED,
    RES_NO_SHOW,
    STAY_ACTIVE,
    STAY_CHECKED_OUT,
    STAY_CHECKOUT_APPROACHING,
    STAY_CHECKOUT_DUE,
    STAY_OVERDUE,
    STAY_RESERVED,
    HotelSetting,
    Notification,
    Payment,
    Reservation,
    StayAlert,
    StayExtension,
    utcnow,
)

# Africa/Douala is WAT all year: no daylight saving, so a fixed offset is the
# honest model and it works on machines without the tz database installed.
FIXED_OFFSET_HOURS = {
    "Africa/Douala": 1,
    "Africa/Yaounde": 1,
    "Africa/Lagos": 1,
    "WAT": 1,
    "UTC": 0,
}

DEFAULT_POLICY = {
    "timezone": "Africa/Douala",
    "checkin_time": "14:00",
    "checkout_time": "12:00",
    "nightly_enabled": True,
    "hourly_enabled": False,
    "hourly_rate_percent": 30,
    "grace_minutes": 30,
    "late_checkout_fee": 0.0,
    "early_checkin_fee": 0.0,
    "deposit_percent": 0,
    "payment_before_occupancy": False,
    "extension_approval_required": True,
    "checkout_alert_minutes": [1440, 360, 120, 30, 0, -60],
    "overdue_manager_alert": True,
}

APPROACHING_WINDOW_MINUTES = 120


class StayError(Exception):
    """A refusal the router turns into a 4xx with a stable code."""

    def __init__(self, status: int, code: str, message: str, details: dict | None = None):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.details = details or {}


def _settings_row() -> HotelSetting | None:
    return db.session.scalar(db.select(HotelSetting).limit(1))


def parse_hhmm(value, fallback: str) -> time:
    raw = str(value or fallback or "").strip()
    try:
        hours, minutes = raw.split(":", 1)
        return time(int(hours), int(minutes))
    except (TypeError, ValueError):
        hours, minutes = fallback.split(":", 1)
        return time(int(hours), int(minutes))


@dataclass(frozen=True)
class StayPolicy:
    timezone: str
    checkin_time: time
    checkout_time: time
    nightly_enabled: bool
    hourly_enabled: bool
    hourly_rate_percent: int
    grace_minutes: int
    late_checkout_fee: float
    early_checkin_fee: float
    deposit_percent: int
    payment_before_occupancy: bool
    extension_approval_required: bool
    checkout_alert_minutes: tuple[int, ...]
    overdue_manager_alert: bool

    @classmethod
    def from_row(cls, row: HotelSetting | None) -> "StayPolicy":
        values = dict(DEFAULT_POLICY)
        if row is not None:
            for field in DEFAULT_POLICY:
                current = getattr(row, field, None)
                if current is not None:
                    values[field] = current
        alerts = values.get("checkout_alert_minutes") or DEFAULT_POLICY["checkout_alert_minutes"]
        try:
            minutes = tuple(sorted({int(value) for value in alerts}, reverse=True))
        except (TypeError, ValueError):
            minutes = tuple(DEFAULT_POLICY["checkout_alert_minutes"])
        return cls(
            timezone=str(values["timezone"] or "Africa/Douala"),
            checkin_time=parse_hhmm(values["checkin_time"], "14:00"),
            checkout_time=parse_hhmm(values["checkout_time"], "12:00"),
            nightly_enabled=bool(values["nightly_enabled"]),
            hourly_enabled=bool(values["hourly_enabled"]),
            hourly_rate_percent=max(0, int(values["hourly_rate_percent"] or 0)),
            grace_minutes=max(0, int(values["grace_minutes"] or 0)),
            late_checkout_fee=float(values["late_checkout_fee"] or 0),
            early_checkin_fee=float(values["early_checkin_fee"] or 0),
            deposit_percent=max(0, int(values["deposit_percent"] or 0)),
            payment_before_occupancy=bool(values["payment_before_occupancy"]),
            extension_approval_required=bool(values["extension_approval_required"]),
            checkout_alert_minutes=minutes,
            overdue_manager_alert=bool(values["overdue_manager_alert"]),
        )

    @property
    def tz(self) -> timezone:
        return timezone(timedelta(hours=FIXED_OFFSET_HOURS.get(self.timezone, 1)))

    def as_dict(self) -> dict:
        return {
            "timezone": self.timezone,
            "checkin_time": self.checkin_time.strftime("%H:%M"),
            "checkout_time": self.checkout_time.strftime("%H:%M"),
            "nightly_enabled": self.nightly_enabled,
            "hourly_enabled": self.hourly_enabled,
            "hourly_rate_percent": self.hourly_rate_percent,
            "grace_minutes": self.grace_minutes,
            "late_checkout_fee": self.late_checkout_fee,
            "early_checkin_fee": self.early_checkin_fee,
            "deposit_percent": self.deposit_percent,
            "payment_before_occupancy": self.payment_before_occupancy,
            "extension_approval_required": self.extension_approval_required,
            "checkout_alert_minutes": list(self.checkout_alert_minutes),
            "overdue_manager_alert": self.overdue_manager_alert,
        }


def load_policy() -> StayPolicy:
    return StayPolicy.from_row(_settings_row())


def local_now(policy: StayPolicy) -> datetime:
    return datetime.now(timezone.utc).astimezone(policy.tz)


def to_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


def from_utc(value: datetime | None, policy: StayPolicy) -> datetime | None:
    if value is None:
        return None
    return value.replace(tzinfo=timezone.utc).astimezone(policy.tz)


def combine_local(day: date, at: time, policy: StayPolicy) -> datetime:
    return datetime.combine(day, at, tzinfo=policy.tz)


def compute_expected_checkout(
    *,
    arrival: date,
    policy: StayPolicy,
    pricing_type: str = PRICING_NIGHTLY,
    nights: int = 1,
    hours: int | None = None,
    start_at: datetime | None = None,
) -> datetime:
    """The authoritative expiry instant (naive UTC) for a new stay.

    Nightly stays run to the policy checkout time on the departure date; an
    hourly stay runs its booked hours from the moment it starts. A nightly
    stay whose computed checkout has already passed (late check-in) rolls
    forward whole days rather than starting expired.
    """
    now = local_now(policy)
    if pricing_type == PRICING_HOURLY:
        anchor = from_utc(start_at, policy) if start_at else now
        return to_utc(anchor + timedelta(hours=max(int(hours or 1), 1)))

    span = max(int(nights or 1), 1)
    checkout_at = combine_local(arrival + timedelta(days=span), policy.checkout_time, policy)
    while checkout_at <= now:
        checkout_at += timedelta(days=1)
    return to_utc(checkout_at)


def quote_charge(
    *,
    nightly_rate: float,
    pricing_type: str,
    nights: int = 1,
    hours: int = 1,
    hourly_rate_percent: int = 30,
    custom_amount: float | None = None,
) -> float:
    if pricing_type == PRICING_HOURLY:
        hourly = float(nightly_rate or 0) * (max(0, int(hourly_rate_percent)) / 100.0)
        return round(hourly * max(int(hours or 1), 1), 2)
    if pricing_type == PRICING_CUSTOM and custom_amount is not None:
        return round(float(custom_amount), 2)
    return round(float(nightly_rate or 0) * max(int(nights or 1), 1), 2)


def normalize_pricing(pricing_type: str | None, policy: StayPolicy) -> str:
    value = str(pricing_type or PRICING_NIGHTLY).strip().lower()
    if value not in PRICING_TYPES:
        return PRICING_NIGHTLY
    if value == PRICING_HOURLY and not policy.hourly_enabled:
        return PRICING_NIGHTLY
    if value == PRICING_NIGHTLY and not policy.nightly_enabled:
        return PRICING_HOURLY if policy.hourly_enabled else PRICING_NIGHTLY
    return value


# --- Money -------------------------------------------------------------
def approved_extension_charges(reservation: Reservation) -> float:
    return round(
        sum(
            float(row.additional_charge or 0)
            for row in reservation.extensions
            if row.status == EXTENSION_APPROVED
        ),
        2,
    )


def payment_totals(reservation: Reservation) -> dict:
    paid = round(
        sum(float(row.amount or 0) for row in reservation.payments if row.kind == PAYMENT_IN), 2
    )
    refunded = round(
        sum(float(row.amount or 0) for row in reservation.payments if row.kind == PAYMENT_REFUND),
        2,
    )
    net_paid = round(paid - refunded, 2)
    room_charge = round(float(reservation.total_amount or 0), 2)
    extension_charges = approved_extension_charges(reservation)
    total_charges = round(room_charge + extension_charges, 2)
    balance = round(total_charges - net_paid, 2)
    if net_paid <= 0:
        state = PAY_UNPAID
    elif balance <= 0:
        state = PAY_PAID
    elif net_paid > 0 and net_paid < total_charges:
        state = PAY_PARTIAL
    else:
        state = PAY_REFUNDED
    return {
        "currency": reservation.currency,
        "room_charge": room_charge,
        "extension_charges": extension_charges,
        "total_charges": total_charges,
        "paid": paid,
        "refunded": refunded,
        "net_paid": net_paid,
        "balance": balance,
        "overpaid": round(max(-balance, 0), 2),
        "payment_state": state,
        "settled": balance <= 0,
    }


# --- Occupancy ---------------------------------------------------------
def stay_state(reservation: Reservation, policy: StayPolicy, now: datetime | None = None) -> dict:
    now = now or utcnow()
    if reservation.status == RES_CHECKED_OUT:
        return {
            "state": STAY_CHECKED_OUT,
            "minutes_remaining": None,
            "is_overdue": False,
            "overdue_minutes": 0,
            "in_house": False,
            "room_held": False,
        }
    if reservation.status in (RES_CANCELLED, RES_NO_SHOW):
        return {
            "state": STAY_RESERVED,
            "minutes_remaining": None,
            "is_overdue": False,
            "overdue_minutes": 0,
            "in_house": False,
            "room_held": False,
        }
    if reservation.status != RES_CHECKED_IN or reservation.expected_checkout_at is None:
        return {
            "state": STAY_RESERVED,
            "minutes_remaining": None,
            "is_overdue": False,
            "overdue_minutes": 0,
            "in_house": False,
            "room_held": reservation.status == RES_CHECKED_IN,
        }

    remaining = (reservation.expected_checkout_at - now).total_seconds() / 60.0
    if remaining < 0:
        state = STAY_OVERDUE
    elif remaining <= 30:
        state = STAY_CHECKOUT_DUE
    elif remaining <= APPROACHING_WINDOW_MINUTES:
        state = STAY_CHECKOUT_APPROACHING
    else:
        state = STAY_ACTIVE

    overdue_minutes = int(max(-remaining, 0))
    return {
        "state": state,
        "minutes_remaining": int(remaining),
        "is_overdue": remaining < 0,
        "overdue_minutes": overdue_minutes,
        "in_grace": 0 < overdue_minutes <= policy.grace_minutes,
        "late_fee_applies": overdue_minutes > policy.grace_minutes,
        "in_house": True,
        # An overdue stay still holds the room until the desk checks them out.
        "room_held": True,
    }


def pending_extension(reservation: Reservation) -> StayExtension | None:
    return next(
        (row for row in reservation.extensions if row.status == EXTENSION_PENDING), None
    )


def serialize_extension(row: StayExtension, policy: StayPolicy) -> dict:
    return {
        "id": row.id,
        "minutes": row.minutes,
        "pricing_type": row.pricing_type,
        "additional_charge": float(row.additional_charge or 0),
        "original_checkout_at": row.original_checkout_at.isoformat(),
        "new_checkout_at": row.new_checkout_at.isoformat(),
        "new_checkout_local": from_utc(row.new_checkout_at, policy).isoformat(),
        "status": row.status,
        "note": row.note,
        "conflict_note": row.conflict_note,
        "requested_by": row.requested_by,
        "approved_by": row.approved_by,
        "created_at": row.created_at.isoformat(),
        "decided_at": row.decided_at.isoformat() if row.decided_at else None,
    }


def serialize_payment(row: Payment) -> dict:
    return {
        "id": row.id,
        "kind": row.kind,
        "amount": float(row.amount or 0),
        "currency": row.currency,
        "method": row.method,
        "reference": row.reference,
        "notes": row.notes,
        "received_by": row.received_by,
        "created_at": row.created_at.isoformat(),
    }


def serialize_stay(
    reservation: Reservation, policy: StayPolicy | None = None, now: datetime | None = None
) -> dict:
    policy = policy or load_policy()
    now = now or utcnow()
    clock = stay_state(reservation, policy, now)
    money = payment_totals(reservation)
    pending = pending_extension(reservation)
    expected_local = from_utc(reservation.expected_checkout_at, policy)
    return {
        "reservation": {
            "id": reservation.id,
            "reference": reservation.reference,
            "status": reservation.status,
            "arrival": reservation.arrival.isoformat(),
            "departure": reservation.departure.isoformat(),
            "nights": reservation.nights(),
            "created_by": reservation.created_by,
        },
        "guest": {
            "id": reservation.guest.id,
            "reference": reservation.guest.reference,
            "display_name": reservation.guest.display_name,
            "phone": reservation.guest.phone,
        }
        if reservation.guest
        else None,
        "room": {
            "id": reservation.room.id,
            "number": reservation.room.number,
            "status": reservation.room.status,
            "housekeeping": reservation.room.housekeeping,
        }
        if reservation.room
        else None,
        "pricing": {
            "type": reservation.pricing_type,
            "stay_hours": reservation.stay_hours,
            "rate_per_night": float(reservation.rate_per_night or 0),
            "hourly_rate_percent": policy.hourly_rate_percent,
        },
        "clock": {
            **clock,
            "checked_in_at": reservation.checked_in_at.isoformat()
            if reservation.checked_in_at
            else None,
            "expected_checkout_at": reservation.expected_checkout_at.isoformat()
            if reservation.expected_checkout_at
            else None,
            "expected_checkout_local": expected_local.isoformat() if expected_local else None,
            "original_checkout_at": reservation.original_checkout_at.isoformat()
            if reservation.original_checkout_at
            else None,
            "checked_out_at": reservation.checked_out_at.isoformat()
            if reservation.checked_out_at
            else None,
            "grace_minutes": policy.grace_minutes,
            "late_checkout_fee": policy.late_checkout_fee,
            "server_now": now.isoformat(),
            "server_now_local": from_utc(now, policy).isoformat(),
        },
        "money": money,
        "extension": {
            "pending": serialize_extension(pending, policy) if pending else None,
            "approved_count": sum(
                1 for row in reservation.extensions if row.status == EXTENSION_APPROVED
            ),
            "history": [serialize_extension(row, policy) for row in reservation.extensions],
        },
        "housekeeping": {
            "room_status": reservation.room.status if reservation.room else None,
            "room_housekeeping": reservation.room.housekeeping if reservation.room else None,
            "task_at": reservation.housekeep_task_at.isoformat()
            if reservation.housekeep_task_at
            else None,
        },
        "checkout": {
            "receipt_reference": reservation.receipt_reference,
            "note": reservation.checkout_note,
            "outstanding_authorised_by": reservation.outstanding_authorised_by,
        },
    }


# --- Alerts ------------------------------------------------------------
def sync_alerts(
    reservation: Reservation, policy: StayPolicy, now: datetime | None = None
) -> list[StayAlert]:
    """Record each checkout threshold once, and re-arm after an extension.

    Alerts are bookkeeping for the desk, not occupancy: they never change a
    stay's state. Existing rows tied to a superseded expiry are cleared so an
    approved extension raises its warnings again at the new time.
    """
    now = now or utcnow()
    if (
        reservation.status != RES_CHECKED_IN
        or reservation.expected_checkout_at is None
    ):
        return []

    expected = reservation.expected_checkout_at
    raised: list[StayAlert] = []
    existing = {row.threshold_minutes: row for row in reservation_alerts(reservation.id)}
    for threshold, row in existing.items():
        if row.expected_checkout_at != expected:
            db.session.delete(row)
    # Flush the deletions before inserting the new rows: both touch the same
    # (reservation, threshold) key, and the insert must not race the delete.
    if existing:
        db.session.flush()

    for threshold in policy.checkout_alert_minutes:
        if threshold in existing and existing[threshold].expected_checkout_at == expected:
            continue
        if now < expected - timedelta(minutes=threshold):
            continue
        alert = StayAlert(
            reservation_id=reservation.id,
            threshold_minutes=threshold,
            kind="checkout_overdue" if threshold < 0 else "checkout",
            expected_checkout_at=expected,
        )
        db.session.add(alert)
        raised.append(alert)
        if threshold < 0 and policy.overdue_manager_alert:
            db.session.add(
                Notification(
                    staff_id=None,
                    kind="operations",
                    title=f"Overdue checkout — room {reservation.room.number if reservation.room else '—'}",
                    body=(
                        f"{reservation.guest.display_name if reservation.guest else 'Guest'} "
                        f"is {abs(threshold)} minutes past the agreed checkout."
                    ),
                )
            )
    if raised:
        db.session.flush()
    return raised


def reservation_alerts(reservation_id: int) -> list[StayAlert]:
    return list(
        db.session.scalars(
            db.select(StayAlert).where(StayAlert.reservation_id == reservation_id)
        ).all()
    )


# --- Extensions --------------------------------------------------------
def extension_conflict(
    reservation: Reservation,
    new_checkout: datetime,
    policy: StayPolicy,
) -> Reservation | None:
    """Another live booking that would collide with the later checkout.

    Compared on hotel-local dates, which is how the desk thinks about rooms:
    a guest keeping the room past noon collides with anyone arriving that day
    or later while another stay holds the room.
    """
    if reservation.room_id is None:
        return None
    new_local = from_utc(new_checkout, policy)
    extends_into = new_local.date()
    return db.session.scalar(
        db.select(Reservation).where(
            Reservation.id != reservation.id,
            Reservation.room_id == reservation.room_id,
            Reservation.status.in_((RES_CHECKED_IN, "confirmed", "pending")),
            Reservation.arrival <= extends_into,
            Reservation.departure > reservation.arrival,
        )
    )


def request_extension(
    reservation: Reservation,
    *,
    minutes: int,
    policy: StayPolicy,
    requested_by: int | None,
    note: str | None = None,
    auto_approve: bool = False,
    now: datetime | None = None,
) -> StayExtension:
    if reservation.status != RES_CHECKED_IN:
        raise StayError(409, "not_in_house", "Only an in-house stay can be extended.")
    minutes = int(minutes)
    if minutes <= 0 or minutes > 60 * 24 * 30:
        raise StayError(400, "invalid_extension", "Extend by between 1 minute and 30 days.")
    if reservation.expected_checkout_at is None:
        raise StayError(409, "no_checkout", "This stay has no agreed checkout to extend.")

    now = now or utcnow()
    original = reservation.expected_checkout_at
    base = max(original, now)
    new_checkout = base + timedelta(minutes=minutes)
    conflict = extension_conflict(reservation, new_checkout, policy)
    if conflict is not None:
        raise StayError(
            409,
            "reservation_conflict",
            f"Room would collide with {conflict.reference} arriving "
            f"{conflict.arrival.isoformat()}.",
            {"conflict_reference": conflict.reference, "arrival": conflict.arrival.isoformat()},
        )

    hours = max(1, round(minutes / 60))
    charge = quote_charge(
        nightly_rate=float(reservation.rate_per_night or 0),
        pricing_type=PRICING_HOURLY,
        hours=hours,
        hourly_rate_percent=policy.hourly_rate_percent,
    )
    row = StayExtension(
        reservation_id=reservation.id,
        minutes=minutes,
        pricing_type=PRICING_HOURLY,
        additional_charge=charge,
        original_checkout_at=original,
        new_checkout_at=new_checkout,
        status=EXTENSION_APPROVED if auto_approve else EXTENSION_PENDING,
        note=(str(note)[:300] if note else None),
        requested_by=requested_by,
        approved_by=requested_by if auto_approve else None,
        decided_at=now if auto_approve else None,
    )
    db.session.add(row)
    if auto_approve:
        apply_extension(reservation, row, approved_by=requested_by, policy=policy, now=now)
    db.session.flush()
    return row


def apply_extension(
    reservation: Reservation,
    extension: StayExtension,
    *,
    approved_by: int | None,
    policy: StayPolicy,
    now: datetime | None = None,
) -> None:
    """Move the expiry, never the history.

    `original_checkout_at` keeps the first agreed time, the extension row keeps
    what was asked, and alerts re-arm against the new expiry.
    """
    if extension.status != EXTENSION_PENDING and extension.status != EXTENSION_APPROVED:
        raise StayError(409, "invalid_extension", "That extension is already decided.")
    conflict = extension_conflict(reservation, extension.new_checkout_at, policy)
    if conflict is not None:
        extension.conflict_note = f"{conflict.reference} arrives {conflict.arrival.isoformat()}"
        raise StayError(
            409,
            "reservation_conflict",
            f"Room would collide with {conflict.reference}.",
            {"conflict_reference": conflict.reference},
        )
    if reservation.original_checkout_at is None:
        reservation.original_checkout_at = extension.original_checkout_at
    extension.status = EXTENSION_APPROVED
    extension.approved_by = approved_by
    extension.decided_at = now or utcnow()
    extension.conflict_note = None
    reservation.expected_checkout_at = extension.new_checkout_at
    sync_alerts(reservation, policy, now)


def reject_extension(
    extension: StayExtension, *, decided_by: int | None, note: str | None = None
) -> None:
    if extension.status != EXTENSION_PENDING:
        raise StayError(409, "invalid_extension", "That extension is already decided.")
    extension.status = EXTENSION_REJECTED
    extension.approved_by = None
    extension.decided_at = utcnow()
    if note:
        extension.conflict_note = str(note)[:300]
    extension.requested_by = extension.requested_by or decided_by


# --- Payments and checkout --------------------------------------------
def record_payment(
    reservation: Reservation,
    *,
    amount: float,
    kind: str = PAYMENT_IN,
    method: str = "cash",
    reference: str | None = None,
    notes: str | None = None,
    received_by: int | None = None,
) -> Payment:
    if kind not in (PAYMENT_IN, PAYMENT_REFUND):
        raise StayError(400, "invalid_payment_kind", "Payments are recorded or refunded.")
    amount = round(float(amount or 0), 2)
    if amount <= 0:
        raise StayError(400, "invalid_amount", "A payment must be greater than zero.")
    if kind == PAYMENT_REFUND:
        paid = payment_totals(reservation)["net_paid"]
        if amount > paid + 0.001:
            raise StayError(
                409,
                "refund_exceeds_paid",
                "A refund cannot exceed what has been taken for this stay.",
                {"net_paid": paid},
            )
    row = Payment(
        reservation_id=reservation.id,
        kind=kind,
        amount=amount,
        currency=reservation.currency,
        method=str(method or "cash")[:24],
        reference=(str(reference)[:64] if reference else None),
        notes=(str(notes)[:300] if notes else None),
        received_by=received_by,
    )
    db.session.add(row)
    db.session.flush()
    return row


def checkout_stay(
    reservation: Reservation,
    *,
    staff_id: int | None,
    policy: StayPolicy,
    note: str | None = None,
    require_settlement: bool = True,
    authorise_outstanding: bool = False,
    now: datetime | None = None,
) -> dict:
    """Close the stay, hand the room to housekeeping, and issue a receipt.

    With `require_settlement`, a balance must be settled first; an authorised
    outstanding balance is recorded against the staff member who approved it.
    The legacy reservation endpoint uses `require_settlement=False` and records
    the acting desk user as the authoriser, so nothing looks settled when it is
    not.
    """
    if reservation.status == RES_CHECKED_OUT:
        raise StayError(409, "already_checked_out", "That stay is already closed.")
    if reservation.status != RES_CHECKED_IN:
        raise StayError(409, "not_in_house", "Only an in-house guest can be checked out.")

    now = now or utcnow()
    money = payment_totals(reservation)
    if require_settlement and money["balance"] > 0.001 and not authorise_outstanding:
        raise StayError(
            409,
            "outstanding_balance",
            f"{money['balance']:.0f} {reservation.currency} is still outstanding.",
            {"money": money},
        )

    reservation.status = RES_CHECKED_OUT
    reservation.checked_out_at = now
    reservation.checked_out_by = staff_id
    reservation.checkout_note = (str(note)[:400] if note else None)
    reservation.receipt_reference = reservation.receipt_reference or (
        "RC" + secrets.token_hex(4).upper()
    )
    if money["balance"] > 0.001 and (authorise_outstanding or not require_settlement):
        reservation.outstanding_authorised_by = staff_id
    if reservation.room is not None:
        reservation.room.status = "cleaning"
        reservation.room.housekeeping = "dirty"
        reservation.housekeep_task_at = now

    return receipt_for(reservation, policy, now)


def receipt_for(
    reservation: Reservation, policy: StayPolicy, now: datetime | None = None
) -> dict:
    now = now or utcnow()
    money = payment_totals(reservation)
    expected_local = from_utc(reservation.expected_checkout_at, policy)
    checked_out_local = from_utc(reservation.checked_out_at, policy)
    return {
        "receipt_reference": reservation.receipt_reference,
        "hotel": _hotel_identity(),
        "stay": {
            "reference": reservation.reference,
            "guest": reservation.guest.display_name if reservation.guest else None,
            "room": reservation.room.number if reservation.room else None,
            "arrival": reservation.arrival.isoformat(),
            "departure": reservation.departure.isoformat(),
            "nights": reservation.nights(),
            "pricing_type": reservation.pricing_type,
            "checked_in_at": reservation.checked_in_at.isoformat()
            if reservation.checked_in_at
            else None,
            "expected_checkout_at": reservation.expected_checkout_at.isoformat()
            if reservation.expected_checkout_at
            else None,
            "expected_checkout_local": expected_local.isoformat() if expected_local else None,
            "checked_out_at": reservation.checked_out_at.isoformat()
            if reservation.checked_out_at
            else None,
            "checked_out_local": checked_out_local.isoformat() if checked_out_local else None,
        },
        "money": money,
        "payments": [serialize_payment(row) for row in reservation.payments],
        "extensions": [serialize_extension(row, policy) for row in reservation.extensions],
        "settled": money["balance"] <= 0.001,
        "outstanding_authorised_by": reservation.outstanding_authorised_by,
        "issued_at": now.isoformat(),
    }


def _hotel_identity() -> dict:
    row = _settings_row()
    if row is None:
        return {"name": "LA-MALIVA VISTA HOTEL", "address": None, "phone": None, "currency": "XAF"}
    return {
        "name": row.name,
        "address": row.address,
        "phone": row.phone,
        "email": row.email,
        "currency": row.currency,
    }
