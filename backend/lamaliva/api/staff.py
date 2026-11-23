"""Staff accounts.

Only an administrator creates staff accounts. Passwords are argon2id hashed,
never echoed back except once at creation, and every new account must change
its password at first sign-in.
"""
from __future__ import annotations

import secrets

from flask import Blueprint, g, jsonify

from ..extensions import db
from ..models import ROLES, ROLE_ADMIN, STATUS_ACTIVE, Staff, utcnow
from ..security import audit, hash_password, json_error, require_auth, require_permission
from ._util import body, iso, page_args, paginated

bp = Blueprint("staff", __name__)

PLACEHOLDER_EMAIL_DOMAIN = "staff.lamaliva.local"


def serialize_staff(row: Staff) -> dict:
    return {
        "id": row.id,
        "username": row.username,
        "email": None
        if (row.email or "").endswith("@" + PLACEHOLDER_EMAIL_DOMAIN)
        else row.email,
        "full_name": row.full_name,
        "role": row.role,
        "status": row.status,
        "must_change_password": row.must_change_password,
        "last_login_at": iso(row.last_login_at),
        "created_at": iso(row.created_at),
    }


@bp.get("")
@require_auth
@require_permission("staff:read")
def list_staff():
    limit, offset = page_args()
    query = db.select(Staff)
    total = db.session.scalar(db.select(db.func.count()).select_from(query.subquery())) or 0
    rows = db.session.scalars(
        query.order_by(Staff.role, Staff.username).limit(limit).offset(offset)
    ).all()
    return paginated([serialize_staff(row) for row in rows], total, limit, offset)


@bp.post("")
@require_auth
@require_permission("staff:manage")
def create_staff():
    data = body()
    username = str(data.get("username") or "").strip().lower()
    full_name = str(data.get("full_name") or "").strip()
    role = str(data.get("role") or "").strip().lower()
    email = str(data.get("email") or "").strip() or None

    if not username or not full_name:
        return json_error(400, "missing_fields", "Username and full name are required.")
    if role not in ROLES:
        return json_error(400, "invalid_role", "role must be one of: " + ", ".join(ROLES) + ".")
    if len(username) < 3:
        return json_error(400, "invalid_username", "Username must be at least 3 characters.")

    if db.session.scalar(db.select(Staff).where(Staff.username == username)) is not None:
        return json_error(409, "duplicate_username", "That username already exists.")
    if email and db.session.scalar(db.select(Staff).where(Staff.email == email)) is not None:
        return json_error(409, "duplicate_email", "That email is already in use.")

    # Email is optional in the desk form, but the column is required and
    # unique; a username-based placeholder keeps both true without inventing
    # an address the hotel would send mail to. It is hidden again on the way
    # out, so the admin only ever sees the address they typed.
    email = email or f"{username}@{PLACEHOLDER_EMAIL_DOMAIN}"

    provided = str(data.get("password") or "").strip()
    generated = not provided
    password = provided or secrets.token_urlsafe(12)
    if len(password) < 8:
        return json_error(400, "weak_password", "Use a password of at least 8 characters.")

    staff = Staff(
        username=username,
        email=email,
        full_name=full_name[:120],
        password_hash=hash_password(password),
        role=role,
        status=STATUS_ACTIVE,
        must_change_password=True,
        password_changed_at=None,
        tokens_valid_from=utcnow(),
    )
    db.session.add(staff)
    db.session.flush()
    audit(
        "staff.created",
        "staff",
        staff.id,
        after={"username": staff.username, "role": staff.role},
    )
    db.session.commit()

    payload = {"data": serialize_staff(staff)}
    if generated:
        # Shown exactly once, to the administrator creating the account.
        payload["meta"] = {"generated_password": password}
    return jsonify(payload), 201


@bp.get("/roles")
@require_auth
@require_permission("staff:read")
def roles():
    return jsonify({"data": list(ROLES), "meta": {"admin_role": ROLE_ADMIN}})
