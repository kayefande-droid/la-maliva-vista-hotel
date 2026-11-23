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
