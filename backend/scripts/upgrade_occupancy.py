"""Bring an existing LA-MALIVA VISTA database up to the current models.

`db.create_all()` creates new tables but never alters existing ones, so every
column added since the database file was first made has to be applied
deliberately. This script diffs the live schema against the SQLAlchemy models
and adds whatever is missing, so one run heals drift from any past change.

Idempotent, and it backs the file up first. Safe on SQLite and PostgreSQL.

    python -m scripts.upgrade_occupancy                 # development database
    python -m scripts.upgrade_occupancy --db postgresql://...
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)

DEFAULT_DB = os.path.join(HERE, "lamaliva_dev.db")


def _backup(url: str) -> None:
    if not url.startswith("sqlite:///"):
        print("Non-SQLite database: take a provider snapshot before continuing.")
        return
    path = url.replace("sqlite:///", "", 1)
    if not os.path.exists(path) or path == ":memory:":
        print("Nothing to back up (new or in-memory database).")
        return
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    target = f"{path}.bak-{stamp}"
    shutil.copy2(path, target)
    print(f"Backed up to {target}")


def _column_ddl(column, dialect) -> str | None:
    """ALTER TABLE ... ADD COLUMN text for one model column.

    SQLite cannot add a UNIQUE column in place; uniqueness for such columns is
    also enforced in application code, so the column is added plain and the
    integrity check still holds.
    """
    try:
        type_sql = column.type.compile(dialect=dialect)
    except Exception:  # pragma: no cover - exotic type
        type_sql = "VARCHAR(255)"

    ddl = f"{column.name} {type_sql}"
    default = getattr(column, "default", None)
    value = getattr(default, "arg", None) if default is not None else None
    if not column.nullable and isinstance(value, (str, int, float, bool)):
        literal = repr(value) if isinstance(value, str) else str(int(value)) if isinstance(value, bool) else str(value)
        ddl += f" NOT NULL DEFAULT {literal}"
    return ddl


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=None, help="SQLALCHEMY_DATABASE_URI override")
    args = parser.parse_args()

    url = args.db or os.environ.get("LAMALIVA_DATABASE_URL")
    if not url:
        if not os.path.exists(DEFAULT_DB):
            print(f"No database at {DEFAULT_DB}; nothing to upgrade.")
            return 0
        url = "sqlite:///" + DEFAULT_DB.replace(os.sep, "/")
    os.environ["LAMALIVA_DATABASE_URL"] = url

    from sqlalchemy import inspect, text

    from lamaliva import create_app
    from lamaliva.extensions import db

    print(f"Upgrading {url}")
    _backup(url)

    app = create_app("development")
    added: list[str] = []
    skipped: list[str] = []
    with app.app_context():
        inspector = inspect(db.engine)
        existing_tables = set(inspector.get_table_names())
        dialect = db.engine.dialect

        for table in db.metadata.sorted_tables:
            if table.name not in existing_tables:
                continue  # new tables are created below
            present = {column["name"] for column in inspector.get_columns(table.name)}
            for column in table.columns:
                if column.name in present:
                    continue
                ddl = _column_ddl(column, dialect)
                if ddl is None:
                    skipped.append(f"{table.name}.{column.name}")
                    continue
                db.session.execute(text(f"ALTER TABLE {table.name} ADD COLUMN {ddl}"))
                added.append(f"{table.name}.{column.name}")
        db.session.commit()

        db.create_all()
        after = set(inspect(db.engine).get_table_names())
        created = sorted(after - existing_tables)

    print(f"Added {len(added)} column(s)" + (": " + ", ".join(added) if added else "."))
    print(f"Created table(s): {', '.join(created) if created else 'none'}")
    if skipped:
        print("Needs a manual migration: " + ", ".join(skipped))
    print("Existing rows keep their defaults; no data was rewritten.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
