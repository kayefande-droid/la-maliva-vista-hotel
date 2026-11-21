"""Occupancy expiry, payments, extensions and checkout.

These tests pin the rules the desk depends on: expiry never checks anyone out,
an overdue room stays held, money is append-only, extensions preserve history,
and a checkout cannot quietly write off a balance.
"""
from __future__ import annotations

import secrets
from datetime import date, datetime, timedelta, timezone

import pytest

from lamaliva.extensions import db
from lamaliva.models import (
    EXTENSION_APPROVED,
    EXTENSION_PENDING,
    PRICING_HOURLY,
    RES_CHECKED_IN,
    RES_CHECKED_OUT,
    RES_CONFIRMED,
    ROLE_RECEPTION,
    ROOM_AVAILABLE,
    ROOM_OCCUPIED,
    STATUS_ACTIVE,
    Guest,
    Reservation,
    Room,
    RoomType,
    Staff,
    StayAlert,
)
from lamaliva.security import hash_password
from lamaliva.stay import load_policy, utcnow

DESK_PASSWORD = "DeskPass!2026"
NIGHTLY_RATE = 50_000


@pytest.fixture()
def world(app):
    """A room, a guest, and a receptionist to sign in as."""
    with app.app_context():
        room_type = RoomType(name="Deluxe", base_rate=NIGHTLY_RATE)
        db.session.add(room_type)
        db.session.flush()
        room = Room(number="101", room_type_id=room_type.id, status=ROOM_AVAILABLE)
        guest = Guest(reference="G-TEST01", first_name="Ama", last_name="Ngwa")
        desk = Staff(
            username="desk",
            email="desk@lamaliva.local",
            full_name="Front Desk",
            password_hash=hash_password(DESK_PASSWORD),
            role=ROLE_RECEPTION,
            status=STATUS_ACTIVE,
            must_change_password=False,
        )
        db.session.add_all([room, guest, desk])
        db.session.commit()
        return {
            "room_id": room.id,
            "guest_id": guest.id,
            "staff_id": desk.id,
        }


def _reservation(world, nights: int = 2, arrival: date | None = None) -> int:
    arrival = arrival or date.today()
    row = Reservation(
        reference="R" + secrets.token_hex(4).upper(),
        guest_id=world["guest_id"],
        room_id=world["room_id"],
        arrival=arrival,
        departure=arrival + timedelta(days=nights),
        status=RES_CONFIRMED,
        rate_per_night=NIGHTLY_RATE,
        total_amount=NIGHTLY_RATE * nights,
        currency="XAF",
    )
    db.session.add(row)
    db.session.commit()
    return row.id


def _checked_in(client, headers, world, nights: int = 2, payload: dict | None = None) -> int:
    reservation_id = _reservation(world, nights)
    response = client.post(
        f"/api/v1/reservations/{reservation_id}/check-in",
        headers=headers,
        json=payload or {},
    )
    assert response.status_code == 200, response.get_json()
    return reservation_id


def _local(value: datetime):
    return value.replace(tzinfo=timezone.utc).astimezone(load_policy().tz)


def _code(response) -> str:
    """The stable error code, carried in the RFC7807 `type` URI."""
    return response.get_json()["type"].split("#", 1)[1]


def test_check_in_sets_the_authoritative_hotel_checkout(app, client, auth, world):
    headers, _ = auth()
    reservation_id = _checked_in(client, headers, world, nights=2)

    with app.app_context():
        row = db.session.get(Reservation, reservation_id)
        policy = load_policy()
        local = row.expected_checkout_at.replace(tzinfo=timezone.utc).astimezone(policy.tz)
        assert local.hour == policy.checkout_time.hour
        assert local.date() == date.today() + timedelta(days=2)
        assert row.original_checkout_at == row.expected_checkout_at
        assert row.status == RES_CHECKED_IN


def test_hourly_check_in_needs_hours_and_prices_the_hour(app, client, auth, world):
    headers, _ = auth()
    reservation_id = _reservation(world)

    # Hourly stays are off by default; switching them on is an explicit policy act.
    disabled = client.post(
        f"/api/v1/reservations/{reservation_id}/check-in",
        headers=headers,
        json={"pricing_type": "hourly", "stay_hours": 3},
    )
    assert disabled.status_code == 409
    assert _code(disabled) == "hourly_unavailable"

    enabled = client.patch("/api/v1/settings", headers=headers, json={"hourly_enabled": True})
    assert enabled.status_code == 200

    missing = client.post(
        f"/api/v1/reservations/{reservation_id}/check-in",
        headers=headers,
        json={"pricing_type": "hourly"},
    )
    assert missing.status_code == 400

    response = client.post(
        f"/api/v1/reservations/{reservation_id}/check-in",
        headers=headers,
        json={"pricing_type": "hourly", "stay_hours": 3},
    )
    assert response.status_code == 200, response.get_json()

    with app.app_context():
        row = db.session.get(Reservation, reservation_id)
        policy = load_policy()
        window = row.expected_checkout_at - utcnow()
        assert timedelta(hours=2, minutes=55) < window < timedelta(hours=3, minutes=5)
        assert row.pricing_type == PRICING_HOURLY
        expected_charge = NIGHTLY_RATE * (policy.hourly_rate_percent / 100) * 3
        assert float(row.total_amount) == pytest.approx(expected_charge)


def test_expiry_never_checks_the_guest_out_or_frees_the_room(app, client, auth, world):
    headers, _ = auth()
    reservation_id = _checked_in(client, headers, world)

    with app.app_context():
        row = db.session.get(Reservation, reservation_id)
        row.expected_checkout_at = utcnow() - timedelta(hours=2)
        db.session.commit()

    detail = client.get(f"/api/v1/stays/{reservation_id}", headers=headers)
    assert detail.status_code == 200
    data = detail.get_json()["data"]
    assert data["clock"]["state"] == "overdue"
    assert data["clock"]["is_overdue"] is True
    assert data["clock"]["room_held"] is True

    with app.app_context():
        row = db.session.get(Reservation, reservation_id)
        assert row.status == RES_CHECKED_IN
        assert row.room.status == ROOM_OCCUPIED


def test_payments_are_append_only_and_refunds_cannot_exceed_them(app, client, auth, world):
    headers, _ = auth()
    reservation_id = _checked_in(client, headers, world)

    paid = client.post(
        f"/api/v1/stays/{reservation_id}/payments",
        headers=headers,
        json={"amount": 20_000, "method": "momo", "reference": "MOMO-1"},
    )
    assert paid.status_code == 201, paid.get_json()

    refund = client.post(
        f"/api/v1/stays/{reservation_id}/payments",
        headers=headers,
        json={"amount": 5_000, "kind": "refund", "notes": "Overcharged deposit"},
    )
    assert refund.status_code == 201
    money = refund.get_json()["data"]["payment"]
    assert money["net_paid"] == 15_000
    assert money["paid"] == 20_000
    assert money["refunded"] == 5_000

    too_much = client.post(
        f"/api/v1/stays/{reservation_id}/payments",
        headers=headers,
        json={"amount": 999_999, "kind": "refund"},
    )
    assert too_much.status_code == 409
    assert _code(too_much) == "refund_exceeds_paid"


def test_extension_waits_for_approval_then_moves_only_the_expiry(app, client, auth, world):
    headers, _ = auth()
    reservation_id = _checked_in(client, headers, world)

    requested = client.post(
        f"/api/v1/stays/{reservation_id}/extensions",
        headers=headers,
        json={"minutes": 120, "note": "Late flight"},
    )
    assert requested.status_code == 201, requested.get_json()
    meta = requested.get_json()["meta"]
    assert meta["approval_required"] is True

    with app.app_context():
        row = db.session.get(Reservation, reservation_id)
        unapproved_checkout = row.expected_checkout_at
        extension = row.extensions[0]
        assert extension.status == EXTENSION_PENDING
        assert extension.original_checkout_at == unapproved_checkout
        assert row.expected_checkout_at == unapproved_checkout

    approved = client.post(
        f"/api/v1/stays/{reservation_id}/extensions/{extension.id}/approve",
        headers=headers,
    )
    assert approved.status_code == 200, approved.get_json()

    with app.app_context():
        row = db.session.get(Reservation, reservation_id)
        extension = row.extensions[0]
        assert extension.status == EXTENSION_APPROVED
        assert row.expected_checkout_at == unapproved_checkout + timedelta(minutes=120)
        assert row.original_checkout_at == unapproved_checkout
        assert float(extension.additional_charge) > 0


def test_extension_is_refused_when_the_next_booking_would_collide(app, client, auth, world):
    headers, _ = auth()
    reservation_id = _checked_in(client, headers, world, nights=1)
    following = _reservation(world, nights=1, arrival=date.today() + timedelta(days=1))

    response = client.post(
        f"/api/v1/stays/{reservation_id}/extensions",
        headers=headers,
        json={"minutes": 240},
    )
    assert response.status_code == 409
    assert _code(response) == "reservation_conflict"
    assert following

    with app.app_context():
        row = db.session.get(Reservation, reservation_id)
        assert row.extensions == []


def test_policy_can_approve_extensions_automatically(app, client, auth, world):
    headers, _ = auth()
    reservation_id = _checked_in(client, headers, world)

    updated = client.patch(
        "/api/v1/settings",
        headers=headers,
        json={"extension_approval_required": False},
    )
    assert updated.status_code == 200, updated.get_json()

    response = client.post(
        f"/api/v1/stays/{reservation_id}/extensions",
        headers=headers,
        json={"hours": 1},
    )
    assert response.status_code == 201, response.get_json()

    with app.app_context():
        row = db.session.get(Reservation, reservation_id)
        assert row.extensions[0].status == EXTENSION_APPROVED
        assert row.expected_checkout_at == row.extensions[0].new_checkout_at


def test_checkout_is_blocked_while_money_is_outstanding(app, client, auth, world):
    headers, _ = auth()
    reservation_id = _checked_in(client, headers, world)

    response = client.post(f"/api/v1/stays/{reservation_id}/checkout", headers=headers, json={})
    assert response.status_code == 409
    refusal = response.get_json()
    assert _code(response) == "outstanding_balance"
    assert refusal["money"]["balance"] == NIGHTLY_RATE * 2

    with app.app_context():
        row = db.session.get(Reservation, reservation_id)
        assert row.status == RES_CHECKED_IN
        assert row.room.status == ROOM_OCCUPIED


def test_settled_checkout_issues_a_receipt_and_hands_the_room_to_housekeeping(
    app, client, auth, world
):
    headers, _ = auth()
    reservation_id = _checked_in(client, headers, world)

    response = client.post(
        f"/api/v1/stays/{reservation_id}/checkout",
        headers=headers,
        json={
            "payments": [{"amount": NIGHTLY_RATE * 2, "method": "momo"}],
            "note": "Settled at the desk",
        },
    )
    assert response.status_code == 200, response.get_json()
    receipt = response.get_json()["data"]["receipt"]
    assert receipt["settled"] is True
    assert receipt["money"]["balance"] == 0
    assert receipt["receipt_reference"]

    with app.app_context():
        row = db.session.get(Reservation, reservation_id)
        assert row.status == RES_CHECKED_OUT
        assert row.receipt_reference == receipt["receipt_reference"]
        assert row.room.status == "cleaning"
        assert row.room.housekeeping == "dirty"
        assert row.housekeep_task_at is not None

    fetched = client.get(f"/api/v1/stays/{reservation_id}/receipt", headers=headers)
    assert fetched.status_code == 200
    assert fetched.get_json()["data"]["stay"]["reference"] == receipt["stay"]["reference"]


def test_only_a_manager_can_authorise_an_outstanding_balance(app, client, auth, world):
    admin_headers, admin_session = auth()
    reservation_id = _checked_in(client, admin_headers, world)

    desk_headers, _ = auth(username="desk", password=DESK_PASSWORD, fingerprint="desk-device")
    refused = client.post(
        f"/api/v1/stays/{reservation_id}/checkout",
        headers=desk_headers,
        json={"authorise_outstanding": True},
    )
    assert refused.status_code == 403
    assert _code(refused) == "approval_required"

    with app.app_context():
        assert db.session.get(Reservation, reservation_id).status == RES_CHECKED_IN

    allowed = client.post(
        f"/api/v1/stays/{reservation_id}/checkout",
        headers=admin_headers,
        json={"authorise_outstanding": True, "note": "Owner approved"},
    )
    assert allowed.status_code == 200, allowed.get_json()
    receipt = allowed.get_json()["data"]["receipt"]
    assert receipt["settled"] is False
    assert receipt["outstanding_authorised_by"] == admin_session["staff"]["id"]


def test_history_keeps_closed_stays(app, client, auth, world):
    headers, _ = auth()
    reservation_id = _checked_in(client, headers, world)
    client.post(
        f"/api/v1/stays/{reservation_id}/checkout",
        headers=headers,
        json={"payments": [{"amount": NIGHTLY_RATE * 2}]},
    )

    history = client.get("/api/v1/stays/history", headers=headers, query_string={"guest": "Ama"})
    assert history.status_code == 200
    payload = history.get_json()
    assert payload["meta"]["total"] == 1
    assert payload["data"][0]["reservation"]["id"] == reservation_id
    assert payload["data"][0]["clock"]["state"] == "checked_out"


def test_alerts_are_raised_once_and_rearm_after_an_extension(app, client, auth, world):
    headers, _ = auth()
    reservation_id = _checked_in(client, headers, world)

    with app.app_context():
        row = db.session.get(Reservation, reservation_id)
        row.expected_checkout_at = utcnow() + timedelta(minutes=20)
        db.session.commit()

    first = client.get("/api/v1/stays/monitor", headers=headers)
    assert first.status_code == 200
    assert first.get_json()["data"]["counts"]["alerts_raised"] >= 1

    second = client.get("/api/v1/stays/monitor", headers=headers)
    assert second.get_json()["data"]["counts"]["alerts_raised"] == 0

    requested = client.post(
        f"/api/v1/stays/{reservation_id}/extensions",
        headers=headers,
        json={"minutes": 180},
    )
    extension_id = requested.get_json()["data"]["extension"]["id"]
    client.post(
        f"/api/v1/stays/{reservation_id}/extensions/{extension_id}/approve",
        headers=headers,
    )

    with app.app_context():
        row = db.session.get(Reservation, reservation_id)
        alerts = db.session.scalars(
            db.select(StayAlert).where(StayAlert.reservation_id == reservation_id)
        ).all()
        assert all(alert.expected_checkout_at == row.expected_checkout_at for alert in alerts)


def test_policy_changes_apply_to_new_stays_only(app, client, auth, world):
    headers, _ = auth()
    existing_id = _checked_in(client, headers, world)

    with app.app_context():
        existing_checkout = db.session.get(Reservation, existing_id).expected_checkout_at

    updated = client.patch("/api/v1/settings", headers=headers, json={"checkout_time": "11:00"})
    assert updated.status_code == 200

    with app.app_context():
        assert db.session.get(Reservation, existing_id).expected_checkout_at == existing_checkout

    new_id = _checked_in(client, headers, world)
    with app.app_context():
        row = db.session.get(Reservation, new_id)
        assert _local(row.expected_checkout_at).hour == 11


def test_receptionist_cannot_approve_an_extension(client, auth, world):
    admin_headers, _ = auth()
    reservation_id = _checked_in(client, admin_headers, world)
    requested = client.post(
        f"/api/v1/stays/{reservation_id}/extensions",
        headers=admin_headers,
        json={"minutes": 60},
    )
    extension_id = requested.get_json()["data"]["extension"]["id"]

    desk_headers, _ = auth(username="desk", password=DESK_PASSWORD, fingerprint="desk-device")
    response = client.post(
        f"/api/v1/stays/{reservation_id}/extensions/{extension_id}/approve",
        headers=desk_headers,
    )
    assert response.status_code == 403
