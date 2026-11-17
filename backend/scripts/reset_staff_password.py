"""Reset a staff or administrator password from the server console.

Use when the account's password is unknown - for example the migrated
administrator, whose hash came from the legacy system.

The new password is generated unless one is given, printed exactly once, and
never stored in plaintext. Resetting a password also invalidates that account's
existing sessions by moving tokens_valid_from forward, and marks the account as
must-change-password so the next sign-in forces a new one.

Dry run by default: it reports what it would do and writes nothing. Pass --apply
to actually change the password.

Examples
    python scripts/reset_staff_password.py --username admin
    python scripts/reset_staff_password.py --username admin --apply
    python scripts/reset_staff_password.py --list
"""
from __future__ import annotations

import argparse
import secrets
import sys
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import inspect

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from lamaliva import create_app  # noqa: E402
from lamaliva.extensions import db  # noqa: E402
from lamaliva.models import Staff  # noqa: E402
from lamaliva.security import hash_password  # noqa: E402


def has_staff_table() -> bool:
    return inspect(db.engine).has_table("staff")


def list_accounts(app) -> int:
    with app.app_context():
        if not has_staff_table():
            print("The staff table does not exist yet. Run the data migration first:")
            print("    python scripts\\migrate_from_sqlite.py --source ..\\instance\\lamaliva.db --apply --create-schema")
            return 1
        rows = db.session.scalars(db.select(Staff).order_by(Staff.username)).all()
        if not rows:
            print("No staff accounts exist yet.")
            return 0
        print(f"{'username':<20} {'role':<8} {'status':<10} must_change")
        for staff in rows:
            print(
                f"{staff.username:<20} {staff.role:<8} {staff.status:<10} "
                f"{'yes' if staff.must_change_password else 'no'}"
            )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--username", help="Account to reset")
    parser.add_argument("--password", help="New password (generated when omitted)")
    parser.add_argument(
        "--apply", action="store_true", help="Write the change (default: dry run)"
    )
    parser.add_argument("--list", action="store_true", help="List accounts and exit")
    args = parser.parse_args(argv)

    app = create_app()

    if args.list:
        return list_accounts(app)
    if not args.username:
        parser.error("--username is required unless --list is used")

    generated = args.password is None
    password = args.password or secrets.token_urlsafe(18)

    with app.app_context():
        if not has_staff_table():
            print("The staff table does not exist yet. Run the data migration first:")
            print("    python scripts\\migrate_from_sqlite.py --source ..\\instance\\lamaliva.db --apply --create-schema")
            return 1
        staff = db.session.scalar(db.select(Staff).where(Staff.username == args.username))
        if staff is None:
            print(f"No account named '{args.username}'. Use --list to see accounts.")
            return 1

        print(f"Account:  {staff.username} <{staff.email}> role={staff.role} status={staff.status}")
        if not args.apply:
            print("\nDry run: nothing written. Re-run with --apply to reset the password.")
            return 0

        if len(password) < 12:
            print("Refusing: passwords must be at least 12 characters.")
            return 2

        staff.password_hash = hash_password(password)
        staff.must_change_password = True
        staff.password_changed_at = None
        staff.tokens_valid_from = datetime.now(timezone.utc).replace(tzinfo=None)
        db.session.commit()

        print("\nPassword reset. Existing sessions are now invalid.")
        print("The account must choose a new password at the next sign-in.")
        if generated:
            print("One-time password (shown once, not stored anywhere):")
            print("    " + password)
        else:
            print("Password taken from --password (not echoed).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
