"""API v1 blueprint registry.

Every router lives in its own module and is registered here with its own
prefix, so the URL surface is one readable list.
"""
from __future__ import annotations

from flask import Blueprint

api_bp = Blueprint("api_v1", __name__)

from .audit import bp as audit_bp  # noqa: E402
from .auth import bp as auth_bp  # noqa: E402
from .devices import bp as devices_bp  # noqa: E402
from .guests import bp as guests_bp  # noqa: E402
from .health import bp as health_bp  # noqa: E402
from .inventory import bp as inventory_bp  # noqa: E402
from .keys import bp as keys_bp  # noqa: E402
from .notifications import bp as notifications_bp  # noqa: E402
from .notifications import settings_bp  # noqa: E402
from .reports import bp as reports_bp  # noqa: E402
from .reservations import bp as reservations_bp  # noqa: E402
from .stays import bp as stays_bp  # noqa: E402
from .rooms import bp as rooms_bp  # noqa: E402
from .staff import bp as staff_bp  # noqa: E402

api_bp.register_blueprint(auth_bp, url_prefix="/auth")
api_bp.register_blueprint(devices_bp, url_prefix="/devices")
api_bp.register_blueprint(keys_bp, url_prefix="/auth-keys")
api_bp.register_blueprint(guests_bp, url_prefix="/guests")
api_bp.register_blueprint(rooms_bp, url_prefix="/rooms")
api_bp.register_blueprint(staff_bp, url_prefix="/staff")
api_bp.register_blueprint(reservations_bp, url_prefix="/reservations")
api_bp.register_blueprint(stays_bp, url_prefix="/stays")
api_bp.register_blueprint(inventory_bp, url_prefix="/inventory")
api_bp.register_blueprint(reports_bp, url_prefix="/reports")
api_bp.register_blueprint(audit_bp, url_prefix="/audit")
api_bp.register_blueprint(notifications_bp, url_prefix="")
api_bp.register_blueprint(settings_bp, url_prefix="/settings")
api_bp.register_blueprint(health_bp)


@api_bp.get("")
def index():
    return {
        "service": "lamaliva-hotel-api",
        "version": "1",
        "health": "/api/v1/health",
    }
