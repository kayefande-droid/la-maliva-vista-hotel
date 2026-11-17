"""WSGI entry point: `flask --app wsgi run` or `waitress-serve wsgi:app`."""
from __future__ import annotations

import os

from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))

from lamaliva import create_app  # noqa: E402

app = create_app()

if __name__ == "__main__":
    # The debug reloader restarts the whole worker on any file change and leaves
    # stray children behind; this API is meant to stay up for the staff apps, so
    # it is off unless someone asks for it explicitly.
    reloader = os.environ.get("LAMALIVA_RELOADER", "").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }
    app.run(
        host=os.environ.get("LAMALIVA_HOST", "127.0.0.1"),
        port=int(os.environ.get("LAMALIVA_PORT", "8000")),
        use_reloader=reloader,
    )
