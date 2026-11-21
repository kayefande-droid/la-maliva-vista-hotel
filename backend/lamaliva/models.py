"""Domain model for the LA-MALIVA VISTA hotel system.

One PostgreSQL database is the single source of truth for the Windows and
Android applications. Enumerated values are plain strings with constants so
that migrations stay readable and Postgres enums do not fight Alembic.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import func

from .extensions import db

# --- Enumerated values -------------------------------------------------
ROLE_ADMIN = "admin"
ROLE_MANAGER = "manager"
ROLE_RECEPTION = "receptionist"
ROLE_HOUSEKEEPING = "housekeeping"
ROLE_INVENTORY = "inventory"
ROLES = (ROLE_ADMIN, ROLE_MANAGER, ROLE_RECEPTION, ROLE_HOUSEKEEPING, ROLE_INVENTORY)

STATUS_ACTIVE = "active"
STATUS_SUSPENDED = "suspended"
STATUS_INVITED = "invited"

ROOM_AVAILABLE = "available"
ROOM_OCCUPIED = "occupied"
ROOM_RESERVED = "reserved"
ROOM_CLEANING = "cleaning"
ROOM_MAINTENANCE = "maintenance"
ROOM_STATUSES = (
    ROOM_AVAILABLE,
    ROOM_OCCUPIED,
    ROOM_RESERVED,
    ROOM_CLEANING,
    ROOM_MAINTENANCE,
)

# --- Stay pricing -----------------------------------------------------
PRICING_NIGHTLY = "nightly"
PRICING_HOURLY = "hourly"
PRICING_CUSTOM = "custom"
PRICING_TYPES = (PRICING_NIGHTLY, PRICING_HOURLY, PRICING_CUSTOM)

# Occupancy states are derived by the stay engine from the server clock; they
# are never stored, so a client clock can never disagree with the backend.
STAY_RESERVED = "reserved"
STAY_ACTIVE = "active"
STAY_CHECKOUT_APPROACHING = "checkout_approaching"
STAY_CHECKOUT_DUE = "checkout_due"
STAY_OVERDUE = "overdue"
STAY_EXTENSION_PENDING = "extension_pending"
STAY_CHECKED_OUT = "checked_out"
STAY_STATES = (
    STAY_RESERVED,
    STAY_ACTIVE,
    STAY_CHECKOUT_APPROACHING,
    STAY_CHECKOUT_DUE,
    STAY_OVERDUE,
    STAY_EXTENSION_PENDING,
    STAY_CHECKED_OUT,
)

# Payment states are kept separate from occupancy states: a guest can be in
# the room with a balance owing and that is not an error.
PAY_UNPAID = "unpaid"
PAY_DEPOSIT = "deposit_paid"
PAY_PARTIAL = "partially_paid"
PAY_PAID = "fully_paid"
PAY_REFUND_PENDING = "refund_pending"
PAY_REFUNDED = "refunded"
PAY_DISPUTED = "payment_disputed"
PAY_STATES = (
    PAY_UNPAID,
    PAY_DEPOSIT,
    PAY_PARTIAL,
    PAY_PAID,
    PAY_REFUND_PENDING,
    PAY_REFUNDED,
    PAY_DISPUTED,
)

PAYMENT_IN = "payment"
PAYMENT_REFUND = "refund"
PAYMENT_KINDS = (PAYMENT_IN, PAYMENT_REFUND)

EXTENSION_PENDING = "pending"
EXTENSION_APPROVED = "approved"
EXTENSION_REJECTED = "rejected"
EXTENSION_STATES = (EXTENSION_PENDING, EXTENSION_APPROVED, EXTENSION_REJECTED)

RES_PENDING = "pending"
RES_CONFIRMED = "confirmed"
RES_CHECKED_IN = "checked_in"
RES_CHECKED_OUT = "checked_out"
RES_CANCELLED = "cancelled"
RES_NO_SHOW = "no_show"
RESERVATION_STATUSES = (
    RES_PENDING,
    RES_CONFIRMED,
    RES_CHECKED_IN,
    RES_CHECKED_OUT,
    RES_CANCELLED,
    RES_NO_SHOW,
)

MOVEMENT_IN = "in"
MOVEMENT_OUT = "out"
MOVEMENT_ADJUST = "adjust"


def utcnow() -> datetime:
    """Naive UTC, so SQLite and PostgreSQL compare identically."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def new_id() -> str:
    return uuid.uuid4().hex


class TimestampMixin:
    created_at = db.Column(db.DateTime, default=utcnow, nullable=False)
    updated_at = db.Column(
        db.DateTime, default=utcnow, onupdate=utcnow, nullable=False, index=True
    )


# --- Identity ----------------------------------------------------------
class Staff(TimestampMixin, db.Model):
    __tablename__ = "staff"

    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(64), unique=True, nullable=False, index=True)
    email = db.Column(db.String(160), unique=True, nullable=False, index=True)
    full_name = db.Column(db.String(160), nullable=False, default="")
    phone = db.Column(db.String(40), nullable=True)
    password_hash = db.Column(db.String(255), nullable=False)
    role = db.Column(db.String(24), nullable=False, default=ROLE_RECEPTION, index=True)
    status = db.Column(db.String(16), nullable=False, default=STATUS_ACTIVE, index=True)

    must_change_password = db.Column(db.Boolean, nullable=False, default=True)
    password_changed_at = db.Column(db.DateTime, nullable=True)
    failed_logins = db.Column(db.Integer, nullable=False, default=0)
    locked_until = db.Column(db.DateTime, nullable=True)
    last_login_at = db.Column(db.DateTime, nullable=True)

    totp_secret = db.Column(db.String(64), nullable=True)
    totp_enabled = db.Column(db.Boolean, nullable=False, default=False)

    # Bumped on password change / suspension: every token issued before this
    # instant is rejected, without needing to hunt down individual tokens.
    tokens_valid_from = db.Column(db.DateTime, nullable=False, default=utcnow)

    created_by = db.Column(db.Integer, db.ForeignKey("staff.id"), nullable=True)

    devices = db.relationship("Device", back_populates="staff", cascade="all, delete-orphan")
    refresh_tokens = db.relationship(
        "RefreshToken", back_populates="staff", cascade="all, delete-orphan"
    )

    def is_locked(self) -> bool:
        return bool(self.locked_until and self.locked_until > utcnow())

    def is_active(self) -> bool:
        return self.status == STATUS_ACTIVE


class Device(TimestampMixin, db.Model):
    __tablename__ = "device"
    __table_args__ = (db.UniqueConstraint("staff_id", "fingerprint", name="uq_device_owner"),)

    id = db.Column(db.Integer, primary_key=True)
    public_id = db.Column(db.String(32), unique=True, nullable=False, default=new_id, index=True)
    staff_id = db.Column(db.Integer, db.ForeignKey("staff.id"), nullable=False, index=True)
    name = db.Column(db.String(120), nullable=False, default="Unnamed device")
    platform = db.Column(db.String(24), nullable=False, default="unknown")  # windows|android
    fingerprint = db.Column(db.String(128), nullable=False)
    app_version = db.Column(db.String(32), nullable=True)
    last_seen_at = db.Column(db.DateTime, nullable=True)
    revoked_at = db.Column(db.DateTime, nullable=True)
    revoked_reason = db.Column(db.String(160), nullable=True)

    staff = db.relationship("Staff", back_populates="devices")

    @property
    def is_revoked(self) -> bool:
        return self.revoked_at is not None


class RefreshToken(db.Model):
    __tablename__ = "refresh_token"

    id = db.Column(db.Integer, primary_key=True)
    token_hash = db.Column(db.String(64), unique=True, nullable=False, index=True)
    staff_id = db.Column(db.Integer, db.ForeignKey("staff.id"), nullable=False, index=True)
    device_id = db.Column(db.Integer, db.ForeignKey("device.id"), nullable=False, index=True)
    family_id = db.Column(db.String(32), nullable=False, index=True)
    issued_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    expires_at = db.Column(db.DateTime, nullable=False)
    used_at = db.Column(db.DateTime, nullable=True)
    revoked_at = db.Column(db.DateTime, nullable=True)

    staff = db.relationship("Staff", back_populates="refresh_tokens")

    def is_usable(self) -> bool:
        return (
            self.revoked_at is None
            and self.used_at is None
            and self.expires_at > utcnow()
        )


class AuthKey(db.Model):
    """The 50-character authorization key.

    Only an argon2 hash is stored. `plaintext` exists in memory for the single
    response that issues the key and is never persisted or logged.
    """

    __tablename__ = "auth_key"

    id = db.Column(db.Integer, primary_key=True)
    staff_id = db.Column(db.Integer, db.ForeignKey("staff.id"), nullable=False, index=True)
    key_hash = db.Column(db.String(255), nullable=False)
    key_prefix = db.Column(db.String(6), nullable=False)  # safe for audit logs
    purpose = db.Column(db.String(48), nullable=False, default="sensitive-operations")
    issued_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    expires_at = db.Column(db.DateTime, nullable=False)
    display_until = db.Column(db.DateTime, nullable=False)
    used_at = db.Column(db.DateTime, nullable=True)
    revoked_at = db.Column(db.DateTime, nullable=True)
    issued_by_device_id = db.Column(db.Integer, db.ForeignKey("device.id"), nullable=True)

    def is_live(self) -> bool:
        return (
            self.revoked_at is None
            and self.used_at is None
            and self.expires_at > utcnow()
        )


# --- Hotel domain ------------------------------------------------------
class RoomType(TimestampMixin, db.Model):
    __tablename__ = "room_type"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(64), unique=True, nullable=False)
    capacity = db.Column(db.Integer, nullable=False, default=2)
    base_rate = db.Column(db.Numeric(12, 2), nullable=False, default=0)
    size_sqm = db.Column(db.Numeric(6, 1), nullable=True)
    description = db.Column(db.String(400), nullable=True)
    image_url = db.Column(db.String(300), nullable=True)

    rooms = db.relationship("Room", back_populates="room_type")


class Room(TimestampMixin, db.Model):
    __tablename__ = "room"

    id = db.Column(db.Integer, primary_key=True)
    number = db.Column(db.String(12), unique=True, nullable=False, index=True)
    room_type_id = db.Column(db.Integer, db.ForeignKey("room_type.id"), nullable=True)
    floor = db.Column(db.Integer, nullable=True)
    status = db.Column(db.String(20), nullable=False, default=ROOM_AVAILABLE, index=True)
    housekeeping = db.Column(db.String(20), nullable=False, default="clean")
    maintenance_note = db.Column(db.String(300), nullable=True)
    notes = db.Column(db.String(300), nullable=True)
    active = db.Column(db.Boolean, nullable=False, default=True)

    room_type = db.relationship("RoomType", back_populates="rooms")
    reservations = db.relationship("Reservation", back_populates="room")


class Guest(TimestampMixin, db.Model):
    __tablename__ = "guest"

    id = db.Column(db.Integer, primary_key=True)
    reference = db.Column(db.String(16), unique=True, nullable=False, index=True)
    first_name = db.Column(db.String(80), nullable=False)
    last_name = db.Column(db.String(80), nullable=False)
    email = db.Column(db.String(160), nullable=True, index=True)
    phone = db.Column(db.String(40), nullable=True, index=True)
    nationality = db.Column(db.String(64), nullable=True)
    address = db.Column(db.String(300), nullable=True)

    # Restricted fields: never returned without guest:restricted permission.
    id_type = db.Column(db.String(40), nullable=True)
    id_number = db.Column(db.String(64), nullable=True)
    date_of_birth = db.Column(db.Date, nullable=True)

    notes = db.Column(db.Text, nullable=True)
    vip = db.Column(db.Boolean, nullable=False, default=False)
    created_by = db.Column(db.Integer, db.ForeignKey("staff.id"), nullable=True)

    # Registration is final: the record is sealed at creation and refused any
    # later edit. `id_number_hash` is a keyed fingerprint used to reject the
    # same document twice; the number itself is only shown to an administrator.
    id_number_hash = db.Column(db.String(64), nullable=True, unique=True, index=True)
    record_seal = db.Column(db.String(64), nullable=True)
    sealed_at = db.Column(db.DateTime, nullable=True)

    reservations = db.relationship("Reservation", back_populates="guest")

    @property
    def display_name(self) -> str:
        return f"{self.first_name} {self.last_name}".strip()


class Reservation(TimestampMixin, db.Model):
    __tablename__ = "reservation"

    id = db.Column(db.Integer, primary_key=True)
    reference = db.Column(db.String(16), unique=True, nullable=False, index=True)
    guest_id = db.Column(db.Integer, db.ForeignKey("guest.id"), nullable=False, index=True)
    room_id = db.Column(db.Integer, db.ForeignKey("room.id"), nullable=True, index=True)

    arrival = db.Column(db.Date, nullable=False, index=True)
    departure = db.Column(db.Date, nullable=False, index=True)
    adults = db.Column(db.Integer, nullable=False, default=1)
    children = db.Column(db.Integer, nullable=False, default=0)

    status = db.Column(db.String(20), nullable=False, default=RES_CONFIRMED, index=True)
    rate_per_night = db.Column(db.Numeric(12, 2), nullable=False, default=0)
    total_amount = db.Column(db.Numeric(12, 2), nullable=False, default=0)
    currency = db.Column(db.String(8), nullable=False, default="XAF")
    source = db.Column(db.String(32), nullable=False, default="reception")
    notes = db.Column(db.Text, nullable=True)

    # --- The stay clock ---------------------------------------------
    # `expected_checkout_at` is the authoritative expiry instant, computed by
    # the server when the guest checks in and moved only by an approved
    # extension. `original_checkout_at` preserves what was first agreed.
    pricing_type = db.Column(db.String(12), nullable=False, default=PRICING_NIGHTLY)
    stay_hours = db.Column(db.Integer, nullable=True)
    expected_checkout_at = db.Column(db.DateTime, nullable=True, index=True)
    original_checkout_at = db.Column(db.DateTime, nullable=True)
    checkout_note = db.Column(db.String(400), nullable=True)
    receipt_reference = db.Column(db.String(24), nullable=True)
    outstanding_authorised_by = db.Column(
        db.Integer, db.ForeignKey("staff.id"), nullable=True
    )
    housekeep_task_at = db.Column(db.DateTime, nullable=True)

    checked_in_at = db.Column(db.DateTime, nullable=True)
    checked_in_by = db.Column(db.Integer, db.ForeignKey("staff.id"), nullable=True)
    checked_out_at = db.Column(db.DateTime, nullable=True)
    checked_out_by = db.Column(db.Integer, db.ForeignKey("staff.id"), nullable=True)

    idempotency_key = db.Column(db.String(64), unique=True, nullable=True)
    created_by = db.Column(db.Integer, db.ForeignKey("staff.id"), nullable=True)

    guest = db.relationship("Guest", back_populates="reservations")
    room = db.relationship("Room", back_populates="reservations")
    payments = db.relationship(
        "Payment",
        back_populates="reservation",
        cascade="all, delete-orphan",
        order_by="Payment.created_at",
    )
    extensions = db.relationship(
        "StayExtension",
        back_populates="reservation",
        cascade="all, delete-orphan",
        order_by="StayExtension.created_at",
    )

    def nights(self) -> int:
        return max((self.departure - self.arrival).days, 0)

    @property
    def is_in_house(self) -> bool:
        return self.status == RES_CHECKED_IN


class Payment(db.Model):
    """Money received against a stay, or refunded to the guest.

    Append-only: a mistake is corrected with a compensating refund, never by
    editing history, so the cash drawer and the stay always reconcile.
    """

    __tablename__ = "payment"

    id = db.Column(db.Integer, primary_key=True)
    reservation_id = db.Column(
        db.Integer, db.ForeignKey("reservation.id"), nullable=False, index=True
    )
    kind = db.Column(db.String(12), nullable=False, default=PAYMENT_IN)
    amount = db.Column(db.Numeric(12, 2), nullable=False, default=0)
    currency = db.Column(db.String(8), nullable=False, default="XAF")
    method = db.Column(db.String(24), nullable=False, default="cash")
    reference = db.Column(db.String(64), nullable=True)
    notes = db.Column(db.String(300), nullable=True)
    received_by = db.Column(db.Integer, db.ForeignKey("staff.id"), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow, index=True)

    reservation = db.relationship("Reservation", back_populates="payments")


class StayExtension(db.Model):
    """A request to keep the room longer than the agreed checkout.

    The original stay is never overwritten: the reservation keeps
    `original_checkout_at`, and every move of the expiry is one of these rows.
    """

    __tablename__ = "stay_extension"

    id = db.Column(db.Integer, primary_key=True)
    reservation_id = db.Column(
        db.Integer, db.ForeignKey("reservation.id"), nullable=False, index=True
    )
    minutes = db.Column(db.Integer, nullable=False, default=0)
    pricing_type = db.Column(db.String(12), nullable=False, default=PRICING_NIGHTLY)
    additional_charge = db.Column(db.Numeric(12, 2), nullable=False, default=0)
    original_checkout_at = db.Column(db.DateTime, nullable=False)
    new_checkout_at = db.Column(db.DateTime, nullable=False)
    status = db.Column(db.String(16), nullable=False, default=EXTENSION_PENDING, index=True)
    note = db.Column(db.String(300), nullable=True)
    conflict_note = db.Column(db.String(300), nullable=True)
    requested_by = db.Column(db.Integer, db.ForeignKey("staff.id"), nullable=True)
    approved_by = db.Column(db.Integer, db.ForeignKey("staff.id"), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow, index=True)
    decided_at = db.Column(db.DateTime, nullable=True)

    reservation = db.relationship("Reservation", back_populates="extensions")


class StayAlert(db.Model):
    """One row per (stay, threshold) so an alert is never raised twice."""

    __tablename__ = "stay_alert"
    __table_args__ = (
        db.UniqueConstraint("reservation_id", "threshold_minutes", name="uq_stay_alert"),
    )

    id = db.Column(db.Integer, primary_key=True)
    reservation_id = db.Column(
        db.Integer, db.ForeignKey("reservation.id"), nullable=False, index=True
    )
    threshold_minutes = db.Column(db.Integer, nullable=False)
    kind = db.Column(db.String(24), nullable=False, default="checkout")
    expected_checkout_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow, index=True)


class InventoryItem(TimestampMixin, db.Model):
    __tablename__ = "inventory_item"

    id = db.Column(db.Integer, primary_key=True)
    sku = db.Column(db.String(32), unique=True, nullable=False, index=True)
    name = db.Column(db.String(120), nullable=False)
    category = db.Column(db.String(48), nullable=False, default="general", index=True)
    unit = db.Column(db.String(24), nullable=False, default="unit")
    quantity = db.Column(db.Numeric(12, 2), nullable=False, default=0)
    reorder_level = db.Column(db.Numeric(12, 2), nullable=False, default=0)
    unit_cost = db.Column(db.Numeric(12, 2), nullable=False, default=0)
    location = db.Column(db.String(80), nullable=True)
    active = db.Column(db.Boolean, nullable=False, default=True)

    movements = db.relationship("StockMovement", back_populates="item")

    @property
    def is_low(self) -> bool:
        return self.quantity <= self.reorder_level


class StockMovement(db.Model):
    __tablename__ = "stock_movement"

    id = db.Column(db.Integer, primary_key=True)
    item_id = db.Column(db.Integer, db.ForeignKey("inventory_item.id"), nullable=False, index=True)
    kind = db.Column(db.String(12), nullable=False)  # in | out | adjust
    quantity = db.Column(db.Numeric(12, 2), nullable=False)
    reason = db.Column(db.String(200), nullable=True)
    reference = db.Column(db.String(64), nullable=True)
    staff_id = db.Column(db.Integer, db.ForeignKey("staff.id"), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow, index=True)

    item = db.relationship("InventoryItem", back_populates="movements")


class AuditLog(db.Model):
    __tablename__ = "audit_log"

    id = db.Column(db.Integer, primary_key=True)
    actor_id = db.Column(db.Integer, db.ForeignKey("staff.id"), nullable=True, index=True)
    actor_name = db.Column(db.String(120), nullable=True)
    action = db.Column(db.String(64), nullable=False, index=True)
    entity = db.Column(db.String(48), nullable=False, index=True)
    entity_id = db.Column(db.String(64), nullable=True, index=True)
    before = db.Column(db.JSON, nullable=True)
    after = db.Column(db.JSON, nullable=True)
    meta = db.Column(db.JSON, nullable=True)
    ip = db.Column(db.String(64), nullable=True)
    device_id = db.Column(db.Integer, db.ForeignKey("device.id"), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow, index=True)


class Notification(db.Model):
    __tablename__ = "notification"

    id = db.Column(db.Integer, primary_key=True)
    staff_id = db.Column(db.Integer, db.ForeignKey("staff.id"), nullable=True, index=True)
    kind = db.Column(db.String(32), nullable=False, default="system", index=True)
    title = db.Column(db.String(160), nullable=False)
    body = db.Column(db.Text, nullable=False)
    read_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow, index=True)


class HotelSetting(TimestampMixin, db.Model):
    __tablename__ = "hotel_setting"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False, default="LA-MALIVA VISTA HOTEL")
    address = db.Column(
        db.String(300),
        nullable=False,
        default="Opposite Fako Heart Entrance, GRA Bokwaongo, Buea, Cameroon",
    )
    phone = db.Column(db.String(40), nullable=True)
    email = db.Column(db.String(160), nullable=True)
    tax_rate = db.Column(db.Numeric(6, 3), nullable=False, default=0)
    currency = db.Column(db.String(8), nullable=False, default="XAF")
    maps_url = db.Column(db.String(300), nullable=True)
    checkin_time = db.Column(db.String(8), nullable=False, default="14:00")
    checkout_time = db.Column(db.String(8), nullable=False, default="12:00")

    # --- Accommodation and checkout policy --------------------------
    # New policy values apply to stays created afterwards; an existing stay is
    # only re-priced when an administrator explicitly re-times it.
    timezone = db.Column(db.String(48), nullable=False, default="Africa/Douala")
    nightly_enabled = db.Column(db.Boolean, nullable=False, default=True)
    hourly_enabled = db.Column(db.Boolean, nullable=False, default=False)
    hourly_rate_percent = db.Column(db.Integer, nullable=False, default=30)
    grace_minutes = db.Column(db.Integer, nullable=False, default=30)
    late_checkout_fee = db.Column(db.Numeric(12, 2), nullable=False, default=0)
    early_checkin_fee = db.Column(db.Numeric(12, 2), nullable=False, default=0)
    deposit_percent = db.Column(db.Integer, nullable=False, default=0)
    payment_before_occupancy = db.Column(db.Boolean, nullable=False, default=False)
    extension_approval_required = db.Column(db.Boolean, nullable=False, default=True)
    checkout_alert_minutes = db.Column(
        db.JSON, nullable=False, default=lambda: [1440, 360, 120, 30, 0, -60]
    )
    overdue_manager_alert = db.Column(db.Boolean, nullable=False, default=True)


def row_count(model) -> int:
    return db.session.scalar(db.select(func.count()).select_from(model)) or 0


def expires(delta: timedelta) -> datetime:
    return utcnow() + delta
