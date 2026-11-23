"""The till and the money report: what the hotel actually earned.

The rules pinned here: a sale leaves the shelf once, a replayed offline sale
never double-banks, a sale without a selling price is refused rather than
guessed, and the daily figure is real received cash, not a projection.
"""
from __future__ import annotations

from datetime import date, timedelta

from lamaliva.api.reports import hotel_today
from lamaliva.extensions import db
from lamaliva.models import InventoryItem, ShopSale, StockMovement


def _item(app, quantity=20, sale_price=1500) -> int:
    with app.app_context():
        item = InventoryItem(
            sku="DRK-001",
            name="Malta",
            category="drinks",
            unit="bottle",
            quantity=quantity,
            reorder_level=5,
            unit_cost=900,
            sale_price=sale_price,
        )
        db.session.add(item)
        db.session.commit()
        return item.id


def test_a_sale_takes_stock_and_banks_the_money(app, client, auth):
    headers, _ = auth()
    item_id = _item(app)

    response = client.post(
        "/api/v1/shop/sales",
        headers=headers,
        json={"item_id": item_id, "quantity": 3, "method": "cash"},
    )
    assert response.status_code == 201, response.get_json()
    sale = response.get_json()["data"]
    assert sale["total"] == 4500
    assert sale["unit_price"] == 1500

    with app.app_context():
        item = db.session.get(InventoryItem, item_id)
        assert float(item.quantity) == 17
        movement = db.session.scalar(
            db.select(StockMovement).where(StockMovement.item_id == item_id)
        )
        assert movement is not None and movement.kind == "out"


def test_a_replayed_offline_sale_is_banked_once(app, client, auth):
    headers, _ = auth()
    item_id = _item(app)
    body = {
        "item_id": item_id,
        "quantity": 2,
        "reference": "OFFLINE-SALE-1",
    }

    first = client.post("/api/v1/shop/sales", headers=headers, json=body)
    second = client.post("/api/v1/shop/sales", headers=headers, json=body)
    assert first.status_code == 201
    assert second.status_code == 200
    assert first.get_json()["data"]["id"] == second.get_json()["data"]["id"]

    with app.app_context():
        assert db.session.scalar(
            db.select(db.func.count()).select_from(ShopSale)
        ) == 1
        item = db.session.get(InventoryItem, item_id)
        assert float(item.quantity) == 18


def test_a_sale_without_a_price_is_refused(app, client, auth):
    headers, _ = auth()
    item_id = _item(app, sale_price=0)

    response = client.post(
        "/api/v1/shop/sales",
        headers=headers,
        json={"item_id": item_id, "quantity": 1},
    )
    assert response.status_code == 400
    assert response.get_json()["type"].endswith("missing_price")


def test_a_sale_beyond_the_shelf_is_refused(app, client, auth):
    headers, _ = auth()
    item_id = _item(app, quantity=2)

    response = client.post(
        "/api/v1/shop/sales",
        headers=headers,
        json={"item_id": item_id, "quantity": 5},
    )
    assert response.status_code == 409
    assert response.get_json()["type"].endswith("insufficient_stock")


def test_a_receptionist_cannot_read_the_financial_report(app, client, auth):
    from lamaliva.models import ROLE_RECEPTION, STATUS_ACTIVE, Staff
    from lamaliva.security import hash_password

    with app.app_context():
        db.session.add(
            Staff(
                username="desk",
                email="desk2@lamaliva.local",
                full_name="Front Desk",
                password_hash=hash_password("DeskPass!2026"),
                role=ROLE_RECEPTION,
                status=STATUS_ACTIVE,
                must_change_password=False,
            )
        )
        db.session.commit()

    desk_headers, _ = auth(
        username="desk", password="DeskPass!2026", fingerprint="desk-till"
    )
    response = client.get("/api/v1/reports/money", headers=desk_headers)
    assert response.status_code == 403


def test_the_money_report_counts_till_and_rooms_by_day_week_and_month(
    app, client, auth
):
    headers, _ = auth()
    item_id = _item(app)
    client.post(
        "/api/v1/shop/sales",
        headers=headers,
        json={"item_id": item_id, "quantity": 4},
    )

    # The report follows the hotel's clock, not the machine running the test.
    today = hotel_today()
    since = (today - timedelta(days=9)).isoformat()
    response = client.get(
        f"/api/v1/reports/money?from={since}&to={today.isoformat()}",
        headers=headers,
    )
    assert response.status_code == 200, response.get_json()
    data = response.get_json()["data"]

    assert data["today"]["date"] == today.isoformat()
    assert data["today"]["shop"] == 6000
    assert data["today"]["rooms"] == 0
    assert data["today"]["total"] == 6000
    assert len(data["daily"]) == 10
    assert len(data["weekly"]) >= 1
    assert len(data["monthly"]) >= 1
    assert data["this_month"]["shop"] >= 6000


def test_a_stock_take_needs_a_reason_and_sets_the_shelf(app, client, auth):
    headers, _ = auth()
    item_id = _item(app, quantity=20)

    refused = client.post(
        f"/api/v1/inventory/items/{item_id}/movements",
        headers=headers,
        json={"kind": "adjust", "quantity": 17},
    )
    assert refused.status_code == 400
    assert refused.get_json()["type"].endswith("reason_required")

    counted = client.post(
        f"/api/v1/inventory/items/{item_id}/movements",
        headers=headers,
        json={"kind": "adjust", "quantity": 17, "reason": "monthly count"},
    )
    assert counted.status_code == 201, counted.get_json()
    assert counted.get_json()["data"]["item"]["quantity"] == 17


def test_restock_with_an_invoice_price_updates_the_weighted_cost(app, client, auth):
    headers, _ = auth()
    item_id = _item(app, quantity=10)

    response = client.post(
        f"/api/v1/inventory/items/{item_id}/movements",
        headers=headers,
        json={"kind": "in", "quantity": 10, "unit_cost": 1100, "reason": "delivery"},
    )
    assert response.status_code == 201, response.get_json()
    item = response.get_json()["data"]["item"]
    assert item["quantity"] == 20
    # Ten bottles at 900 plus ten at 1,100 average to 1,000.
    assert item["unit_cost"] == 1000
    assert item["stock_value"] == 20000


def test_a_sale_refuses_an_unknown_payment_method(app, client, auth):
    headers, _ = auth()
    item_id = _item(app)

    response = client.post(
        "/api/v1/shop/sales",
        headers=headers,
        json={"item_id": item_id, "quantity": 1, "method": "bitcoin"},
    )
    assert response.status_code == 400
    assert response.get_json()["type"].endswith("invalid_method")


def test_the_money_report_shows_the_drawer_by_method(app, client, auth):
    headers, _ = auth()
    item_id = _item(app)
    client.post(
        "/api/v1/shop/sales",
        headers=headers,
        json={"item_id": item_id, "quantity": 2, "method": "cash"},
    )
    client.post(
        "/api/v1/shop/sales",
        headers=headers,
        json={"item_id": item_id, "quantity": 1, "method": "momo"},
    )

    today = hotel_today()
    response = client.get(
        f"/api/v1/reports/money?from={today.isoformat()}&to={today.isoformat()}",
        headers=headers,
    )
    assert response.status_code == 200, response.get_json()
    by_method = response.get_json()["data"]["today"]["by_method"]
    assert by_method["cash"]["total"] == 3000
    assert by_method["momo"]["shop"] == 1500
