"""Occupancy and checkout monitoring.

The desk watches stays here: how long is left, who is overdue, what is still
owed, what extensions are waiting for approval, and which rooms have been
handed to housekeeping. Every figure is computed by the server from its own
clock in the hotel's timezone.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta

from flask import Blueprint, g, jsonify, request

from ..extensions import db
from ..models import (
    CHARGE_CATEGORIES,
    EXTENSION_APPROVED,
    EXTENSION_PENDING,
    PRICING_HOURLY,
    RES_CHECKED_IN,
    RES_CHECKED_OUT,
    Notification,
    Reservation,
    StayAlert,
    StayCharge,
    StayExtension,
    utcnow,
)
from ..security import audit, has_permission, json_error, require_auth, require_permission
from ..stay import (
    StayError,
    apply_extension,
    approved_extension_charges,
    checkout_stay,
    load_policy,
    payment_totals,
    record_payment,
    reject_extension,
    request_extension,
    serialize_stay,
    sync_alerts,
)
from ._util import body, page_args, paginated

bp = Blueprint("stays", __name__)


def _reservation_or_404(reservation_id: int) -> Reservation:
    row = db.session.get(Reservation, reservation_id)
    if row is None:
        raise StayError(404, "reservation_not_found", "No such reservation.")
    return row


def _stay_error(error: StayError):
    # Same RFC7807 shape as every other refusal in the API.
    return json_error(error.status, error.code, error.message, **(error.details or {}))


@bp.app_errorhandler(StayError)
def _handle_stay_error(error: StayError):
    return _stay_error(error)


@bp.get("/monitor")
@require_auth
@require_permission("reservation:read")
def monitor():
    """Every stay currently holding a room, with its live countdown.

    Alerts are synchronised on read, so scheduled thresholds appear without a
    separate worker and a missed poll simply catches up next time.
    """
    policy = load_policy()
    now = utcnow()
    rows = list(
        db.session.scalars(
            db.select(Reservation)
            .where(Reservation.status == RES_CHECKED_IN)
            .order_by(Reservation.expected_checkout_at.asc(), Reservation.id.asc())
        ).all()
    )
    raised = 0
    for row in rows:
        raised += len(sync_alerts(row, policy, now))
    if raised:
        db.session.commit()

    stays = [serialize_stay(row, policy, now) for row in rows]
    due_today = sum(
        1
        for stay in stays
        if stay["clock"]["expected_checkout_local"]
        and stay["clock"]["expected_checkout_local"][:10]
        == now.replace(tzinfo=None).date().isoformat()
    )
    counts = {
        "in_house": len(stays),
        "active": sum(1 for stay in stays if stay["clock"]["state"] == "active"),
        "approaching": sum(1 for stay in stays if stay["clock"]["state"] == "checkout_approaching"),
        "due": sum(1 for stay in stays if stay["clock"]["state"] == "checkout_due"),
        "overdue": sum(1 for stay in stays if stay["clock"]["is_overdue"]),
        "due_today": due_today,
        "extension_pending": sum(1 for stay in stays if stay["extension"]["pending"]),
        "outstanding_balance": round(
            sum(max(stay["money"]["balance"], 0) for stay in stays), 2
        ),
        "alerts_raised": raised,
    }
    return jsonify({"data": {"counts": counts, "policy": policy.as_dict(), "stays": stays}})


@bp.get("/history")
@require_auth
@require_permission("reservation:read")
def history():
    """Historical occupancy. Checked-out stays are kept, never deleted."""
    limit, offset = page_args()
    query = db.select(Reservation).where(
        Reservation.checked_in_at.is_not(None)
        | Reservation.status.in_((RES_CHECKED_IN, RES_CHECKED_OUT))
    )

    status = (request.args.get("status") or "").strip().lower()
    if status:
        query = query.where(Reservation.status == status)

    guest = (request.args.get("guest") or "").strip()
    if guest:
        from ..models import Guest

        query = query.join(Guest).where(
            db.or_(
                Guest.reference.ilike(f"%{guest}%"),
                Guest.first_name.ilike(f"%{guest}%"),
                Guest.last_name.ilike(f"%{guest}%"),
            )
        )

    room_id = request.args.get("room_id")
    if room_id:
        query = query.where(Reservation.room_id == int(room_id))

    staff_id = request.args.get("staff_id")
    if staff_id:
        query = query.where(
            db.or_(
                Reservation.checked_in_by == int(staff_id),
                Reservation.checked_out_by == int(staff_id),
            )
        )

    try:
        since = date.fromisoformat(request.args["from"]) if request.args.get("from") else None
        until = date.fromisoformat(request.args["to"]) if request.args.get("to") else None
    except ValueError:
        return json_error(400, "invalid_date", "from/to must be ISO dates.")
    if since:
        query = query.where(Reservation.arrival >= since)
    if until:
        query = query.where(Reservation.arrival <= until)

    total = db.session.scalar(db.select(db.func.count()).select_from(query.subquery())) or 0
    rows = db.session.scalars(
        query.order_by(Reservation.arrival.desc(), Reservation.id.desc())
        .limit(limit)
        .offset(offset)
    ).all()
    policy = load_policy()
    return paginated([serialize_stay(row, policy) for row in rows], total, limit, offset)


@bp.get("/<int:reservation_id>")
@require_auth
@require_permission("reservation:read")
def stay_detail(reservation_id: int):
    policy = load_policy()
    row = _reservation_or_404(reservation_id)
    now = utcnow()
    if sync_alerts(row, policy, now):
        db.session.commit()
    alerts = list(
        db.session.scalars(
            db.select(StayAlert)
            .where(StayAlert.reservation_id == row.id)
            .order_by(StayAlert.created_at.asc())
        ).all()
    )
    data = serialize_stay(row, policy, now)
    data["alerts"] = [
        {
            "threshold_minutes": alert.threshold_minutes,
            "kind": alert.kind,
            "created_at": alert.created_at.isoformat(),
        }
        for alert in alerts
    ]
    return jsonify({"data": data})


@bp.post("/<int:reservation_id>/payments")
@require_auth
@require_permission("reservation:checkin")
def add_payment(reservation_id: int):
    policy = load_policy()
    row = _reservation_or_404(reservation_id)
    if row.status == "cancelled":
        return json_error(409, "cancelled", "A cancelled stay takes no payment.")
    data = body()
    try:
        payment = record_payment(
            row,
            amount=data.get("amount"),
            kind=str(data.get("kind") or "payment"),
            method=str(data.get("method") or "cash"),
            reference=data.get("reference"),
            notes=data.get("notes"),
            received_by=g.staff.id,
        )
    except StayError as error:
        return _stay_error(error)

    audit(
        f"stay.{payment.kind}_recorded",
        "reservation",
        row.id,
        after={"amount": float(payment.amount), "method": payment.method},
    )
    db.session.commit()
    stay = serialize_stay(row, policy)
    return jsonify({"data": {"payment": stay["money"], "stay": stay}}), 201


@bp.post("/<int:reservation_id>/charges")
@require_auth
@require_permission("reservation:checkin")
def add_charge(reservation_id: int):
    """Put a meal or a drink on an in-house guest's room bill.

    Breakfast, lunch, supper, a drink or something else, with how many and
    the menu price. The charge is append-only and joins the bill, so
    check-out asks for it instead of the hotel absorbing it.
    """
    row = _reservation_or_404(reservation_id)
    if row.status != RES_CHECKED_IN:
        return json_error(
            409,
            "not_in_house",
            "Meals and drinks are charged to a guest who is checked in.",
        )

    data = body()
    category = str(data.get("category") or "other").strip().lower()
    if category not in CHARGE_CATEGORIES:
        return json_error(
            400,
            "invalid_category",
            f"category must be one of {', '.join(CHARGE_CATEGORIES)}.",
        )
    description = str(data.get("description") or "").strip()
    if not description:
        return json_error(
            400, "missing_description", "Say what was taken, for example 'Omelette'."
        )
    try:
        quantity = float(data.get("quantity") or 1)
        unit_price = float(data.get("unit_price") or 0)
    except (TypeError, ValueError):
        return json_error(400, "invalid_number", "quantity and unit_price must be numbers.")
    if not (0 < quantity <= 1000) or not (0 <= unit_price <= 10_000_000):
        return json_error(
            400,
            "invalid_number",
            "Give a quantity above zero and a price of zero or more.",
        )

    charge = StayCharge(
        reservation_id=row.id,
        category=category,
        description=description[:120],
        quantity=round(quantity, 2),
        unit_price=round(unit_price, 2),
        total=round(quantity * unit_price, 2),
        note=(str(data.get("note") or "")[:200] or None),
        created_by=g.staff.id,
    )
    db.session.add(charge)
    db.session.flush()
    audit(
        "stay.charge_added",
        "reservation",
        row.id,
        after={
            "category": category,
            "description": charge.description,
            "quantity": float(charge.quantity),
            "total": float(charge.total),
        },
    )
    db.session.commit()
    return jsonify({"data": serialize_stay(row, load_policy())}), 201


@bp.get("/<int:reservation_id>/charges")
@require_auth
@require_permission("reservation:read")
def list_charges(reservation_id: int):
    row = _reservation_or_404(reservation_id)
    stay = serialize_stay(row, load_policy())
    return jsonify({"data": stay["charges"], "money": stay["money"]})


@bp.post("/<int:reservation_id>/extensions")
@require_auth
@require_permission("reservation:write")
def create_extension(reservation_id: int):
    policy = load_policy()
    row = _reservation_or_404(reservation_id)
    data = body()

    minutes = data.get("minutes")
    if minutes is None and data.get("hours") is not None:
        try:
            minutes = int(data["hours"]) * 60
        except (TypeError, ValueError):
            return json_error(400, "invalid_extension", "hours must be a number.")
    try:
        minutes = int(minutes or 0)
    except (TypeError, ValueError):
        return json_error(400, "invalid_extension", "minutes must be a number.")

    can_approve = has_permission(g.staff.role, "reservation:approve")
    auto = bool(data.get("auto_approve")) and can_approve
    if not policy.extension_approval_required:
        auto = True

    try:
        extension = request_extension(
            row,
            minutes=minutes,
            policy=policy,
            requested_by=g.staff.id,
            note=data.get("note"),
            auto_approve=auto,
        )
    except StayError as error:
        return _stay_error(error)

    audit(
        "stay.extension_requested",
        "reservation",
        row.id,
        after={
            "minutes": extension.minutes,
            "new_checkout_at": extension.new_checkout_at.isoformat(),
            "status": extension.status,
        },
    )
    db.session.commit()
    return (
        jsonify(
            {
                "data": {
                    "extension": serialize_stay(row, policy)["extension"]["pending"]
                    or serialize_stay(row, policy)["extension"]["history"][-1],
                    "stay": serialize_stay(row, policy),
                },
                "meta": {"approval_required": policy.extension_approval_required and not auto},
            }
        ),
        201,
    )


def _extension_or_404(reservation_id: int, extension_id: int) -> StayExtension:
    row = db.session.get(StayExtension, extension_id)
    if row is None or row.reservation_id != reservation_id:
        raise StayError(404, "extension_not_found", "No such extension on this stay.")
    return row


@bp.post("/<int:reservation_id>/extensions/<int:extension_id>/approve")
@require_auth
@require_permission("reservation:approve")
def approve_extension(reservation_id: int, extension_id: int):
    policy = load_policy()
    reservation = _reservation_or_404(reservation_id)
    extension = _extension_or_404(reservation_id, extension_id)
    if extension.status != EXTENSION_PENDING:
        return json_error(409, "invalid_extension", "That extension is already decided.")
    try:
        apply_extension(
            reservation, extension, approved_by=g.staff.id, policy=policy
        )
    except StayError as error:
        db.session.commit()  # keep the conflict note
        return _stay_error(error)

    audit(
        "stay.extension_approved",
        "reservation",
        reservation.id,
        after={
            "extension": extension.id,
            "new_checkout_at": extension.new_checkout_at.isoformat(),
            "charge": float(extension.additional_charge or 0),
        },
    )
    db.session.commit()
    return jsonify({"data": serialize_stay(reservation, policy)})


@bp.post("/<int:reservation_id>/extensions/<int:extension_id>/reject")
@require_auth
@require_permission("reservation:approve")
def reject(reservation_id: int, extension_id: int):
    policy = load_policy()
    reservation = _reservation_or_404(reservation_id)
    extension = _extension_or_404(reservation_id, extension_id)
    data = body()
    try:
        reject_extension(extension, decided_by=g.staff.id, note=data.get("note"))
    except StayError as error:
        return _stay_error(error)

    audit("stay.extension_rejected", "reservation", reservation.id, after={"extension": extension.id})
    db.session.commit()
    return jsonify({"data": serialize_stay(reservation, policy)})


@bp.post("/<int:reservation_id>/checkout")
@require_auth
@require_permission("reservation:checkin")
def checkout(reservation_id: int):
    """Close the stay with a full summary, final payment and a receipt.

    A balance must be settled unless an approver explicitly authorises it;
    either way the authorised debt is recorded against them.
    """
    policy = load_policy()
    row = _reservation_or_404(reservation_id)
    data = body()

    payments = data.get("payments") or []
    if isinstance(payments, dict):
        payments = [payments]
    if not isinstance(payments, list):
        return json_error(400, "invalid_payments", "payments must be a list.")

    # Validate every line before writing any of them.
    normalised: list[dict] = []
    for entry in payments:
        if not isinstance(entry, dict):
            return json_error(400, "invalid_payments", "Each payment must be an object.")
        try:
            amount = float(entry.get("amount") or 0)
        except (TypeError, ValueError):
            return json_error(400, "invalid_payments", "Payment amounts must be numbers.")
        if amount <= 0:
            return json_error(400, "invalid_payments", "Payment amounts must be positive.")
        normalised.append(entry)

    for entry in normalised:
        try:
            record_payment(
                row,
                amount=float(entry["amount"]),
                kind=str(entry.get("kind") or "payment"),
                method=str(entry.get("method") or "cash"),
                reference=entry.get("reference"),
                notes=entry.get("notes"),
                received_by=g.staff.id,
            )
        except StayError as error:
            db.session.rollback()
            return _stay_error(error)

    authorise = bool(data.get("authorise_outstanding") or data.get("authorize_outstanding"))
    if authorise and not has_permission(g.staff.role, "reservation:approve"):
        db.session.rollback()
        return json_error(
            403, "approval_required", "Only a manager can authorise an outstanding balance."
        )

    try:
        receipt = checkout_stay(
            row,
            staff_id=g.staff.id,
            policy=policy,
            note=data.get("note"),
            require_settlement=True,
            authorise_outstanding=authorise,
        )
    except StayError as error:
        db.session.rollback()
        return _stay_error(error)

    audit(
        "stay.checked_out",
        "reservation",
        row.id,
        after={
            "receipt": row.receipt_reference,
            "balance": receipt["money"]["balance"],
            "authorised": row.outstanding_authorised_by is not None,
        },
    )
    db.session.add(
        Notification(
            staff_id=None,
            kind="operations",
            title=f"Room {row.room.number if row.room else '—'} needs cleaning",
            body=f"{row.guest.display_name if row.guest else 'Guest'} checked out.",
        )
    )
    db.session.commit()
    return jsonify({"data": {"receipt": receipt, "stay": serialize_stay(row, policy)}})


@bp.get("/<int:reservation_id>/receipt")
@require_auth
@require_permission("reservation:read")
def receipt(reservation_id: int):
    from ..stay import receipt_for

    policy = load_policy()
    row = _reservation_or_404(reservation_id)
    if not row.receipt_reference:
        return json_error(404, "no_receipt", "This stay has not been checked out yet.")
    return jsonify({"data": receipt_for(row, policy)})
