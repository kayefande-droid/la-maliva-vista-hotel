"""Health and version endpoints. No authentication, no hotel data."""
from __future__ import annotations

from flask import Blueprint, jsonify

from ..extensions import db

bp = Blueprint("health", __name__)


@bp.get("/health")
def health():
    database = "ok"
    try:
        db.session.execute(db.text("SELECT 1"))
    except Exception:  # noqa: BLE001
        database = "unavailable"
        db.session.rollback()

    status = 200 if database == "ok" else 503
    return (
        jsonify(
            {
                "status": "ok" if database == "ok" else "degraded",
                "service": "lamaliva-hotel-api",
                "version": "1.0.0",
                "database": database,
                "time": __import__("datetime").datetime.utcnow().isoformat() + "Z",
            }
        ),
        status,
    )
