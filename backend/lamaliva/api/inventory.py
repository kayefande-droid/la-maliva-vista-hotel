"""Inventory: items, stock movements and low-stock notifications."""
from __future__ import annotations

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


def serialize_item(item: InventoryItem) -> dict:
    return {
        "id": item.id,
        "sku": item.sku,
        "name": item.name,
        "category": item.category,
        "unit": item.unit,
        "quantity": float(item.quantity or 0),
        "reorder_level": float(item.reorder_level or 0),
        "unit_cost": money(item.unit_cost),
        "sale_price": money(item.sale_price),
        "location": item.location,
        "low_stock": item.is_low,
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

    item = InventoryItem(
        sku=sku[:32],
        name=name[:120],
        category=str(data.get("category") or "general")[:48],
        unit=str(data.get("unit") or "unit")[:24],
        quantity=data.get("quantity") or 0,
        reorder_level=data.get("reorder_level") or 0,
        unit_cost=data.get("unit_cost") or 0,
        sale_price=data.get("sale_price") or 0,
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
    try:
        quantity = float(data.get("quantity") or 0)
    except (TypeError, ValueError):
        return json_error(400, "invalid_quantity", "quantity must be a number.")
    if quantity <= 0:
        return json_error(400, "invalid_quantity", "quantity must be greater than zero.")

    before = float(item.quantity or 0)
    if kind == MOVEMENT_IN:
        item.quantity = before + quantity
    elif kind == MOVEMENT_OUT:
        if quantity > before:
            return json_error(409, "insufficient_stock", f"Only {before:g} {item.unit} in stock.")
        item.quantity = before - quantity
    else:  # adjust = absolute set, used for stock counts
        item.quantity = quantity

    movement = StockMovement(
        item_id=item.id,
        kind=kind,
        quantity=quantity,
        reason=str(data.get("reason") or "")[:200] or None,
        reference=str(data.get("reference") or "")[:64] or None,
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
        jsonify({"data": {"item": serialize_item(item), "movement_id": movement.id}}),
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
    before = {"name": item.name, "reorder_level": float(item.reorder_level or 0)}
    for field in ("name", "category", "unit", "location"):
        if field in data:
            setattr(item, field, data[field])
    if "reorder_level" in data:
        item.reorder_level = data["reorder_level"]
    if "unit_cost" in data:
        item.unit_cost = data["unit_cost"]
    if "sale_price" in data:
        item.sale_price = data["sale_price"]
    audit(
        "inventory.item_updated",
        "inventory_item",
        item.id,
        before=before,
        after={"name": item.name, "reorder_level": float(item.reorder_level or 0)},
    )
    db.session.commit()
    return jsonify({"data": serialize_item(item)})
