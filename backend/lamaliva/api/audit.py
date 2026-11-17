"""Audit log, notifications and hotel settings."""
from __future__ import annotations

from flask import Blueprint, g, jsonify, request

from ..extensions import db
from ..models import AuditLog, HotelSetting, Notification, utcnow
from ..security import audit, json_error, require_auth, require_permission
from ._util import body, iso, money, page_args, paginated

bp = Blueprint("audit", __name__)


@bp.get("")
@require_auth
@require_permission("audit:read")
def list_audit():
    limit, offset = page_args()
    query = db.select(AuditLog)

    entity = (request.args.get("entity") or "").strip()
    if entity:
        query = query.where(AuditLog.entity == entity)
    action = (request.args.get("action") or "").strip()
    if action:
        query = query.where(AuditLog.action == action)
    actor = request.args.get("actor_id")
    if actor:
        query = query.where(AuditLog.actor_id == int(actor))

    total = db.session.scalar(db.select(db.func.count()).select_from(query.subquery())) or 0
    rows = db.session.scalars(
        query.order_by(AuditLog.created_at.desc(), AuditLog.id.desc()).limit(limit).offset(offset)
    ).all()
    return paginated(
        [
            {
                "id": row.id,
                "actor_id": row.actor_id,
                "actor_name": row.actor_name,
                "action": row.action,
                "entity": row.entity,
                "entity_id": row.entity_id,
                "before": row.before,
                "after": row.after,
                "meta": row.meta,
                "ip": row.ip,
                "created_at": iso(row.created_at),
            }
            for row in rows
        ],
        total,
        limit,
        offset,
    )
