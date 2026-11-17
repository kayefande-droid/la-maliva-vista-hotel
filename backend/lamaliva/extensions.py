"""Shared extension instances (bound to the app in the factory).

Flask-Migrate/Alembic are optional at import time so the API can start on a
machine where they are not installed yet. Schema changes are then applied with
`migrations/` SQL files and the migration runner in `lamaliva.migrate`.
"""
from __future__ import annotations

from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

try:  # pragma: no cover - depends on the machine
    from flask_migrate import Migrate

    migrate = Migrate()
    HAS_ALEMBIC = True
except Exception:  # noqa: BLE001
    migrate = None
    HAS_ALEMBIC = False
