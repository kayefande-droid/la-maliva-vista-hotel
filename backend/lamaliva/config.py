"""Configuration for the LA-MALIVA VISTA hotel API.

Every value comes from the environment. Nothing secret is committed and no
credential has a working default: the app refuses to start in production
without the required secrets.
"""
from __future__ import annotations

import os
from datetime import timedelta

try:  # python-dotenv is optional; production supplies real environment variables.
    from dotenv import load_dotenv as _load_dotenv

    _load_dotenv(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".env"))
except ImportError:  # pragma: no cover
    pass


def _env(name: str, default: str | None = None) -> str | None:
    value = os.environ.get(name)
    if value is None:
        return default
    value = value.strip()
    return value or default


class BaseConfig:
    # --- Core ---------------------------------------------------------
    SECRET_KEY = _env("LAMALIVA_SECRET_KEY")
    JSON_SORT_KEYS = False
    PREFERRED_URL_SCHEME = "https"

    # --- Database -----------------------------------------------------
    SQLALCHEMY_DATABASE_URI = _env("LAMALIVA_DATABASE_URL", "sqlite:///:memory:")
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {
        "pool_pre_ping": True,
        "pool_size": 10,
        "max_overflow": 10,
        "pool_recycle": 1800,
    }

    # --- Tokens -------------------------------------------------------
    JWT_ALGORITHM = "HS256"
    JWT_ISSUER = "lamaliva-hotel-api"
    ACCESS_TOKEN_TTL = timedelta(minutes=int(_env("LAMALIVA_ACCESS_TTL_MIN", "15")))
    REFRESH_TOKEN_TTL = timedelta(days=int(_env("LAMALIVA_REFRESH_TTL_DAYS", "30")))

    # --- The 50-character authorization key ---------------------------
    AUTH_KEY_LENGTH = 50
    AUTH_KEY_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    AUTH_KEY_TTL = timedelta(hours=24)          # daily rotation
    AUTH_KEY_DISPLAY_TTL = timedelta(minutes=3)  # shown once, then hidden

    # --- Credentials policy -------------------------------------------
    PASSWORD_MIN_LENGTH = 12
    LOGIN_MAX_FAILURES = 5
    LOGIN_LOCK_MINUTES = 15
    BOOTSTRAP_ADMIN_USERNAME = _env("LAMALIVA_BOOTSTRAP_ADMIN", "director")
    BOOTSTRAP_ADMIN_PASSWORD = _env("LAMALIVA_BOOTSTRAP_PASSWORD")

    # --- CORS ---------------------------------------------------------
    CORS_ORIGINS = [
        origin.strip()
        for origin in (_env("LAMALIVA_CORS_ORIGINS", "") or "").split(",")
        if origin.strip()
    ]

    # --- Misc ---------------------------------------------------------
    HOTEL_NAME = "LA-MALIVA VISTA"
    API_PREFIX = "/api/v1"


class DevelopmentConfig(BaseConfig):
    DEBUG = True


class TestConfig(BaseConfig):
    TESTING = True
    SECRET_KEY = "test-only-secret-not-used-anywhere-real"
    SQLALCHEMY_DATABASE_URI = "sqlite://"
    SQLALCHEMY_ENGINE_OPTIONS = {
        "poolclass": __import__("sqlalchemy.pool", fromlist=["StaticPool"]).StaticPool,
        "connect_args": {"check_same_thread": False},
    }
    ACCESS_TOKEN_TTL = timedelta(minutes=15)
    BOOTSTRAP_ADMIN_USERNAME = "director"
    BOOTSTRAP_ADMIN_PASSWORD = "TestBootstrap!2026"


class ProductionConfig(BaseConfig):
    DEBUG = False

    @classmethod
    def validate(cls) -> None:
        missing = [
            name
            for name, value in (
                ("LAMALIVA_SECRET_KEY", cls.SECRET_KEY),
                ("LAMALIVA_DATABASE_URL", _env("LAMALIVA_DATABASE_URL")),
            )
            if not value
        ]
        if missing:
            raise RuntimeError(
                "Refusing to start: missing required environment variable(s): "
                + ", ".join(missing)
            )
        uri = _env("LAMALIVA_DATABASE_URL", "") or ""
        if not uri.startswith("postgresql"):
            raise RuntimeError(
                "Refusing to start: LAMALIVA_DATABASE_URL must point at PostgreSQL "
                "in production (got a non-postgres URL)."
            )


CONFIGS = {
    "development": DevelopmentConfig,
    "testing": TestConfig,
    "production": ProductionConfig,
}


def get_config(name: str | None = None):
    name = (name or _env("LAMALIVA_ENV", "development") or "development").lower()
    return CONFIGS.get(name, DevelopmentConfig)
