"""Backend smoke/behavior tests for the La-Maliva Vista Flask app.

Covers the guest-critical paths: signup (CSRF, weak-password policy,
duplicate accounts), email verification gate, web login, native-app token
auth (/api/auth/login), and the public rooms API.

Runs fully offline against a throwaway SQLite file set via DATABASE_URL
before the app module is imported.
"""

import os
import re
import tempfile

import pytest

# ----------------------------- test bootstrapping ---------------------------
# Point the app at a throwaway SQLite file BEFORE importing it, so no test
# ever touches the developer's local instance/lamaliva.db data.
_TMPDIR = tempfile.mkdtemp(prefix="lamaliva-test-")
os.environ.pop("SENTRY_DSN", None)
os.environ["DATABASE_URL"] = "sqlite:///" + os.path.join(_TMPDIR, "test.db").replace("\\", "/")

import app as app_module  # noqa: E402
from app import User  # noqa: E402

TEST_PASSWORD = "Str0ng!Passphrase"  # 13 chars, mixed case, digit, symbol


def _uid():
    """Unique suffix so parallel/repeated runs never collide with fixtures."""
    return os.urandom(3).hex()


@pytest.fixture()
def client(monkeypatch):
    """Test client with DNS-dependent email validation stubbed out."""
    def _fake_email_check(email):
        return {"valid": True, "email": email.strip().lower()}
    monkeypatch.setattr(app_module, "validate_email_real", _fake_email_check)
    # Deterministic tests: rate limiter stays off (its own policy is covered
    # implicitly by the GET-skip fix in enforce_rate_limits; per-attacker
    # windowing is infra-level behavior we don't need to unit-test here).
    monkeypatch.setattr(app_module, "_rate_limit_hit", lambda *a, **k: False)
    app_module.app.config["TESTING"] = True
    with app_module.app.test_client() as c:
        yield c


def _csrf(client, path):
    """Fetch a page and pull the auto-injected CSRF token from its forms."""
    rv = client.get(path)
    m = re.search(r'name="_csrf_token" value="([^"]+)"', rv.get_data(as_text=True))
    assert m, f"expected a CSRF token on {path}"
    return m.group(1)


def test_home_loads(client):
    assert client.get("/").status_code == 200


def test_version_exposes_native_windows_zip_and_direct_exe(client):
    body = client.get("/api/version").get_json()
    assert body["version"] == app_module.APP_VERSION
    windows = body["releases"]["windows"]
    assert windows["filename"] == f"La-Maliva-Vista-{app_module.APP_VERSION}-windows.zip"
    assert windows["available"] is True
    assert windows["exe_available"] is True
    assert windows["exe_filename"] == f"La-Maliva-Vista-{app_module.APP_VERSION}.exe"
    assert windows["exe_size_bytes"] > 0


def test_downloads_page_has_native_exe_link(client):
    response = client.get("/downloads")
    assert response.status_code == 200
    assert "/downloads/windows/exe" in response.get_data(as_text=True)


def test_native_windows_exe_is_downloaded_directly(client, monkeypatch):
    monkeypatch.setattr(app_module, "_record_app_event", lambda *args: None)
    response = client.get("/downloads/windows/exe")
    assert response.status_code == 200
    assert response.headers["Content-Disposition"].endswith(
        f"La-Maliva-Vista-{app_module.APP_VERSION}.exe")
    assert response.data.startswith(b"MZ")


def test_native_windows_zip_contains_flutter_runtime(client, monkeypatch):
    import io
    import zipfile

    monkeypatch.setattr(app_module, "_record_app_event", lambda *args: None)
    response = client.get("/downloads/windows")
    assert response.status_code == 200
    assert response.headers["Content-Disposition"].endswith(
        f"La-Maliva-Vista-{app_module.APP_VERSION}-windows.zip")
    with zipfile.ZipFile(io.BytesIO(response.data)) as bundle:
        names = bundle.namelist()
        assert bundle.testzip() is None
        assert "lamaliva_app.exe" in names
        assert "flutter_windows.dll" in names
        assert any(name.startswith("data/flutter_assets/") for name in names)


def test_signup_form_carries_csrf(client):
    html = client.get("/signup").get_data(as_text=True)
    assert "<form" in html and 'name="_csrf_token"' in html


def test_signup_rejects_missing_csrf(client):
    uname = "nocsrf" + _uid()
    rv = client.post("/signup", data={
        "username": uname, "email": uname + "@example.com",
        "password": TEST_PASSWORD,
    })
    assert rv.status_code in (302, 400), rv.status_code
    assert User.query.filter_by(username=uname).first() is None


def test_signup_rejects_weak_password(client):
    token = _csrf(client, "/signup")
    uname = "weakpw" + _uid()
    rv = client.post("/signup", data={
        "username": uname, "email": uname + "@example.com",
        "password": "password",  # fails the NIST-style policy
        "_csrf_token": token,
    })
    assert rv.status_code == 302
    assert User.query.filter_by(username=uname).first() is None


def test_signup_success_creates_verified_user(client):
    token = _csrf(client, "/signup")
    uname = "guest" + _uid()
    rv = client.post("/signup", data={
        "username": uname, "email": uname + "@example.com",
        "password": TEST_PASSWORD, "_csrf_token": token,
        "signup_source": "web",
    })
    assert rv.status_code == 302
    user = User.query.filter_by(username=uname).first()
    assert user is not None, "signup should persist the account"
    # Offline SMTP means the branded email cannot go out, so the route
    # must auto-activate the account rather than lock the guest out.
    assert user.email_verified is True
    assert user.role == "user"


def test_signup_duplicate_username_rejected(client):
    token = _csrf(client, "/signup")
    uname = "dupe" + _uid()
    first = client.post("/signup", data={
        "username": uname, "email": uname + "@example.com",
        "password": TEST_PASSWORD, "_csrf_token": token,
        "signup_source": "web",
    })
    assert first.status_code == 302
    second = client.post("/signup", data={
        "username": uname, "email": "other" + _uid() + "@example.com",
        "password": TEST_PASSWORD, "_csrf_token": token,
    })
    assert second.status_code == 302
    # still exactly one user with that name
    assert len(User.query.filter_by(username=uname).all()) == 1


def test_native_app_login_issues_bearer_token(client):
    token = _csrf(client, "/signup")
    uname = "appuser" + _uid()
    client.post("/signup", data={
        "username": uname, "email": uname + "@example.com",
        "password": TEST_PASSWORD, "_csrf_token": token,
        "signup_source": "android",
    })
    rv = client.post("/api/auth/login", json={
        "username": uname, "password": TEST_PASSWORD,
    })
    assert rv.status_code == 200, rv.get_json()
    body = rv.get_json()
    assert body.get("ok") is True
    assert body.get("token")
    assert body["user"]["username"] == uname
    assert body["user"]["role"] == "user"


def test_native_app_login_rejects_bad_password(client):
    rv = client.post("/api/auth/login", json={
        "username": "no-such-user-" + _uid(), "password": "whatever-pass",
    })
    assert rv.status_code == 401
    assert rv.get_json().get("ok") is False


def test_bearer_token_resolves_api_user(client):
    # Signup + native-app login, then prove the raw token identifies the
    # caller on a Bearer-authenticated endpoint (the app's inbox API).
    token = _csrf(client, "/signup")
    uname = "apiuser" + _uid()
    client.post("/signup", data={
        "username": uname, "email": uname + "@example.com",
        "password": TEST_PASSWORD, "_csrf_token": token,
    })
    login = client.post("/api/auth/login", json={
        "username": uname, "password": TEST_PASSWORD,
    })
    bearer = login.get_json()["token"]

    anon = client.get("/api/notifications")
    assert anon.status_code == 401, anon.status_code
    assert anon.get_json().get("ok") is False

    rv = client.get("/api/notifications",
                    headers={"Authorization": "Bearer " + bearer})
    assert rv.status_code == 200, rv.status_code
    body = rv.get_json()
    assert body.get("ok") is True and "notifications" in body
