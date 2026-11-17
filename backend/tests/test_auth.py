"""Authentication behaviour that the security requirements depend on."""
from __future__ import annotations

from lamaliva.extensions import db
from lamaliva.models import Device, Staff, STATUS_SUSPENDED, utcnow
from lamaliva.security import hash_password


def test_login_succeeds_and_flags_first_change(client):
    response = client.post(
        "/api/v1/auth/login",
        json={
            "username": "director",
            "password": "TestBootstrap!2026",
            "device": {"name": "Office PC", "platform": "windows", "fingerprint": "pc-1"},
        },
    )
    assert response.status_code == 200
    data = response.get_json()["data"]
    assert data["access_token"]
    assert data["refresh_token"]
    assert data["staff"]["role"] == "admin"
    assert data["staff"]["must_change_password"] is True
    assert "*" in data["permissions"]


def test_wrong_password_is_generic(client):
    response = client.post(
        "/api/v1/auth/login", json={"username": "director", "password": "nope-nope-nope"}
    )
    assert response.status_code == 401
    assert response.get_json()["detail"] == "Incorrect username or password."


def test_unknown_account_looks_identical(client):
    response = client.post(
        "/api/v1/auth/login", json={"username": "ghost", "password": "nope-nope-nope"}
    )
    assert response.status_code == 401
    assert response.get_json()["detail"] == "Incorrect username or password."


def test_suspended_account_cannot_sign_in(app, client):
    with app.app_context():
        staff = db.session.scalar(db.select(Staff).where(Staff.username == "director"))
        staff.status = STATUS_SUSPENDED
        db.session.commit()

    response = client.post(
        "/api/v1/auth/login",
        json={"username": "director", "password": "TestBootstrap!2026"},
    )
    assert response.status_code == 403
    assert response.get_json()["title"] == "account suspended"


def test_me_requires_a_token(client):
    assert client.get("/api/v1/auth/me").status_code == 401


def test_me_returns_profile(auth, client):
    headers, payload = auth()
    response = client.get("/api/v1/auth/me", headers=headers)
    assert response.status_code == 200
    assert response.get_json()["data"]["staff"]["username"] == "director"


def test_revoked_device_loses_access_immediately(auth, client):
    headers, payload = auth()
    public_id = payload["device"]["public_id"]
    assert client.post(f"/api/v1/devices/{public_id}/revoke", headers=headers).status_code == 200
    assert client.get("/api/v1/auth/me", headers=headers).status_code == 403


def test_refresh_rotates_and_detects_reuse(auth, client):
    _, first = auth()
    rotated = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]}
    )
    assert rotated.status_code == 200
    second = rotated.get_json()["data"]
    assert second["refresh_token"] != first["refresh_token"]

    # Replaying the spent token must kill the family.
    replay = client.post("/api/v1/auth/refresh", json={"refresh_token": first["refresh_token"]})
    assert replay.status_code == 401
    assert replay.get_json()["title"] == "refresh token reused"

    after = client.post("/api/v1/auth/refresh", json={"refresh_token": second["refresh_token"]})
    assert after.status_code == 401


def test_password_change_enforces_policy(auth, client):
    headers, _ = auth()
    weak = client.post(
        "/api/v1/auth/change-password",
        headers=headers,
        json={"current_password": "TestBootstrap!2026", "new_password": "short"},
    )
    assert weak.status_code == 400

    good = client.post(
        "/api/v1/auth/change-password",
        headers=headers,
        json={
            "current_password": "TestBootstrap!2026",
            "new_password": "MalivaVista#2026",
        },
    )
    assert good.status_code == 200
    assert good.get_json()["data"]["staff"]["must_change_password"] is False


def test_failed_logins_lock_the_account(app, client):
    for _ in range(5):
        client.post("/api/v1/auth/login", json={"username": "director", "password": "bad-password"})
    locked = client.post(
        "/api/v1/auth/login",
        json={"username": "director", "password": "TestBootstrap!2026"},
    )
    assert locked.status_code == 423


def test_device_registry_lists_own_devices(auth, client):
    headers, _ = auth()
    response = client.get("/api/v1/devices", headers=headers)
    assert response.status_code == 200
    devices = response.get_json()["data"]
    assert len(devices) == 1
    assert devices[0]["platform"] == "windows"
