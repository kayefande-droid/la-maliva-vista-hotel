"""Small shared helpers for the API routers."""
from __future__ import annotations

from flask import jsonify, request


def page_args(default_limit: int = 25, max_limit: int = 200) -> tuple[int, int]:
    try:
        limit = int(request.args.get("limit", default_limit))
    except (TypeError, ValueError):
        limit = default_limit
    try:
        offset = int(request.args.get("offset", 0))
    except (TypeError, ValueError):
        offset = 0
    return max(1, min(limit, max_limit)), max(0, offset)


def paginated(items: list, total: int, limit: int, offset: int):
    return jsonify(
        {
            "data": items,
            "meta": {
                "total": total,
                "limit": limit,
                "offset": offset,
                "has_more": offset + len(items) < total,
            },
        }
    )


def body() -> dict:
    data = request.get_json(silent=True)
    return data if isinstance(data, dict) else {}


def iso(value) -> str | None:
    if value is None:
        return None
    return value.isoformat() + ("Z" if not value.isoformat().endswith("Z") else "")


def money(value) -> float:
    return float(value or 0)
