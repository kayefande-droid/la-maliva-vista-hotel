"""Guests: registration is final, sealed and Cameroon-first.

Rules this module enforces, because the hotel asked for them:

* A guest is registered once. The record is sealed (HMAC-SHA256 over its own
  fields, keyed with the application secret) at creation and refused every
  later edit, so what the desk recorded is what the hotel can prove.
* Identification is required and checked against the document types a
  Cameroon business actually sees: CNI, birth certificate / kit number,
  passport and residence permit. The number must be in the document's own
  format, and the same document cannot be registered twice.
* `id_number` and `date_of_birth` are returned only to a role holding
  `guest:restricted` (administrator). Everyone else sees that a document is on
  file without seeing it.
"""
from __future__ import annotations

import re
import secrets

from flask import Blueprint, g, jsonify, request

from ..extensions import db
from ..models import Guest, utcnow
from ..security import (
    audit,
    hash_identity,
    has_permission,
    json_error,
    require_auth,
    require_permission,
    seal_record,
)
from ._util import body, iso, page_args, paginated

bp = Blueprint("guests", __name__)

# Document type -> (human name, accepted format).
ID_TYPES: dict[str, tuple[str, re.Pattern[str]]] = {
    "cni": ("Cameroon national ID (CNI)", re.compile(r"^\d{8,12}$")),
    "birth_certificate": (
        "Birth certificate / kit number",
        re.compile(r"^[A-Z0-9][A-Z0-9/\-]{3,19}$"),
    ),
    "passport": ("Passport", re.compile(r"^[A-Z]{1,2}\d{6,8}$")),
    "residence_permit": (
        "Residence permit",
        re.compile(r"^[A-Z0-9][A-Z0-9/\-]{3,19}$"),
    ),
}

# Cameroon mobile numbers: +237 6XXXXXXXX, or the local 6XXXXXXXX form.
PHONE_RE = re.compile(r"^(?:\+?237)?6\d{8}$")


class IdentityError(Exception):
    """Raised when a registration cannot be accepted; carries an HTTP status."""

    def __init__(self, code: str, message: str, status: int = 400) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status


def _reference() -> str:
    return "G" + secrets.token_hex(4).upper()


def _clean(value) -> str:
    return str(value if value is not None else "").strip()


def normalise_identity(raw_type, raw_number) -> tuple[str, str]:
    """Return (id_type, canonical id_number) or raise IdentityError."""
    id_type = _clean(raw_type).lower()
    id_number = "".join(_clean(raw_number).split()).upper()

    if not id_type or not id_number:
        raise IdentityError(
            "identity_required",
            "Record the guest's identification document type and number. "
            "Registration is final, so the document must be correct.",
        )
    if id_type not in ID_TYPES:
        raise IdentityError(
            "unsupported_id_type",
            "id_type must be one of: " + ", ".join(sorted(ID_TYPES)) + ".",
        )

    label, pattern = ID_TYPES[id_type]
    if not pattern.match(id_number):
        raise IdentityError(
            "invalid_id_number",
            f"{label} numbers are not in the expected format. "
            "Check the document and enter the original number exactly as printed.",
        )
    return id_type, id_number


def normalise_phone(raw) -> str | None:
    phone = "".join(_clean(raw).split())
    if not phone:
        return None
    if not PHONE_RE.match(phone):
        raise IdentityError(
            "invalid_phone",
            "Enter a Cameroon mobile number, for example +237 6XX XXX XXX.",
        )
    return phone


def seal_payload(guest: Guest) -> dict:
    """The exact field set a guest's seal covers."""
    return {
        "reference": guest.reference,
        "first_name": guest.first_name,
        "last_name": guest.last_name,
        "phone": guest.phone,
        "email": guest.email,
        "nationality": guest.nationality,
        "address": guest.address,
        "id_type": guest.id_type,
        "id_number": guest.id_number,
        "date_of_birth": guest.date_of_birth.isoformat() if guest.date_of_birth else None,
        "created_by": guest.created_by,
    }


def seal_matches(guest: Guest) -> bool:
    if not guest.record_seal:
        return False
    return seal_record(seal_payload(guest), purpose="guest") == guest.record_seal


def build_guest(data: dict, *, staff_id: int) -> Guest:
    """Build, validate and seal a guest. Does not commit.

    Identification may arrive flat (`id_type` / `id_number`) or nested under
    `identity`, because both shapes are used by the desk apps.

    Raises IdentityError for anything the desk must correct.
    """
    first = _clean(data.get("first_name"))
    last = _clean(data.get("last_name"))
    if not first or not last:
        raise IdentityError("missing_name", "First and last name are required.")

    identity = data.get("identity") if isinstance(data.get("identity"), dict) else {}
    id_type, id_number = normalise_identity(
        data.get("id_type") or identity.get("id_type"),
        data.get("id_number") or identity.get("id_number"),
    )
    phone = normalise_phone(data.get("phone"))

    fingerprint = hash_identity(id_number)
    existing = db.session.scalar(
        db.select(Guest).where(Guest.id_number_hash == fingerprint)
    )
    if existing is not None:
        raise IdentityError(
            "duplicate_identity",
            f"That document is already registered to guest {existing.reference}. "
            "A person is registered once; use their existing record.",
            409,
        )

    guest = Guest(
        reference=_reference(),
        first_name=first[:80],
        last_name=last[:80],
        email=(_clean(data.get("email")) or None),
        phone=phone,
        nationality=(_clean(data.get("nationality")) or "Cameroonian")[:64],
        address=(_clean(data.get("address")) or None),
        notes=(_clean(data.get("notes")) or None),
        vip=bool(data.get("vip")),
        id_type=id_type,
        id_number=id_number,
        id_number_hash=fingerprint,
        created_by=staff_id,
    )
    guest.record_seal = seal_record(seal_payload(guest), purpose="guest")
    guest.sealed_at = utcnow()
    return guest


def serialize_guest(guest: Guest, include_restricted: bool) -> dict:
    payload = {
        "id": guest.id,
        "reference": guest.reference,
        "first_name": guest.first_name,
        "last_name": guest.last_name,
        "display_name": guest.display_name,
        "email": guest.email,
        "phone": guest.phone,
        "nationality": guest.nationality,
        "address": guest.address,
        "vip": guest.vip,
        "notes": guest.notes,
        "created_at": iso(guest.created_at),
        "updated_at": iso(guest.updated_at),
        "reservations": len(guest.reservations),
        "sealed_at": iso(guest.sealed_at),
        "seal": guest.record_seal,
        "seal_valid": seal_matches(guest),
        "identity": {"restricted": True}
        if not include_restricted
        else {
            "id_type": guest.id_type,
            "id_number": guest.id_number,
            "date_of_birth": guest.date_of_birth.isoformat()
            if guest.date_of_birth
            else None,
            "id_type_label": ID_TYPES.get(guest.id_type or "", ("", None))[0],
        },
    }
    return payload


def guest_error(error: IdentityError):
    return json_error(error.status, error.code, error.message)


@bp.get("")
@require_auth
@require_permission("guest:read")
def list_guests():
    limit, offset = page_args()
    include_restricted = has_permission(g.staff.role, "guest:restricted")

    query = db.select(Guest)
    search = (request.args.get("q") or "").strip()
    if search:
        like = f"%{search.lower()}%"
        query = query.where(
            db.or_(
                db.func.lower(Guest.first_name).like(like),
                db.func.lower(Guest.last_name).like(like),
                db.func.lower(db.func.coalesce(Guest.email, "")).like(like),
                db.func.coalesce(Guest.phone, "").like(f"%{search}%"),
                db.func.upper(Guest.reference).like(f"%{search.upper()}%"),
            )
        )
    if (request.args.get("vip") or "").lower() in {"1", "true", "yes"}:
        query = query.where(Guest.vip.is_(True))

    total = db.session.scalar(db.select(db.func.count()).select_from(query.subquery())) or 0
    rows = db.session.scalars(
        query.order_by(Guest.last_name, Guest.first_name).limit(limit).offset(offset)
    ).all()
    return paginated(
        [serialize_guest(row, include_restricted) for row in rows], total, limit, offset
    )


@bp.get("/<int:guest_id>")
@require_auth
@require_permission("guest:read")
def get_guest(guest_id: int):
    guest = db.session.get(Guest, guest_id)
    if guest is None:
        return json_error(404, "guest_not_found", "No such guest.")
    return jsonify(
        {"data": serialize_guest(guest, has_permission(g.staff.role, "guest:restricted"))}
    )


@bp.post("")
@require_auth
@require_permission("guest:write")
def create_guest():
    try:
        guest = build_guest(body(), staff_id=g.staff.id)
    except IdentityError as error:
        return guest_error(error)

    db.session.add(guest)
    db.session.flush()
    audit(
        "guest.created",
        "guest",
        guest.id,
        after={"reference": guest.reference, "seal": guest.record_seal},
    )
    db.session.commit()

    return (
        jsonify({"data": serialize_guest(guest, has_permission(g.staff.role, "guest:restricted"))}),
        201,
    )


@bp.patch("/<int:guest_id>")
@require_auth
@require_permission("guest:write")
def update_guest(guest_id: int):
    """Refused, deliberately.

    A registered guest is a record, not a draft. Corrections are made by
    registering a new stay or by an administrator via the database console,
    so this endpoint answers with the reason rather than silently failing.
    """
    guest = db.session.get(Guest, guest_id)
    if guest is None:
        return json_error(404, "guest_not_found", "No such guest.")
    return json_error(
        403,
        "record_immutable",
        "Guest registrations cannot be edited once saved. "
        "The record is sealed and final; ask an administrator for a correction.",
    )


@bp.get("/<int:guest_id>/history")
@require_auth
@require_permission("guest:read")
def guest_history(guest_id: int):
    from .reservations import serialize_reservation

    guest = db.session.get(Guest, guest_id)
    if guest is None:
        return json_error(404, "guest_not_found", "No such guest.")
    rows = sorted(guest.reservations, key=lambda r: r.arrival, reverse=True)
    return jsonify({"data": [serialize_reservation(row) for row in rows]})


@bp.get("/id-types")
@require_auth
@require_permission("guest:read")
def id_types():
    """The documents the desk may record, with their accepted formats."""
    return jsonify(
        {
            "data": [
                {
                    "value": key,
                    "label": label,
                    "hint": {
                        "cni": "9 to 12 digits, as printed on the card.",
                        "birth_certificate": "The kit / certificate number, letters and digits.",
                        "passport": "Two letters followed by seven digits.",
                        "residence_permit": "Permit number, letters and digits.",
                    }[key],
                }
                for key, (label, _) in ID_TYPES.items()
            ]
        }
    )
