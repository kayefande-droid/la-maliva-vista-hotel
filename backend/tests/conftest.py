"""Test fixtures: an in-memory database and a seeded administrator."""
from __future__ import annotations

import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from lamaliva import create_app  # noqa: E402
from lamaliva.extensions import db  # noqa: E402
from lamaliva.models import ROLE_ADMIN, STATUS_ACTIVE, Staff  # noqa: E402
from lamaliva.security import hash_password  # noqa: E402

ADMIN_PASSWORD = "TestBootstrap!2026"


@pytest.fixture()
def app():
    application = create_app("testing")
    with application.app_context():
        db.create_all()
        db.session.add(
            Staff(
                username="director",
                email="director@lamaliva.local",
                full_name="Hotel Director",
                password_hash=hash_password(ADMIN_PASSWORD),
                role=ROLE_ADMIN,
                status=STATUS_ACTIVE,
                must_change_password=True,
            )
        )
        db.session.commit()
        yield application
        db.session.remove()
        db.drop_all()


@pytest.fixture()
def client(app):
    return app.test_client()


@pytest.fixture()
def auth(client):
    """Sign in and return (headers, session_payload)."""

    def _login(username="director", password=ADMIN_PASSWORD, fingerprint="test-device"):
        response = client.post(
            "/api/v1/auth/login",
            json={
                "username": username,
                "password": password,
                "device": {
                    "name": "Pytest workstation",
                    "platform": "windows",
                    "fingerprint": fingerprint,
                },
            },
        )
        assert response.status_code == 200, response.get_json()
        payload = response.get_json()["data"]
        return {"Authorization": f"Bearer {payload['access_token']}"}, payload

    return _login
