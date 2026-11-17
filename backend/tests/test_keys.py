"""The 50-character authorization key: length, one-time display, single use, expiry."""
from __future__ import annotations

from datetime import timedelta

from lamaliva.extensions import db
from lamaliva.models import AuthKey, utcnow


def _issue(client, headers, password="TestBootstrap!2026"):
    return client.post("/api/v1/auth-keys", headers=headers, json={"password": password})


def test_key_is_exactly_fifty_characters(auth, client):
    headers, _ = auth()
    response = _issue(client, headers)
    assert response.status_code == 201
    data = response.get_json()["data"]
    assert len(data["key"]) == 50
    assert data["key"].isalnum()
    assert data["state"] == "live"


def test_key_is_not_returned_again(auth, client):
    headers, _ = auth()
    issued = _issue(client, headers).get_json()["data"]
    current = client.get("/api/v1/auth-keys/current", headers=headers).get_json()["data"]
    assert "key" not in current
    assert current["prefix"] == issued["key"][:6]


def test_key_display_window_is_three_minutes(auth, client):
    headers, _ = auth()
    data = _issue(client, headers).get_json()["data"]
    from datetime import datetime

    issued_at = datetime.fromisoformat(data["issued_at"].replace("Z", ""))
    display_until = datetime.fromisoformat(data["display_until"].replace("Z", ""))
    assert timedelta(minutes=2, seconds=55) < display_until - issued_at < timedelta(minutes=3, seconds=5)


def test_key_is_single_use(auth, client):
    headers, _ = auth()
    key = _issue(client, headers).get_json()["data"]["key"]

    first = client.post(
        "/api/v1/auth-keys/verify",
        headers=headers,
        json={"key": key, "action": "staff.suspend"},
    )
    assert first.status_code == 200
    assert first.get_json()["data"]["authorized"] is True

    second = client.post(
        "/api/v1/auth-keys/verify",
        headers=headers,
        json={"key": key, "action": "staff.suspend"},
    )
    assert second.status_code == 400
    assert second.get_json()["title"] == "key used"


def test_issuing_a_new_key_retires_the_old_one(auth, client):
    headers, _ = auth()
    first_key = _issue(client, headers).get_json()["data"]["key"]
    _issue(client, headers)
    stale = client.post(
        "/api/v1/auth-keys/verify", headers=headers, json={"key": first_key}
    )
    assert stale.status_code == 400
    assert stale.get_json()["title"] in {"key revoked", "key used"}


def test_expired_key_is_rejected(app, auth, client):
    headers, _ = auth()
    key = _issue(client, headers).get_json()["data"]["key"]
    with app.app_context():
        row = db.session.scalar(db.select(AuthKey).order_by(AuthKey.id.desc()).limit(1))
        row.expires_at = utcnow() - timedelta(minutes=1)
        db.session.commit()

    response = client.post("/api/v1/auth-keys/verify", headers=headers, json={"key": key})
    assert response.status_code == 400
    assert response.get_json()["title"] == "key expired"


def test_issue_requires_the_password(auth, client):
    headers, _ = auth()
    assert _issue(client, headers, password="wrong-password").status_code == 403
    assert client.post(
        "/api/v1/auth-keys", headers=headers, json={"password": ""}
    ).status_code == 400


def test_plaintext_is_never_stored(auth, client, app):
    headers, _ = auth()
    key = _issue(client, headers).get_json()["data"]["key"]
    with app.app_context():
        row = db.session.scalar(db.select(AuthKey).order_by(AuthKey.id.desc()).limit(1))
        assert key not in row.key_hash
        assert row.key_hash.startswith("$argon2")


def test_key_does_not_end_the_normal_session(auth, client):
    headers, _ = auth()
    key = _issue(client, headers).get_json()["data"]["key"]
    client.post("/api/v1/auth-keys/verify", headers=headers, json={"key": key})
    assert client.get("/api/v1/auth/me", headers=headers).status_code == 200
