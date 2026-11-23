"""Inventory: items, stock movements and low-stock notifications."""
from __future__ import annotations

import math
import secrets

from flask import Blueprint, g, jsonify, request

from ..extensions import db
from ..models import (
    MOVEMENT_ADJUST,
    MOVEMENT_IN,
    MOVEMENT_OUT,
    InventoryItem,
    Notification,
    StockMovement,
)
from ..security import audit, json_error, require_auth, require_permission
from ._util import body, iso, money, page_args, paginated

bp = Blueprint("inventory", __name__)


class NumberError(ValueError):
    """A stock figure that is missing, not a number, or out of range."""


def number(raw, *, minimum: float = 0.0, maximum: float | None = None) -> float:
    """A stock or money figure rounded to two places, or [NumberError].

    Charges, counts and prices are the numbers that end up in the hotel's
    books: NaN, infinity and negatives are refused here rather than written
    into a ledger that can only be corrected with a compensating entry.
    """
    try:
        value = float(raw)
    except (TypeError, ValueError):
        raise NumberError("must be a number") from None
    if not math.isfinite(value) or value < minimum:
        raise NumberError(f"must be at least {minimum:g}")
    if maximum is not None and value > maximum:
        raise NumberError(f"must be at most {maximum:g}")
    return round(value, 2)


def serialize_item(item: InventoryItem) -> dict:
    quantity = float(item.quantity or 0)
    cost = float(item.unit_cost or 0)
    price = float(item.sale_price or 0)
    return {
        "id": item.id,
        "sku": item.sku,
        "name": item.name,
        "category": item.category,
        "unit": item.unit,
        "quantity": quantity,
        "reorder_level": float(item.reorder_level or 0),
        "unit_cost": money(item.unit_cost),
        "sale_price": money(item.sale_price),
        "location": item.location,
        "low_stock": item.is_low,
        "in_stock": quantity > 0,
        "sellable": quantity > 0 and price > 0,
        # What the shelf cost the hotel and what it would take if it sold out.
        "stock_value": round(quantity * cost, 2),
        "retail_value": round(quantity * price, 2),
        "updated_at": iso(item.updated_at),
    }


def _low_stock_notification(item: InventoryItem) -> None:
    db.session.add(
        Notification(
            staff_id=None,
            kind="inventory",
            title=f"Low stock — {item.name}",
            body=(
                f"{item.name} is at {float(item.quantity):g} {item.unit} "
                f"(reorder level {float(item.reorder_level):g})."
            ),
        )
    )


@bp.get("/items")
@require_auth
@require_permission("inventory:read")
def list_items():
    limit, offset = page_args()
    query = db.select(InventoryItem).where(InventoryItem.active.is_(True))
    search = (request.args.get("q") or "").strip()
    if search:
        like = f"%{search.lower()}%"
        query = query.where(
            db.or_(
                db.func.lower(InventoryItem.name).like(like),
                db.func.lower(InventoryItem.sku).like(like),
                db.func.lower(InventoryItem.category).like(like),
            )
        )
    if (request.args.get("low") or "").lower() in {"1", "true", "yes"}:
        query = query.where(InventoryItem.quantity <= InventoryItem.reorder_level)

    total = db.session.scalar(db.select(db.func.count()).select_from(query.subquery())) or 0
    rows = db.session.scalars(
        query.order_by(InventoryItem.name).limit(limit).offset(offset)
    ).all()
    return paginated([serialize_item(row) for row in rows], total, limit, offset)


@bp.get("/low-stock")
@require_auth
@require_permission("inventory:read")
def low_stock():
    rows = db.session.scalars(
        db.select(InventoryItem)
        .where(
            InventoryItem.active.is_(True),
            InventoryItem.quantity <= InventoryItem.reorder_level,
        )
        .order_by(InventoryItem.quantity)
    ).all()
    return jsonify({"data": [serialize_item(row) for row in rows], "meta": {"count": len(rows)}})


@bp.post("/items")
@require_auth
@require_permission("inventory:manage")
def create_item():
    data = body()
    name = str(data.get("name") or "").strip()
    if not name:
        return json_error(400, "missing_name", "An item name is required.")

    sku = str(data.get("sku") or "").strip() or "SKU-" + secrets.token_hex(3).upper()
    if db.session.scalar(db.select(InventoryItem).where(InventoryItem.sku == sku)) is not None:
        return json_error(409, "duplicate_sku", f"SKU {sku} already exists.")

    try:
        quantity = number(data.get("quantity") or 0)
        reorder_level = number(data.get("reorder_level") or 0)
        unit_cost = number(data.get("unit_cost") or 0)
        sale_price = number(data.get("sale_price") or 0)
    except NumberError as error:
        return json_error(400, "invalid_number", f"Stock figures {error}.")

    item = InventoryItem(
        sku=sku[:32],
        name=name[:120],
        category=str(data.get("category") or "general")[:48],
        unit=str(data.get("unit") or "unit")[:24],
        quantity=quantity,
        reorder_level=reorder_level,
        unit_cost=unit_cost,
        sale_price=sale_price,
        location=(data.get("location") or None),
    )
    db.session.add(item)
    db.session.flush()
    audit("inventory.item_created", "inventory_item", item.id, after={"sku": item.sku})
    db.session.commit()
    return jsonify({"data": serialize_item(item)}), 201


@bp.post("/items/<int:item_id>/movements")
@require_auth
@require_permission("inventory:movement")
def add_movement(item_id: int):
    item = db.session.get(InventoryItem, item_id)
    if item is None:
        return json_error(404, "item_not_found", "No such inventory item.")

    data = body()
    kind = str(data.get("kind") or "").lower()
    if kind not in (MOVEMENT_IN, MOVEMENT_OUT, MOVEMENT_ADJUST):
        return json_error(400, "invalid_kind", "kind must be in, out or adjust.")

    # Replaying a queued movement must not count the stock twice.
    reference = str(data.get("reference") or "").strip()[:64] or None
    if reference:
        existing = db.session.scalar(
            db.select(StockMovement).where(
                StockMovement.item_id == item.id,
                StockMovement.reference == reference,
            )
        )
        if existing is not None:
            return jsonify(
                {
                    "data": {
                        "item": serialize_item(item),
                        "movement_id": existing.id,
                        "replayed": True,
                    }
                }
            )

    try:
        quantity = number(data.get("quantity") or 0)
    except NumberError as error:
        return json_error(400, "invalid_quantity", f"quantity {error}.")
    if quantity <= 0:
        return json_error(400, "invalid_quantity", "quantity must be greater than zero.")

    reason = str(data.get("reason") or "").strip()[:200] or None
    if kind == MOVEMENT_ADJUST and not reason:
        # A stock take rewrites the shelf; the count and who counted it are the
        # only record of why the number moved, so it must say something.
        return json_error(
            400,
            "reason_required",
            "A stock take needs a reason, for example 'monthly count'.",
        )

    before = float(item.quantity or 0)
    if kind == MOVEMENT_IN:
        item.quantity = round(before + quantity, 2)
        # Restocking with the invoice price keeps the item's cost current; the
        # old stock is folded in at its own cost so the margin stays honest.
        if "unit_cost" in data and data.get("unit_cost") not in (None, ""):
            try:
                paid = number(data.get("unit_cost") or 0)
            except NumberError as error:
                return json_error(400, "invalid_unit_cost", f"unit_cost {error}.")
            old_cost = float(item.unit_cost or 0) * before
            item.unit_cost = round((old_cost + paid * quantity) / (before + quantity), 2)
    elif kind == MOVEMENT_OUT:
        if quantity > before:
            return json_error(409, "insufficient_stock", f"Only {before:g} {item.unit} in stock.")
        item.quantity = round(before - quantity, 2)
    else:  # adjust = absolute set, used for stock counts
        item.quantity = quantity

    movement = StockMovement(
        item_id=item.id,
        kind=kind,
        quantity=quantity,
        reason=reason,
        reference=reference,
        staff_id=g.staff.id,
    )
    db.session.add(movement)

    if float(item.quantity) <= float(item.reorder_level or 0) and before > float(item.reorder_level or 0):
        _low_stock_notification(item)

    audit(
        "inventory.movement",
        "inventory_item",
        item.id,
        before={"quantity": before},
        after={"quantity": float(item.quantity), "kind": kind, "amount": quantity},
    )
    db.session.commit()
    return (
        jsonify(
            {
                "data": {
                    "item": serialize_item(item),
                    "movement_id": movement.id,
                    "quantity_before": before,
                }
            }
        ),
        201,
    )


@bp.get("/items/<int:item_id>/movements")
@require_auth
@require_permission("inventory:read")
def list_movements(item_id: int):
    item = db.session.get(InventoryItem, item_id)
    if item is None:
        return json_error(404, "item_not_found", "No such inventory item.")
    limit, offset = page_args()
    rows = db.session.scalars(
        db.select(StockMovement)
        .where(StockMovement.item_id == item_id)
        .order_by(StockMovement.created_at.desc())
        .limit(limit)
        .offset(offset)
    ).all()
    return jsonify(
        {
            "data": [
                {
                    "id": row.id,
                    "kind": row.kind,
                    "quantity": float(row.quantity),
                    "reason": row.reason,
                    "reference": row.reference,
                    "created_at": iso(row.created_at),
                }
                for row in rows
            ]
        }
    )


@bp.patch("/items/<int:item_id>")
@require_auth
@require_permission("inventory:manage")
def update_item(item_id: int):
    item = db.session.get(InventoryItem, item_id)
    if item is None:
        return json_error(404, "item_not_found", "No such inventory item.")
    data = body()
    before = {
        "name": item.name,
        "reorder_level": float(item.reorder_level or 0),
        "unit_cost": float(item.unit_cost or 0),
        "sale_price": float(item.sale_price or 0),
    }
    for field in ("name", "category", "unit", "location"):
        if field in data:
            value = str(data[field] or "").strip()
            if field in ("name", "unit") and not value:
                return json_error(400, "missing_value", f"{field} cannot be empty.")
            setattr(item, field, value[:120] if field == "name" else value[:80])
    for field in ("reorder_level", "unit_cost", "sale_price"):
        if field in data:
            try:
                setattr(item, field, number(data[field] or 0))
            except NumberError as error:
                return json_error(400, "invalid_number", f"{field} {error}.")
    audit(
        "inventory.item_updated",
        "inventory_item",
        item.id,
        before=before,
        after={
            "name": item.name,
            "reorder_level": float(item.reorder_level or 0),
            "unit_cost": float(item.unit_cost or 0),
            "sale_price": float(item.sale_price or 0),
        },
    )
    db.session.commit()
    return jsonify({"data": serialize_item(item)})
