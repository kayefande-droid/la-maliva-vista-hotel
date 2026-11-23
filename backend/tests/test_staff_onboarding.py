"""End-to-end checks for the paths the desk actually walks.

Account creation is the first thing an administrator does, and a broken
onboarding path locks the whole hotel out, so the full loop is pinned here:
create the account, sign in with it, change the first password, then confirm
that the new role is refused the manager-only pages.
"""
from __future__ import annotations

from datetime import date, timedelta


def _code(response) -> str:
    """Errors are problem+json: the machine code lives in `type`."""
    return str(response.get_json().get("type", "")).rsplit("#", 1)[-1]


def _create_staff(client, auth, **overrides):
    headers, _ = auth()
    payload = {
        "username": "frontdesk",
        "full_name": "Front Desk",
        "role": "receptionist",
        "password": "DeskPassword#2026",
    }
    payload.update(overrides)
    return client.post("/api/v1/staff", json=payload, headers=headers)


def test_an_administrator_can_create_an_account_and_it_can_sign_in(client, auth):
    created = _create_staff(client, auth)
    assert created.status_code == 201, created.get_json()

    body = created.get_json()
    assert body["data"]["username"] == "frontdesk"
    assert body["data"]["role"] == "receptionist"
    # A password was supplied, so no one-time password is echoed back.
    assert "meta" not in body

    listing = client.get("/api/v1/staff", headers=auth()[0])
    assert listing.status_code == 200
    assert any(row["username"] == "frontdesk" for row in listing.get_json()["data"])

    login = client.post(
        "/api/v1/auth/login",
        json={
            "username": "frontdesk",
            "password": "DeskPassword#2026",
            "device": {
                "name": "Desk phone",
                "platform": "android",
                "fingerprint": "desk-phone-1",
            },
        },
    )
    assert login.status_code == 200, login.get_json()
    session = login.get_json()["data"]
    assert session["staff"]["must_change_password"] is True
    assert "report:financial" not in session["permissions"]

    changed = client.post(
        "/api/v1/auth/change-password",
        json={
            "current_password": "DeskPassword#2026",
            "new_password": "DeskPassword#2027",
        },
        headers={"Authorization": f"Bearer {session['access_token']}"},
    )
    assert changed.status_code == 200, changed.get_json()
    assert changed.get_json()["data"]["staff"]["must_change_password"] is False

    # The old password stops working immediately.
    again = client.post(
        "/api/v1/auth/login",
        json={
            "username": "frontdesk",
            "password": "DeskPassword#2026",
            "device": {"fingerprint": "desk-phone-1"},
        },
    )
    assert again.status_code == 401


def test_created_accounts_cannot_duplicate_a_username_or_email(client, auth):
    assert _create_staff(client, auth, email="front@lamaliva.local").status_code == 201
    duplicate = _create_staff(client, auth, full_name="Someone Else")
    assert duplicate.status_code == 409
    assert _code(duplicate) == "duplicate_username"

    other = _create_staff(
        client,
        auth,
        username="nightdesk",
        full_name="Night Desk",
        email="front@lamaliva.local",
    )
    assert other.status_code == 409
    assert _code(other) == "duplicate_email"


def test_weak_or_missing_fields_are_refused_with_a_clear_reason(client, auth):
    short_username = _create_staff(client, auth, username="ab")
    assert short_username.status_code == 400
    assert _code(short_username) == "invalid_username"

    weak = _create_staff(client, auth, password="123")
    assert weak.status_code == 400
    assert _code(weak) == "weak_password"

    bad_role = _create_staff(client, auth, role="owner")
    assert bad_role.status_code == 400
    assert _code(bad_role) == "invalid_role"

    missing_name = _create_staff(client, auth, full_name="  ")
    assert missing_name.status_code == 400
    assert _code(missing_name) == "missing_fields"


def test_a_new_receptionist_can_register_a_guest_and_book_a_room(client, auth):
    assert _create_staff(client, auth).status_code == 201
    login = client.post(
        "/api/v1/auth/login",
        json={
            "username": "frontdesk",
            "password": "DeskPassword#2026",
            "device": {"fingerprint": "desk-phone-2"},
        },
    )
    token = login.get_json()["data"]["access_token"]
    headers = {"Authorization": f"Bearer {token}"}

    guest = client.post(
        "/api/v1/guests",
        json={
            "first_name": "Amina",
            "last_name": "Njoya",
            "phone": "+237699000123",
            "id_type": "cni",
            "id_number": "1234567890",
        },
        headers=headers,
    )
    assert guest.status_code == 201, guest.get_json()

    room_type = client.get("/api/v1/rooms/types", headers=headers)
    assert room_type.status_code == 200
    rate = room_type.get_json()["data"][0]["base_rate"] if room_type.get_json()["data"] else 30000

    arrival = date.today() + timedelta(days=30)
    booking = client.post(
        "/api/v1/reservations",
        json={
            "guest_id": guest.get_json()["data"]["id"],
            "arrival": arrival.isoformat(),
            "departure": (arrival + timedelta(days=2)).isoformat(),
            "rate_per_night": rate,
        },
        headers=headers,
    )
    assert booking.status_code == 201, booking.get_json()
    reference = booking.get_json()["data"]["id"]

    cancelled = client.post(
        f"/api/v1/reservations/{reference}/cancel",
        json={"reason": "Smoke check"},
        headers=headers,
    )
    assert cancelled.status_code == 200, cancelled.get_json()


def test_a_receptionist_is_refused_the_money_report_and_staff_creation(client, auth):
    assert _create_staff(client, auth).status_code == 201
    login = client.post(
        "/api/v1/auth/login",
        json={
            "username": "frontdesk",
            "password": "DeskPassword#2026",
            "device": {"fingerprint": "desk-phone-3"},
        },
    )
    headers = {"Authorization": f"Bearer {login.get_json()['data']['access_token']}"}
    today = date.today()

    money = client.get(
        f"/api/v1/reports/money?from={today - timedelta(days=6)}&to={today}",
        headers=headers,
    )
    assert money.status_code == 403

    staff = client.post(
        "/api/v1/staff",
        json={"username": "sneaky", "full_name": "Sneaky", "role": "admin"},
        headers=headers,
    )
    assert staff.status_code == 403
