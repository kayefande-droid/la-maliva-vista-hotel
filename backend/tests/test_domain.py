"""Hotel operations: rooms, guests, reservations, check-in/out, inventory, reports."""
from __future__ import annotations

from datetime import date, timedelta

import pytest

from lamaliva.extensions import db
from lamaliva.models import AuditLog, Device, Notification, Staff, STATUS_ACTIVE
from lamaliva.security import hash_password

TODAY = date.today()


@pytest.fixture()
def receptionist(app, client):
    with app.app_context():
        db.session.add(
            Staff(
                username="reception",
                email="reception@lamaliva.local",
                full_name="Reception Desk",
                password_hash=hash_password("Reception#2026x"),
                role="receptionist",
                status=STATUS_ACTIVE,
                must_change_password=False,
            )
        )
        db.session.commit()
    response = client.post(
        "/api/v1/auth/login",
        json={
            "username": "reception",
            "password": "Reception#2026x",
            "device": {"name": "Front desk", "platform": "windows", "fingerprint": "desk-1"},
        },
    )
    assert response.status_code == 200, response.get_json()
    payload = response.get_json()["data"]
    return {"Authorization": f"Bearer {payload['access_token']}"}, payload


@pytest.fixture()
def housekeeper(app, client):
    with app.app_context():
        db.session.add(
            Staff(
                username="housekeeping",
                email="housekeeping@lamaliva.local",
                full_name="Housekeeping",
                password_hash=hash_password("Housekeeping#2026"),
                role="housekeeping",
                status=STATUS_ACTIVE,
                must_change_password=False,
            )
        )
        db.session.commit()
    response = client.post(
        "/api/v1/auth/login",
        json={
            "username": "housekeeping",
            "password": "Housekeeping#2026",
            "device": {"name": "Floor tablet", "platform": "android", "fingerprint": "tab-1"},
        },
    )
    payload = response.get_json()["data"]
    return {"Authorization": f"Bearer {payload['access_token']}"}, payload


def _room(client, headers, number="101"):
    response = client.post("/api/v1/rooms", headers=headers, json={"number": number, "floor": 1})
    assert response.status_code == 201, response.get_json()
    return response.get_json()["data"]


def _guest(client, headers, first="Amina", last="Nkeng"):
    response = client.post(
        "/api/v1/guests",
        headers=headers,
        json={
            "first_name": first,
            "last_name": last,
            "phone": "+237600000000",
            "identity": {"id_type": "passport", "id_number": "P1234567"},
        },
    )
    assert response.status_code == 201, response.get_json()
    return response.get_json()["data"]


def test_room_and_guest_creation(auth, client):
    headers, _ = auth()
    room = _room(client, headers)
    assert room["number"] == "101"

    guest = _guest(client, headers)
    assert guest["reference"].startswith("G")
    assert guest["identity"]["id_number"] == "P1234567"

    duplicate = client.post("/api/v1/rooms", headers=headers, json={"number": "101"})
    assert duplicate.status_code == 409


def test_reservation_lifecycle_keeps_room_in_sync(auth, client):
    headers, _ = auth()
    room = _room(client, headers)
    guest = _guest(client, headers)

    created = client.post(
        "/api/v1/reservations",
        headers=headers,
        json={
            "guest_id": guest["id"],
            "room_id": room["id"],
            "arrival": TODAY.isoformat(),
            "departure": (TODAY + timedelta(days=2)).isoformat(),
            "rate_per_night": 30000,
        },
    )
    assert created.status_code == 201, created.get_json()
    reservation = created.get_json()["data"]
    assert reservation["nights"] == 2
    assert reservation["total_amount"] == 60000

    checked_in = client.post(
        f"/api/v1/reservations/{reservation['id']}/check-in", headers=headers
    )
    assert checked_in.status_code == 200
    assert checked_in.get_json()["data"]["status"] == "checked_in"

    rooms = client.get("/api/v1/rooms", headers=headers).get_json()["data"]
    assert rooms[0]["status"] == "occupied"

    checked_out = client.post(
        f"/api/v1/reservations/{reservation['id']}/check-out", headers=headers
    )
    assert checked_out.status_code == 200
    rooms = client.get("/api/v1/rooms", headers=headers).get_json()["data"]
    assert rooms[0]["status"] == "cleaning"


def test_double_booking_is_rejected(auth, client):
    headers, _ = auth()
    room = _room(client, headers)
    guest = _guest(client, headers)
    payload = {
        "guest_id": guest["id"],
        "room_id": room["id"],
        "arrival": TODAY.isoformat(),
        "departure": (TODAY + timedelta(days=3)).isoformat(),
    }
    assert client.post("/api/v1/reservations", headers=headers, json=payload).status_code == 201

    clash = client.post("/api/v1/reservations", headers=headers, json=payload)
    assert clash.status_code == 409
    assert clash.get_json()["title"] == "room unavailable"


def test_create_is_idempotent(auth, client):
    headers, _ = auth()
    room = _room(client, headers)
    guest = _guest(client, headers)
    payload = {
        "guest_id": guest["id"],
        "room_id": room["id"],
        "arrival": TODAY.isoformat(),
        "departure": (TODAY + timedelta(days=1)).isoformat(),
        "idempotency_key": "abc-123",
    }
    first = client.post("/api/v1/reservations", headers=headers, json=payload)
    second = client.post("/api/v1/reservations", headers=headers, json=payload)
    assert first.status_code == 201
    assert second.status_code == 200
    assert second.get_json()["meta"]["idempotent"] is True
    assert first.get_json()["data"]["reference"] == second.get_json()["data"]["reference"]


def test_departure_before_arrival_is_rejected(auth, client):
    headers, _ = auth()
    room = _room(client, headers)
    guest = _guest(client, headers)
    response = client.post(
        "/api/v1/reservations",
        headers=headers,
        json={
            "guest_id": guest["id"],
            "room_id": room["id"],
            "arrival": (TODAY + timedelta(days=2)).isoformat(),
            "departure": TODAY.isoformat(),
        },
    )
    assert response.status_code == 400
    assert response.get_json()["title"] == "invalid stay"


def test_receptionist_cannot_see_identity_numbers(auth, receptionist, client):
    admin_headers, _ = auth()
    guest = _guest(client, admin_headers)
    headers, payload = receptionist
    assert "guest:restricted" not in payload["permissions"]

    listed = client.get("/api/v1/guests", headers=headers)
    assert listed.status_code == 200
    item = listed.get_json()["data"][0]
    assert item["identity"] == {"restricted": True}
    assert guest["identity"]["id_number"] not in str(listed.get_json())


def test_receptionist_may_book_but_not_manage_staff(receptionist, client):
    headers, _ = receptionist
    room = _room(client, headers) if False else None  # receptionist lacks room:write
    assert client.post("/api/v1/rooms", headers=headers, json={"number": "999"}).status_code == 403
    assert client.get("/api/v1/staff", headers=headers).status_code in (403, 404)


def test_housekeeping_cannot_write_reservations(housekeeper, client):
    headers, _ = housekeeper
    response = client.post(
        "/api/v1/reservations",
        headers=headers,
        json={"guest_id": 1, "arrival": TODAY.isoformat(), "departure": TODAY.isoformat()},
    )
    assert response.status_code == 403
    assert response.get_json()["required_permission"] == "reservation:write"


def test_inventory_movement_and_low_stock_alert(auth, client, app):
    headers, _ = auth()
    item = client.post(
        "/api/v1/inventory/items",
        headers=headers,
        json={"name": "Bottled water", "unit": "bottle", "quantity": 20, "reorder_level": 10},
    ).get_json()["data"]

    taken = client.post(
        f"/api/v1/inventory/items/{item['id']}/movements",
        headers=headers,
        json={"kind": "out", "quantity": 15, "reason": "minibar restock"},
    )
    assert taken.status_code == 201
    assert taken.get_json()["data"]["item"]["quantity"] == 5

    low = client.get("/api/v1/inventory/low-stock", headers=headers).get_json()
    assert low["meta"]["count"] == 1

    with app.app_context():
        alerts = db.session.scalars(
            db.select(Notification).where(Notification.kind == "inventory")
        ).all()
        assert len(alerts) == 1
        assert "Low stock" in alerts[0].title


def test_overselling_stock_is_refused(auth, client):
    headers, _ = auth()
    item = client.post(
        "/api/v1/inventory/items", headers=headers, json={"name": "Towels", "quantity": 2}
    ).get_json()["data"]
    response = client.post(
        f"/api/v1/inventory/items/{item['id']}/movements",
        headers=headers,
        json={"kind": "out", "quantity": 5},
    )
    assert response.status_code == 409


def test_reports_reflect_real_data(auth, client):
    headers, _ = auth()
    room = _room(client, headers)
    guest = _guest(client, headers)
    client.post(
        "/api/v1/reservations",
        headers=headers,
        json={
            "guest_id": guest["id"],
            "room_id": room["id"],
            "arrival": TODAY.isoformat(),
            "departure": (TODAY + timedelta(days=2)).isoformat(),
        },
    )
    overview = client.get("/api/v1/reports/overview", headers=headers).get_json()["data"]
    assert overview["rooms"]["total"] == 1
    assert overview["today"]["arrivals"] == 1

    revenue = client.get("/api/v1/reports/revenue", headers=headers)
    assert revenue.status_code == 200
    assert revenue.get_json()["data"]["currency"] == "XAF"


def test_audit_trail_records_writes(auth, client, app):
    headers, _ = auth()
    guest = _guest(client, headers)
    logs = client.get("/api/v1/audit?entity=guest", headers=headers).get_json()["data"]
    assert any(entry["action"] == "guest.created" for entry in logs)

    with app.app_context():
        assert db.session.scalar(db.select(db.func.count()).select_from(AuditLog)) > 0


def test_settings_are_admin_only(auth, receptionist, client):
    admin_headers, _ = auth()
    updated = client.patch(
        "/api/v1/settings", headers=admin_headers, json={"name": "LA-MALIVA VISTA HOTEL"}
    )
    assert updated.status_code == 200

    headers, _ = receptionist
    denied = client.patch("/api/v1/settings", headers=headers, json={"name": "Hacked"})
    assert denied.status_code == 403


def test_health_endpoint_reports_database(client):
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    body = response.get_json()
    assert body["database"] == "ok"
