"""The shop till: food, drinks and sundries sold from the store room.

Recording a sale moves stock out and banks the money in one step, so the
shelf and the till always reconcile. Anyone who may move stock
(`inventory:movement`) may work the till; the money totals also roll up into
the financial revenue report for management.
"""
from __future__ import annotations

from datetime import date, timedelta

from flask import Blueprint, g, jsonify, request

from ..extensions import db
from ..models import InventoryItem, ShopSale, StockMovement, utcnow
from ..security import audit, json_error, require_auth, require_permission
from ._util import body, iso, money, page_args, paginated
from .inventory import _low_stock_notification

bp = Blueprint("shop", __name__)


def serialize_sale(sale: ShopSale) -> dict:
    return {
        "id": sale.id,
        "item_id": sale.item_id,
        "item_name": sale.item_name,
        "quantity": float(sale.quantity or 0),
        "unit_price": money(sale.unit_price),
        "total": money(sale.total),
        "currency": sale.currency,
        "method": sale.method,
        "reference": sale.reference,
        "created_at": iso(sale.created_at),
    }


@bp.post("/sales")
@require_auth
@require_permission("inventory:movement")
def record_sale():
    data = body()
    item = db.session.get(InventoryItem, data.get("item_id"))
    if item is None or not item.active:
        return json_error(404, "item_not_found", "No such stock item.")

    try:
        quantity = float(data.get("quantity") or 0)
    except (TypeError, ValueError):
        return json_error(400, "invalid_quantity", "quantity must be a number.")
    if quantity <= 0:
        return json_error(400, "invalid_quantity", "quantity must be greater than zero.")

    try:
        unit_price = float(
            data.get("unit_price")
            if data.get("unit_price") not in (None, "")
            else (item.sale_price or 0)
        )
    except (TypeError, ValueError):
        return json_error(400, "invalid_price", "unit_price must be a number.")
    if unit_price <= 0:
        return json_error(
            400,
            "missing_price",
            f"Set a selling price for {item.name} first; "
            "an administrator can add one on the stock item.",
        )

    if quantity > float(item.quantity or 0):
        return json_error(
            409,
            "insufficient_stock",
            f"Only {float(item.quantity or 0):g} {item.unit} of {item.name} on the shelf.",
        )

    reference = (str(data.get("reference") or "").strip() or None)
    if reference:
        # An offline till replays its queue; the server banks it once.
        existing = db.session.scalar(
            db.select(ShopSale).where(ShopSale.reference == reference)
        )
        if existing is not None:
            return jsonify({"data": serialize_sale(existing)})

    method = str(data.get("method") or "cash")[:24]
    total = round(quantity * unit_price, 2)
    before = float(item.quantity or 0)
    item.quantity = before - quantity

    sale = ShopSale(
        item_id=item.id,
        item_name=item.name,
        quantity=quantity,
        unit_price=unit_price,
        total=total,
        currency="XAF",
        method=method,
        reference=reference,
        staff_id=g.staff.id,
    )
    db.session.add(sale)
    db.session.flush()
    db.session.add(
        StockMovement(
            item_id=item.id,
            kind="out",
            quantity=quantity,
            reason="sale",
            reference=reference or f"SALE-{sale.id}",
            staff_id=g.staff.id,
        )
    )

    if float(item.quantity) <= float(item.reorder_level or 0) < before:
        _low_stock_notification(item)

    audit(
        "shop.sale_recorded",
        "shop_sale",
        sale.id,
        after={
            "item": item.name,
            "quantity": quantity,
            "unit_price": unit_price,
            "total": total,
            "method": method,
        },
    )
    db.session.commit()
    return jsonify({"data": serialize_sale(sale)}), 201


@bp.get("/sales")
@require_auth
@require_permission("inventory:movement")
def list_sales():
    today = date.today()
    try:
        since = date.fromisoformat(request.args.get("from") or today.isoformat())
        until = date.fromisoformat(request.args.get("to") or today.isoformat())
    except ValueError:
        return json_error(400, "invalid_range", "from/to must be ISO dates.")

    start = utcnow().replace(year=since.year, month=since.month, day=since.day,
                             hour=0, minute=0, second=0, microsecond=0)
    end = utcnow().replace(year=until.year, month=until.month, day=until.day,
                           hour=0, minute=0, second=0, microsecond=0) + timedelta(days=1)

    base = db.select(ShopSale).where(
        ShopSale.created_at >= start, ShopSale.created_at < end
    )
    revenue = db.session.scalar(
        db.select(db.func.coalesce(db.func.sum(ShopSale.total), 0))
        .select_from(base.subquery())
    )
    count = db.session.scalar(
        db.select(db.func.count()).select_from(base.subquery())
    ) or 0

    limit, offset = page_args()
    rows = db.session.scalars(
        base.order_by(ShopSale.created_at.desc()).limit(limit).offset(offset)
    ).all()
    payload = jsonify(
        {
            "data": [serialize_sale(row) for row in rows],
            "meta": {
                "total": count,
                "limit": limit,
                "offset": offset,
                "has_more": offset + len(rows) < count,
            },
            "totals": {
                "currency": "XAF",
                "sales": count,
                "revenue": money(revenue),
                "range": {"from": since.isoformat(), "to": until.isoformat()},
            },
        }
    )
    return payload
