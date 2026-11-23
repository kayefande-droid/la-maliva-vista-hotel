"""Application factory for the LA-MALIVA VISTA hotel API."""
from __future__ import annotations

import logging
import os
import secrets
from datetime import datetime, timezone

from flask import Flask, jsonify, request

from .config import get_config
from .extensions import db, migrate
from .security import hash_password, json_error

log = logging.getLogger("lamaliva")


def create_app(config_name: str | None = None) -> Flask:
    app = Flask(__name__)
    config = get_config(config_name)
    if hasattr(config, "validate"):
        config.validate()
    app.config.from_object(config)

    if not app.config.get("SECRET_KEY"):
        # Development only: a random key each boot. Production validates above.
        app.config["SECRET_KEY"] = secrets.token_hex(32)
        log.warning("LAMALIVA_SECRET_KEY not set; using an ephemeral development key.")

    engine_options = dict(app.config.get("SQLALCHEMY_ENGINE_OPTIONS") or {})
    if str(app.config["SQLALCHEMY_DATABASE_URI"]).startswith("sqlite"):
        # SQLite rejects pooling arguments meant for PostgreSQL.
        for key in ("pool_size", "max_overflow", "pool_recycle"):
            engine_options.pop(key, None)
    app.config["SQLALCHEMY_ENGINE_OPTIONS"] = engine_options

    db.init_app(app)
    if migrate is not None:
        migrate.init_app(app, db)

    from .api import api_bp

    app.register_blueprint(api_bp, url_prefix=app.config["API_PREFIX"])

    _register_errors(app)
    _register_health(app)
    _register_commands(app)

    @app.after_request
    def security_headers(response):
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault(
            "Permissions-Policy", "geolocation=(), microphone=(), camera=()"
        )
        if request.is_secure:
            response.headers.setdefault(
                "Strict-Transport-Security", "max-age=31536000; includeSubDomains"
            )
        return response

    @app.after_request
    def cors_allowlist(response):
        origin = request.headers.get("Origin")
        allowed = app.config.get("CORS_ORIGINS") or []
        if origin and origin in allowed:
            response.headers["Access-Control-Allow-Origin"] = origin
            response.headers["Vary"] = "Origin"
            response.headers["Access-Control-Allow-Credentials"] = "true"
        return response

    _ensure_schema(app)
    return app


def _ensure_schema(app: Flask) -> None:
    """Additive, idempotent schema guard for hosts without a shell.

    `db.create_all()` opens new tables but never alters an existing one, so a
    deployment would otherwise fail on the first shop sale. Disable with
    LAMALIVA_AUTO_SCHEMA=0 and run scripts/upgrade_occupancy.py instead.
    """
    if app.config.get("TESTING"):
        return
    flag = os.environ.get("LAMALIVA_AUTO_SCHEMA", "1").strip().lower()
    if flag in {"0", "false", "no", "off"}:
        return

    from sqlalchemy import inspect, text

    with app.app_context():
        try:
            db.create_all()
            inspector = inspect(db.engine)
            if inspector.has_table("inventory_item"):
                columns = {
                    column["name"]
                    for column in inspector.get_columns("inventory_item")
                }
                if "sale_price" not in columns:
                    db.session.execute(
                        text(
                            "ALTER TABLE inventory_item "
                            "ADD COLUMN sale_price NUMERIC(12, 2) "
                            "NOT NULL DEFAULT 0"
                        )
                    )
                    db.session.commit()
        except Exception:  # pragma: no cover - depends on the host
            db.session.rollback()
            log.exception(
                "Schema guard could not add the newest tables; "
                "run scripts/upgrade_occupancy.py"
            )


def _register_errors(app: Flask) -> None:
    @app.errorhandler(404)
    def not_found(_):
        return json_error(404, "not_found", "No such resource.")

    @app.errorhandler(405)
    def method_not_allowed(_):
        return json_error(405, "method_not_allowed", "Method not allowed for this route.")

    @app.errorhandler(429)
    def too_many(_):
        return json_error(429, "rate_limited", "Too many requests. Slow down.")

    @app.errorhandler(Exception)
    def unhandled(exc):
        if app.config.get("TESTING"):
            raise exc
        log.exception("Unhandled error on %s %s", request.method, request.path)
        db.session.rollback()
        return json_error(500, "server_error", "Something went wrong on the server.")


def _register_health(app: Flask) -> None:
    @app.get("/healthz")
    def liveness():
        return jsonify({"status": "ok", "service": "lamaliva-api"})


def _register_commands(app: Flask) -> None:
    import click

    @app.cli.command("bootstrap-admin")
    @click.option("--username", default=None, help="Administrator username")
    @click.option("--email", default=None, help="Administrator email")
    @click.option("--password", default=None, help="Provided password (else generated)")
    def bootstrap_admin(username, email, password):
        """Create the first administrator. Prints the password exactly once."""
        from .models import ROLE_ADMIN, STATUS_ACTIVE, Staff

        username = username or app.config["BOOTSTRAP_ADMIN_USERNAME"]
        email = email or f"{username}@lamaliva.local"

        if db.session.scalar(db.select(Staff).where(Staff.role == ROLE_ADMIN)) is not None:
            click.echo("An administrator already exists. Refusing to create another.")
            return

        provided = password or app.config.get("BOOTSTRAP_ADMIN_PASSWORD")
        generated = provided is None
        password = provided or secrets.token_urlsafe(18)

        staff = Staff(
            username=username,
            email=email,
            full_name="Hotel Director",
            password_hash=hash_password(password),
            role=ROLE_ADMIN,
            status=STATUS_ACTIVE,
            must_change_password=True,
            password_changed_at=None,
            tokens_valid_from=datetime.now(timezone.utc).replace(tzinfo=None),
        )
        db.session.add(staff)
        db.session.commit()

        click.echo("Administrator created: " + username)
        click.echo("Password must be changed at first sign-in.")
        if generated:
            click.echo("One-time password (shown once, not stored anywhere):")
            click.echo("    " + password)
        else:
            click.echo("Password taken from LAMALIVA_BOOTSTRAP_PASSWORD.")

    @app.cli.command("seed-demo")
    def seed_demo():
        """Create a small set of rooms so the apps have something real to show."""
        from .models import ROOM_AVAILABLE, Room, RoomType

        if db.session.scalar(db.select(Room).limit(1)) is not None:
            click.echo("Rooms already exist; nothing seeded.")
            return

        standard = RoomType(name="Standard", capacity=2, base_rate=25000, size_sqm=24)
        deluxe = RoomType(name="Deluxe", capacity=2, base_rate=40000, size_sqm=32)
        suite = RoomType(name="Suite", capacity=4, base_rate=65000, size_sqm=48)
        db.session.add_all([standard, deluxe, suite])
        db.session.flush()

        plan = [
            ("101", standard), ("102", standard), ("103", standard),
            ("104", deluxe), ("105", deluxe),
            ("201", standard), ("202", deluxe), ("203", deluxe),
            ("204", suite), ("205", suite),
        ]
        for number, room_type in plan:
            db.session.add(
                Room(
                    number=number,
                    room_type_id=room_type.id,
                    floor=int(number[0]),
                    status=ROOM_AVAILABLE,
                )
            )
        db.session.commit()
        click.echo(f"Seeded {len(plan)} rooms.")
