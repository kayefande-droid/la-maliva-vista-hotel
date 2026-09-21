from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, send_file, make_response, session, Response
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime, timedelta, timezone
import os
import io
import csv
import random
import re
import base64
import requests
import secrets
import struct as _struct
from functools import wraps # Import wraps for decorator
from email_utils import validate_email_real  # Real email verification (syntax + DNS + disposable)
from mailer import send_verification_email, smtp_configured
import logging
import time as _time
import hashlib as _hashlib
import hmac as _hmac

# ===================== ASVS L3 CRYPTO CORE =====================
# Argon2id (OWASP PHC winner) with pbkdf2 fallback; deterministic wrappers keep
# every password entry point (signup, login, change, admin-create, API) uniform.
try:
    from argon2 import PasswordHasher as _ArgonHasher
    from argon2.exceptions import VerifyMismatchError as _ArgonMismatch
    _argon = _ArgonHasher(time_cost=3, memory_cost=65536, parallelism=4)  # OWASP L3 params
    _HAS_ARGON = True
except ImportError:  # pragma: no cover
    _HAS_ARGON = False


def hash_password(pw: str) -> str:
    """Argon2id when available, Werkzeug scrypt otherwise. Format is self-identifying."""
    if _HAS_ARGON:
        return _argon.hash(pw)
    return generate_password_hash(pw)


def verify_password(pw_hash: str, pw: str) -> bool:
    """Constant-time verify for either format (defends against DB tampering)."""
    if not pw_hash:
        return False
    try:
        if '$argon2' in pw_hash:
            return _argon.verify(pw_hash, pw) if _HAS_ARGON else False
        return check_password_hash(pw_hash, pw)
    except Exception:
        return False


def needs_rehash(pw_hash: str) -> bool:
    """True when a stored hash should be upgraded to current parameters."""
    if _HAS_ARGON and pw_hash and pw_hash.startswith('$argon2'):
        return _argon.check_needs_rehash(pw_hash)
    return bool(pw_hash) and not pw_hash.startswith('$argon2')  # legacy pbkdf2/scrypt


# ---- NIST 800-63B password policy (ASVS 2.1) ----
_PASSWORD_MIN = 12
_COMMON_FRAGMENTS = ('lamaliva', 'password', '123456', 'qwerty', 'admin123', 'letmein', 'welcome')


def password_policy_error(pw: str) -> str | None:
    """Return an error message when `pw` violates policy, else None."""
    if not pw or len(pw) < _PASSWORD_MIN:
        return f'Password must be at least {_PASSWORD_MIN} characters.'
    if not re.search(r'[A-Z]', pw) or not re.search(r'[a-z]', pw):
        return 'Password needs both upper and lower case letters.'
    if not re.search(r'\d', pw):
        return 'Password needs at least one number.'
    if not re.search(r'[^A-Za-z0-9]', pw):
        return 'Password needs at least one symbol.'
    low = pw.lower()
    if any(f in low for f in _COMMON_FRAGMENTS):
        return 'Password contains a banned common fragment.'
    return None


# ---- TOTP (RFC 6238, SHA-256, 30s step) — admin MFA without extra deps ----
def totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode().rstrip('=')  # 160-bit, base32


def totp_now(secret: str, step: int = 30, digits: int = 8) -> str:
    key = base64.b32decode(secret + '=' * ((8 - len(secret) % 8) % 8), casefold=True)
    counter = int(_time.time()) // step
    msg = _struct.pack('>Q', counter)
    digest = _hmac.new(key, msg, _hashlib.sha256).digest()
    o = digest[-1] & 0x0F
    code = (_struct.unpack('>I', digest[o:o + 4])[0] & 0x7FFFFFFF) % (10 ** digits)
    return str(code).zfill(digits)


def totp_verify(secret: str, code: str, window: int = 1) -> bool:
    """Check code allowing ±window steps of clock drift."""
    if not secret or not code or not code.strip().isdigit():
        return False
    code = code.strip()
    for drift in range(-window, window + 1):
        key = base64.b32decode(secret + '=' * ((8 - len(secret) % 8) % 8), casefold=True)
        counter = int(_time.time()) // 30 + drift
        msg = _struct.pack('>Q', counter)
        digest = _hmac.new(key, msg, _hashlib.sha256).digest()
        o = digest[-1] & 0x0F
        want = str((_struct.unpack('>I', digest[o:o + 4])[0] & 0x7FFFFFFF) % (10 ** 8)).zfill(8)
        if _hmac.compare_digest(want, code):
            return True
    return False


def totp_provisioning_uri(secret: str, account: str) -> str:
    from urllib.parse import quote as _q
    issuer = 'LA-MALIVA+VISTA'
    return (f"otpauth://totp/{issuer}:{_q(account)}?secret={secret}&issuer={issuer}"
            f"&algorithm=SHA256&digits=8&period=30")


# ---- API tokens stored hashed (ASVS 3.5) — plaintext only at issue time ----
def _token_hash(token: str) -> str:
    return _hashlib.sha256(token.encode()).hexdigest()


def new_api_token() -> str:
    return secrets.token_urlsafe(32)

# ReportLab imports
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
from reportlab.lib.units import inch

app = Flask(__name__)
CORS(app)

# Trust Render's proxy so url_for(_external=True) produces the real
# https://la-maliva-vista-hotel.onrender.com host (critical for the
# email-verification links — behind a proxy Flask would otherwise build
# http://127.0.0.1/... links that lead nowhere).
from werkzeug.middleware.proxy_fix import ProxyFix
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)

# --- CONFIGURATION ---
APP_VERSION = "2.3.0"
BUILD_CHANNEL = "stable"

app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'lamaliva_vista_paradise_2026')
# Use absolute path for database to ensure it runs correctly everywhere
basedir = os.path.abspath(os.path.dirname(__file__))
db_path = os.path.join(basedir, 'instance', 'lamaliva.db')
app.config['SQLALCHEMY_DATABASE_URI'] = f'sqlite:///{db_path}'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# MTN Mobile Money Configuration
app.config['MTN_MOMO_SUBSCRIPTION_KEY'] = os.environ.get('MTN_MOMO_SUBSCRIPTION_KEY', '')
app.config['MTN_MOMO_API_USER'] = os.environ.get('MTN_MOMO_API_USER', '')
app.config['MTN_MOMO_API_KEY'] = os.environ.get('MTN_MOMO_API_KEY', '')
app.config['MTN_MOMO_API_URL'] = os.environ.get('MTN_MOMO_API_URL', 'https://sandbox.momodeveloper.mtn.com')
app.config['MTN_MOMO_TARGET_ENV'] = os.environ.get('MTN_MOMO_TARGET_ENV', 'sandbox') # or 'mtncameroon' for live

# NOTE: There is deliberately NO second 'secret pass' field on the public login
# form. Admin and staff sign in with the same single login form as guests —
# their elevated powers come from their account role, not a separate form.
# Default seeded admin: username 'admin' / password 'lamaliva@2026' (changeable
# in-dashboard via Change Password). Admin creates staff accounts in User
# Management (admin-only).

# Ensure instance folder exists
instance_folder = os.path.join(basedir, 'instance')
if not os.path.exists(instance_folder):
    os.makedirs(instance_folder)

db = SQLAlchemy(app)
login_manager = LoginManager(app)
login_manager.login_view = 'login'

# ===================== SECURITY RULES =====================
import sqlite3
from sqlalchemy import event as sa_event
from sqlalchemy.engine import Engine

# ---- 1. Session & request hardening ----
_IS_PROD = os.environ.get('FLASK_ENV') == 'production' or os.environ.get('RENDER') is not None
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,                      # JS cannot read the session cookie
    SESSION_COOKIE_SAMESITE='Lax',                     # blocks most cross-site cookie sends
    SESSION_COOKIE_SECURE=_IS_PROD,                    # HTTPS-only cookies on Render
    PERMANENT_SESSION_LIFETIME=timedelta(hours=12),    # sessions expire after 12h
    MAX_CONTENT_LENGTH=8 * 1024 * 1024,                # 8 MB upload cap (images)
    JSON_SORT_KEYS=False,
)

# ASVS 3.3: idle timeout — staff/admin sessions die after 30 min of inactivity
_IDLE_TIMEOUT = timedelta(minutes=30)


def _validate_image_upload(file_storage) -> str | None:
    """ASVS 5.3.3: accept only real images — magic-byte check + full Pillow
    re-encode (kills polyglot/malformed payloads). Returns an error or None."""
    from PIL import Image as _PILImage
    pos = file_storage.stream.tell()
    header = file_storage.stream.read(16)
    file_storage.stream.seek(pos)
    magic_ok = (
        header.startswith(b'\x89PNG\r\n\x1a\n')
        or header.startswith(b'\xff\xd8\xff')            # JPEG
        or header.startswith((b'RIFF', b'WEBP'))
        or header.startswith((b'GIF87a', b'GIF89a'))
    )
    if not magic_ok:
        return 'File is not a recognised image (PNG/JPEG/WebP/GIF).'
    try:
        img = _PILImage.open(file_storage.stream)
        img.load()
        fmt = (img.format or '').upper()
        if fmt not in ('PNG', 'JPEG', 'WEBP', 'GIF'):
            return f'Unsupported image format: {fmt}.'
        # defence-in-depth: normalise through a clean re-encode
        out = io.BytesIO()
        img.save(out, format='PNG' if fmt == 'GIF' else fmt)
        out.seek(0)
        file_storage.stream = out
        return None
    except Exception:
        return 'Image failed safety validation — re-export and try again.'

# ---- 2. Database rules (SQLite PRAGMAs on every connection) ----
@sa_event.listens_for(Engine, 'connect')
def _set_sqlite_pragmas(dbapi_connection, connection_record):
    """Enforce database integrity rules for every SQLite connection."""
    if isinstance(dbapi_connection, sqlite3.Connection):
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys = ON")       # enforce FK constraints
        cursor.execute("PRAGMA journal_mode = WAL")      # safe concurrent reads/writes
        cursor.execute("PRAGMA busy_timeout = 5000")     # wait instead of 'database is locked'
        cursor.execute("PRAGMA synchronous = NORMAL")    # durable + fast
        cursor.close()


# ---- 3. CSRF protection (form + JSON, auto-injected) ----
def _csrf_token():
    if '_csrf_token' not in session:
        session['_csrf_token'] = secrets.token_hex(32)
    return session['_csrf_token']


app.jinja_env.globals['csrf_token'] = _csrf_token

# Endpoints exempt from CSRF (cookie-less native-app calls and static assets)
_CSRF_EXEMPT_PREFIXES = ('/api/', '/sw.js', '/manifest.json')


@app.before_request
def csrf_protect():
    """Reject state-changing requests without a valid session-bound token."""
    if request.method in ('GET', 'HEAD', 'OPTIONS'):
        return
    if any(request.path.startswith(p) for p in _CSRF_EXEMPT_PREFIXES):
        return
    token = session.get('_csrf_token')
    sent = (
        request.form.get('_csrf_token')
        or request.headers.get('X-CSRF-Token')
        or (request.get_json(silent=True) or {}).get('_csrf_token')
        if request.is_json
        else request.form.get('_csrf_token') or request.headers.get('X-CSRF-Token')
    )
    if not token or not sent or not secrets.compare_digest(token, sent):
        if request.path.startswith('/api/') or request.is_json:
            return jsonify({'ok': False, 'error': 'CSRF token missing or invalid.'}), 400
        flash('⚠️ Security check failed — please retry the form.', 'error')
        return redirect(request.referrer or url_for('public_home'))


@app.after_request
def inject_csrf_forms(response):
    """Auto-add the CSRF hidden input to every HTML <form method="post">.

    Saves editing dozens of templates while guaranteeing every form carries
    the token. Requests the token exists for are unaffected.
    """
    if response.content_type and response.content_type.startswith('text/html') and response.direct_passthrough is False:
        try:
            html = response.get_data(as_text=True)
            token = _csrf_token()
            hidden = f'<input type="hidden" name="_csrf_token" value="{token}">'
            import re as _re
            def _add(m):
                tag = m.group(0)
                return tag + hidden if '_csrf_token' not in tag else tag
            html = _re.sub(r'<form[^>]*method=["\']post["\'][^>]*>', _add, html, flags=_re.I)
            response.set_data(html)
        except Exception:
            pass
    return response


# ---- 4. Rate limiting (brute-force / spam guard) ----
_RATE_BUCKET = {}          # {key: [timestamps]}
_RATE_RULES = {           # endpoint -> (max_hits, window_seconds)
    'login': (10, 300),              # 10 tries / 5 min / IP+identifier
    'api_auth_login': (10, 300),     # same ceiling for the native-app login endpoint
    'signup': (5, 3600),             # 5 signups / hour / IP
    'resend_verification': (3, 600), # 3 emails / 10 min / IP
    'chat': (30, 60),                # 30 msgs / min / IP
    'api_book': (10, 3600),          # 10 bookings / hour / IP
}


def _rate_limit_hit(bucket_key, max_hits, window):
    """Return True when this hit exceeds the allowed rate."""
    import time as _time
    now = _time.time()
    hits = [t for t in _RATE_BUCKET.get(bucket_key, []) if now - t < window]
    hits.append(now)
    _RATE_BUCKET[bucket_key] = hits
    # opportunistic cleanup so the dict cannot grow unbounded
    if len(_RATE_BUCKET) > 5000:
        for k in [k for k, v in _RATE_BUCKET.items() if not v or now - v[-1] > window * 2]:
            _RATE_BUCKET.pop(k, None)
    return len(hits) > max_hits


@app.before_request
def enforce_rate_limits():
    rule = _RATE_RULES.get(request.endpoint)
    if not rule:
        return
    max_hits, window = rule
    ident = ''
    if request.endpoint == 'login':
        ident = (request.form.get('username') or '').strip().lower()
    key = f"{request.endpoint}:{request.remote_addr}:{ident}"
    if _rate_limit_hit(key, max_hits, window):
        _perform_log_later(f"Rate limit hit on {request.endpoint} from {request.remote_addr}")
        if request.path.startswith('/api/') or request.is_json:
            return jsonify({'ok': False, 'error': 'Too many attempts — slow down and try again shortly.'}), 429
        flash('⛔ Too many attempts. Please wait a few minutes and try again.', 'error')
        return redirect(request.referrer or url_for('public_home'))


def _perform_log_later(action):
    """Best-effort security log that never breaks the request."""
    try:
        with app.app_context():
            db.session.add(ActivityLog(action=action))
            db.session.commit()
    except Exception:
        db.session.rollback()


# ---- 5. Role-based access decorator ----
def require_roles(*roles):
    """Route guard: allow only the given roles (admin implicitly allowed via args).

    API callers get JSON 403; browser users get a flash + redirect.
    """
    def decorator(f):
        @wraps(f)
        def wrapped(*args, **kwargs):
            if not current_user.is_authenticated or current_user.role not in roles:
                _perform_log_later(f"DENIED {request.path} for {getattr(current_user, 'username', 'anonymous')} (needs {roles})")
                if request.path.startswith('/api/') or request.is_json:
                    return jsonify({'ok': False, 'error': 'Insufficient permissions.'}), 403
                flash('❌ Access denied. You do not have permission for that area.', 'error')
                return redirect(url_for('dashboard' if current_user.is_authenticated else 'login'))
            return f(*args, **kwargs)
        return wrapped
    return decorator

# ===================== MODELS =====================
class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True)
    email = db.Column(db.String(120), unique=True)
    password_hash = db.Column(db.String(128))
    role = db.Column(db.String(20), default='user') # 'user', 'staff', 'admin'
    registered_on = db.Column(db.DateTime, default=datetime.now(timezone.utc)) # New: Registration timestamp
    can_be_monitored_by_admin = db.Column(db.Boolean, default=False) # New: Permission for screen view
    first_login_done = db.Column(db.Boolean, default=False) # New: Track first login for welcome message

    # ---- Email verification ----
    email_verified = db.Column(db.Boolean, default=False)
    verification_token = db.Column(db.String(128), nullable=True)
    verification_sent_at = db.Column(db.DateTime, nullable=True)

    # ---- Elevated access secret pass (admin/staff second factor) ----
    access_secret_hash = db.Column(db.String(128), nullable=True)

    # ---- Password management ----
    password_changed = db.Column(db.Boolean, default=False)  # True once user changes from default

    # ---- ASVS L3: account lockout + session validity + TOTP MFA ----
    failed_logins = db.Column(db.Integer, default=0, nullable=False)
    locked_until = db.Column(db.DateTime, nullable=True)
    session_valid_after = db.Column(db.DateTime, nullable=True)  # invalidate old sessions on password change
    totp_secret = db.Column(db.String(64), nullable=True)
    totp_pending_secret = db.Column(db.String(64), nullable=True)  # enrollment not yet confirmed

    # ---- Native-app API access ----
    api_token = db.Column(db.String(64), nullable=True, index=True)  # SHA-256 hash of the bearer token
    api_token_issued = db.Column(db.DateTime, nullable=True)

class Room(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    room_number = db.Column(db.String(10), unique=True)
    room_type = db.Column(db.String(50))
    price = db.Column(db.Float)
    status = db.Column(db.String(20), default='Available') # Available, Occupied, Maintenance
    description = db.Column(db.String(255), nullable=True)
    image_url = db.Column(db.String(255), nullable=True) # New: Image URL for the room

class Guest(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100))
    phone = db.Column(db.String(20))
    email = db.Column(db.String(100))

class Reservation(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    guest_id = db.Column(db.Integer, db.ForeignKey('guest.id'), nullable=False)
    # Nullable: offline app registrations sync without a live room pick
    room_id = db.Column(db.Integer, db.ForeignKey('room.id'), nullable=True)
    check_in = db.Column(db.DateTime, nullable=False)
    check_out = db.Column(db.DateTime, nullable=False)
    status = db.Column(db.String(20), default='Confirmed') # Confirmed, Checked-In, Checked-Out, Cancelled
    amount = db.Column(db.Float, nullable=False, default=0.0)
    access_deadline = db.Column(db.DateTime, nullable=True) # New: Deadline for room access
    customer_arrived_paid = db.Column(db.Boolean, default=False) # New: Checkbox for arrival/payment

    __table_args__ = (
        db.Index('ix_reservation_room_in', 'room_id', 'check_in'),
        db.Index('ix_reservation_status', 'status'),
        db.CheckConstraint("check_out > check_in", name='ck_res_dates'),
        db.CheckConstraint("amount >= 0", name='ck_res_amount'),
    )

    # Define relationships
    guest = db.relationship('Guest', backref='reservations')
    room = db.relationship('Room', backref='reservations')

class Hotel(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), default='LA-MALIVA VISTA HOTEL')
    address = db.Column(db.String(200), default='Opposite Fako Heart Entrance, GRA Bokwaongo, Buea, Cameroon')
    tax_rate = db.Column(db.Float, default=0.0)
    # New columns for lock system
    is_locked = db.Column(db.Boolean, default=False)
    lock_message = db.Column(db.Text, default="We are currently undergoing maintenance. Please check back later.")
    # ---- Admin feature toggles (drive PWA + native app sections) ----
    payments_active = db.Column(db.Boolean, default=False)  # MoMo / bank payment sections
    snackbar_active = db.Column(db.Boolean, default=False)  # Snackbar / restaurant menu
    # ---- Google Maps location link (site contact page + native app "Location" option) ----
    maps_url = db.Column(db.String(500), default='https://www.google.com/maps/search/?api=1&query=Fako+Heart+Entrance+GRA+Bokwaongo+Buea+Cameroon')

class SnackbarItem(db.Model):
    """An item on the hotel's snackbar / restaurant menu (admin-managed)."""
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), nullable=False)
    category = db.Column(db.String(50), default='Drinks', index=True)  # Drinks, Beer, Wine, Whisky, Meals, Snacks
    price = db.Column(db.Float, nullable=False)
    image_url = db.Column(db.String(255), nullable=True)
    available = db.Column(db.Boolean, default=True, index=True)
    created_at = db.Column(db.DateTime, default=datetime.now(timezone.utc))

    __table_args__ = (
        db.CheckConstraint("price > 0", name='ck_snack_price'),
    )

class Announcement(db.Model):
    """Admin-posted notice shown to staff on the site (and to the app via API)."""
    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(150), nullable=False)
    body = db.Column(db.Text, nullable=False)
    audience = db.Column(db.String(20), default='staff', nullable=False, index=True)  # staff | everyone
    pinned = db.Column(db.Boolean, default=False, index=True)
    created_by = db.Column(db.Integer, db.ForeignKey('user.id'))
    created_at = db.Column(db.DateTime, default=datetime.now(timezone.utc), index=True)

    author = db.relationship('User', backref='announcements', foreign_keys=[created_by])


class DirectMessage(db.Model):
    """Admin <-> staff direct message with optional file attachment."""
    id = db.Column(db.Integer, primary_key=True)
    sender_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False, index=True)
    recipient_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False, index=True)
    body = db.Column(db.Text, default='')
    attachment_path = db.Column(db.String(255), nullable=True)   # /static/uploads/messages/…
    attachment_name = db.Column(db.String(200), nullable=True)   # original filename
    attachment_size = db.Column(db.Integer, nullable=True)
    read_at = db.Column(db.DateTime, nullable=True, index=True)
    created_at = db.Column(db.DateTime, default=datetime.now(timezone.utc), index=True)

    sender = db.relationship('User', foreign_keys=[sender_id], backref=db.backref('messages_sent', passive_deletes=True))
    recipient = db.relationship('User', foreign_keys=[recipient_id], backref=db.backref('messages_received', passive_deletes=True))


def log_activity(action_description):
    """Decorator for logging route access."""
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            _perform_log(action_description)
            return f(*args, **kwargs)
        return decorated_function
    return decorator


# ===================== ADMIN ANNOUNCEMENTS + ADMIN/STAFF MESSAGING =====================

_MSG_UPLOAD_DIR = os.path.join(basedir, 'static', 'uploads', 'messages')
_ALLOWED_MSG_EXT = {
    '.png', '.jpg', '.jpeg', '.webp', '.gif', '.pdf', '.txt', '.csv', '.doc', '.docx',
    '.xls', '.xlsx', '.zip', '.mp3', '.mp4', '.mov', '.avi', '.mkv',
}
_MSG_MAX_SIZE = 8 * 1024 * 1024  # 8 MB, mirrors MAX_CONTENT_LENGTH


def _save_message_attachment(file):
    """Validate + store a chat attachment. Returns (web_path, orig_name, size, error)."""
    name = (file.filename or '').strip()
    ext = os.path.splitext(name)[1].lower()
    if ext not in _ALLOWED_MSG_EXT:
        return None, None, None, f'File type {ext or "(none)"} is not allowed.'
    data = file.read()
    if len(data) > _MSG_MAX_SIZE:
        return None, None, None, 'File is larger than 8 MB.'
    if ext in ('.png', '.jpg', '.jpeg', '.webp', '.gif'):
        # images must actually be images
        try:
            from PIL import Image as _PILImage
            img = _PILImage.open(io.BytesIO(data))
            img.load()
        except Exception:
            return None, None, None, 'Image failed safety validation.'
    import uuid as _uuid
    fname = f"msg_{_uuid.uuid4().hex[:12]}{ext}"
    os.makedirs(_MSG_UPLOAD_DIR, exist_ok=True)
    with open(os.path.join(_MSG_UPLOAD_DIR, fname), 'wb') as fh:
        fh.write(data)
    return f"/static/uploads/messages/{fname}", name[:200], len(data), None


@app.route('/announcements')
@login_required
@log_activity("Viewed Announcements")
def announcements():
    """Notice board: admin composes; staff (and guests when audience=everyone) read."""
    q = Announcement.query
    if current_user.role != 'admin':
        q = q.filter(Announcement.audience.in_(('staff', 'everyone')))
    posts = q.order_by(Announcement.pinned.desc(), Announcement.created_at.desc()).limit(100).all()
    return render_template('announcements.html', posts=posts)


@app.route('/announcements/post', methods=['POST'])
@login_required
@require_roles('admin')
def announcement_post():
    """Admin publishes a notice to staff or everyone."""
    title = (request.form.get('title') or '').strip()
    body = (request.form.get('body') or '').strip()
    audience = request.form.get('audience', 'staff')
    if audience not in ('staff', 'everyone'):
        audience = 'staff'
    if not title or not body:
        flash('❌ Title and message are required.', 'error')
        return redirect(url_for('announcements'))
    post = Announcement(title=title[:150], body=body, audience=audience,
                        pinned='pinned' in request.form, created_by=current_user.id)
    db.session.add(post)
    db.session.commit()
    _perform_log(f"Posted announcement: {title[:60]}")
    flash('✅ Announcement published.', 'success')
    return redirect(url_for('announcements'))


@app.route('/announcements/<int:post_id>/delete', methods=['POST'])
@login_required
@require_roles('admin')
def announcement_delete(post_id):
    post = Announcement.query.get_or_404(post_id)
    db.session.delete(post)
    db.session.commit()
    _perform_log(f"Deleted announcement #{post_id}")
    flash('🗑️ Announcement removed.', 'info')
    return redirect(url_for('announcements'))


@app.route('/messages')
@login_required
@require_roles('admin', 'staff')
def messages():
    """Admin <-> staff inbox. Admin picks any staff to talk to; staff see admin thread."""
    if current_user.role == 'admin':
        partners = User.query.filter(User.role == 'staff', User.id != current_user.id).order_by(User.username).all()
    else:
        partners = User.query.filter(User.role == 'admin').order_by(User.username).all()

    partner_id = request.args.get('with', type=int)
    partner = None
    if partner_id:
        partner = User.query.get(partner_id)
        allowed = (
            (current_user.role == 'admin' and partner and partner.role == 'staff')
            or (current_user.role == 'staff' and partner and partner.role == 'admin')
        )
        if not allowed:
            partner = None
    if partner is None and partners:
        partner = partners[0]

    thread = []
    if partner:
        thread = DirectMessage.query.filter(
            ((DirectMessage.sender_id == current_user.id) & (DirectMessage.recipient_id == partner.id))
            | ((DirectMessage.sender_id == partner.id) & (DirectMessage.recipient_id == current_user.id))
        ).order_by(DirectMessage.created_at.asc()).limit(300).all()
        # mark partner->me messages read
        unread = [m for m in thread if m.recipient_id == current_user.id and not m.read_at]
        for m in unread:
            m.read_at = datetime.now(timezone.utc)
        if unread:
            db.session.commit()

    unread_counts = {}
    for m in DirectMessage.query.filter(
            DirectMessage.recipient_id == current_user.id, DirectMessage.read_at.is_(None)).all():
        unread_counts[m.sender_id] = unread_counts.get(m.sender_id, 0) + 1

    return render_template('messages.html', partners=partners, partner=partner,
                           thread=thread, unread_counts=unread_counts)


@app.route('/messages/send', methods=['POST'])
@login_required
@require_roles('admin', 'staff')
def messages_send():
    """Send a DM (text and/or attachment) to an admin/staff counterpart."""
    recipient = User.query.get(request.form.get('recipient_id', type=int))
    allowed = recipient and (
        (current_user.role == 'admin' and recipient.role == 'staff')
        or (current_user.role == 'staff' and recipient.role == 'admin')
    )
    if not allowed:
        flash('❌ You can only message ' + ('staff members.' if current_user.role == 'admin' else 'the administrator.'), 'error')
        return redirect(url_for('messages'))

    body = (request.form.get('body') or '').strip()
    file = request.files.get('attachment')
    if not body and (not file or not file.filename):
        flash('❌ Write a message or attach a file.', 'error')
        return redirect(url_for('messages', with_=recipient.id))

    att_path = att_name = att_size = None
    if file and file.filename:
        att_path, att_name, att_size, err = _save_message_attachment(file)
        if err:
            flash(f'❌ {err}', 'error')
            return redirect(url_for('messages', with_=recipient.id))

    msg = DirectMessage(sender_id=current_user.id, recipient_id=recipient.id,
                        body=body[:5000], attachment_path=att_path,
                        attachment_name=att_name, attachment_size=att_size)
    db.session.add(msg)
    db.session.commit()
    _perform_log(f"Message to {recipient.username}" + (f" with attachment {att_name}" if att_name else ""))
    flash('✅ Sent.', 'success')
    return redirect(url_for('messages', with_=recipient.id))


@app.route('/messages/attachment/<int:msg_id>')
@login_required
@require_roles('admin', 'staff')
def messages_attachment(msg_id):
    """Download a chat attachment — only sender or recipient may fetch it."""
    msg = DirectMessage.query.get_or_404(msg_id)
    if current_user.id not in (msg.sender_id, msg.recipient_id):
        flash('❌ Not your conversation.', 'error')
        return redirect(url_for('messages'))
    if not msg.attachment_path:
        flash('❌ No attachment on that message.', 'error')
        return redirect(url_for('messages'))
    full = os.path.join(basedir, msg.attachment_path.lstrip('/').replace('/', os.sep))
    if not os.path.exists(full):
        flash('❌ File no longer exists.', 'error')
        return redirect(url_for('messages'))
    return send_file(full, as_attachment=True, download_name=msg.attachment_name or 'attachment')


# ===================== APP API: ANNOUNCEMENTS + MESSAGES =====================

@app.route('/api/announcements')
def api_announcements():
    """Notice board for the native app (role-aware).

    Guests and anonymous app users receive `everyone` posts (developer-team
    and hotel-wide notices); staff additionally receive `staff` posts; admin
    sees everything.
    """
    user = _current_api_user()
    q = Announcement.query
    if user is None:
        q = q.filter(Announcement.audience == 'everyone')
    elif user.role != 'admin':
        q = q.filter(Announcement.audience.in_(('staff', 'everyone') if user.role == 'staff' else ('everyone',)))
    posts = q.order_by(Announcement.pinned.desc(), Announcement.created_at.desc()).limit(50).all()
    return jsonify({'ok': True, 'announcements': [{
        'id': p.id, 'title': p.title, 'body': p.body, 'audience': p.audience,
        'pinned': p.pinned, 'author': p.author.username if p.author else 'Admin',
        'created_at': p.created_at.isoformat(),
    } for p in posts]})


@app.route('/api/messages', methods=['GET', 'POST'])
def api_messages():
    """Admin<->staff DMs for the native app, including file transfer (multipart)."""
    user = _current_api_user()
    if not user or user.role not in ('admin', 'staff'):
        return jsonify({'ok': False, 'error': 'Staff access only.'}), 403

    if request.method == 'GET':
        if user.role == 'admin':
            partners = User.query.filter(User.role == 'staff').order_by(User.username).all()
        else:
            partners = User.query.filter(User.role == 'admin').order_by(User.username).all()
        partner_id = request.args.get('with', type=int)
        thread = []
        if partner_id:
            thread = DirectMessage.query.filter(
                ((DirectMessage.sender_id == user.id) & (DirectMessage.recipient_id == partner_id))
                | ((DirectMessage.sender_id == partner_id) & (DirectMessage.recipient_id == user.id))
            ).order_by(DirectMessage.created_at.asc()).limit(300).all()
            for m in thread:
                if m.recipient_id == user.id and not m.read_at:
                    m.read_at = datetime.now(timezone.utc)
            db.session.commit()
        return jsonify({'ok': True,
                        'partners': [{'id': p.id, 'username': p.username, 'role': p.role} for p in partners],
                        'messages': [{
                            'id': m.id, 'from': m.sender.username, 'from_id': m.sender_id,
                            'body': m.body, 'attachment': m.attachment_path,
                            'attachment_name': m.attachment_name,
                            'created_at': m.created_at.isoformat(),
                            'mine': m.sender_id == user.id,
                        } for m in thread]})

    # POST — text and/or multipart file
    recipient = User.query.get(request.form.get('recipient_id', type=int)
                               or (request.get_json(silent=True) or {}).get('recipient_id'))
    allowed = recipient and (
        (user.role == 'admin' and recipient.role == 'staff')
        or (user.role == 'staff' and recipient.role == 'admin')
    )
    if not allowed:
        return jsonify({'ok': False, 'error': 'Invalid recipient.'}), 400
    body = (request.form.get('body') or (request.get_json(silent=True) or {}).get('body') or '').strip()
    file = request.files.get('attachment')
    if not body and (not file or not file.filename):
        return jsonify({'ok': False, 'error': 'Empty message.'}), 400
    att_path = att_name = att_size = None
    if file and file.filename:
        att_path, att_name, att_size, err = _save_message_attachment(file)
        if err:
            return jsonify({'ok': False, 'error': err}), 400
    msg = DirectMessage(sender_id=user.id, recipient_id=recipient.id,
                        body=body[:5000], attachment_path=att_path,
                        attachment_name=att_name, attachment_size=att_size)
    db.session.add(msg)
    db.session.commit()
    return jsonify({'ok': True, 'message': {'id': msg.id, 'attachment': att_path}})


class ActivityLog(db.Model): # New ActivityLog Model
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'))
    timestamp = db.Column(db.DateTime, default=datetime.now(timezone.utc), index=True)
    action = db.Column(db.String(255))
    details = db.Column(db.Text, nullable=True)

    user = db.relationship('User', backref=db.backref('activity_logs', lazy=True))

    __table_args__ = (
        db.Index('ix_activity_user_time', 'user_id', 'timestamp'),
    )

# Initialize database and create initial data
def initialize_database():
    """Initialize database tables and create initial data."""
    with app.app_context():
        try:
            db.create_all()
            create_initial_data()
        except Exception as e:
            print(f"Database initialization error: {e}")
            # In a production environment, you might want to re-raise or handle this differently
            raise

# Call database initialization

# Security headers + PWA offline support
@app.after_request
def add_security_headers(response):
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'SAMEORIGIN'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    # ASVS 14.4: cache nothing that carries session data
    if request.path.startswith('/api/') or request.path.startswith('/dashboard'):
        response.headers['Cache-Control'] = 'no-store'
    # ASVS 14.x: modern hardening headers
    if _IS_PROD:
        response.headers.setdefault('Strict-Transport-Security', 'max-age=31536000; includeSubDomains')
    response.headers.setdefault('Referrer-Policy', 'strict-origin-when-cross-origin')
    response.headers.setdefault('Permissions-Policy',
                                'camera=(), microphone=(), geolocation=(self), payment=()')
    response.headers.setdefault('Cross-Origin-Opener-Policy', 'same-origin')
    # Content Security Policy: allows Bootstrap/FontAwesome CDNs and inline
    # scripts used by the templates, but blocks everything else.
    response.headers.setdefault('Content-Security-Policy',
        "default-src 'self'; "
        "script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://cdnjs.cloudflare.com; "
        "style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://cdnjs.cloudflare.com https://fonts.googleapis.com; "
        "font-src 'self' data: https://cdn.jsdelivr.net https://cdnjs.cloudflare.com https://fonts.gstatic.com; "
        "img-src 'self' data: blob: https:; "
        "connect-src 'self'; "
        "frame-src 'self' https://www.google.com https://maps.google.com; "
        "worker-src 'self'; "
        "object-src 'none'; "
        "base-uri 'self'; "
        "form-action 'self'")
    # Service worker needs to own its scope
    if request.path == '/sw.js':
        response.headers['Service-Worker-Allowed'] = '/'
    return response

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))


@app.context_processor
def inject_branding():
    """Expose hotel feature flags to every template (PWA pages + admin tools).

    The native app gets the same flags via /api/features — one switchboard,
    every surface stays in sync.
    """
    try:
        hotel = _get_hotel()
        return dict(
            hotel_name=hotel.name,
            payments_active=bool(hotel.payments_active),
            snackbar_active=bool(hotel.snackbar_active),
            maps_url=hotel.maps_url or 'https://www.google.com/maps/search/?api=1&query=Fako+Heart+Entrance+GRA+Bokwaongo+Buea+Cameroon',
        )
    except Exception:
        return dict(hotel_name='LA-MALIVA VISTA HOTEL', payments_active=False, snackbar_active=False,
                    maps_url='https://www.google.com/maps/search/?api=1&query=Fako+Heart+Entrance+GRA+Bokwaongo+Buea+Cameroon')

# ===================== ACTIVITY LOGGING =====================
def _perform_log(action, details=None):
    """Internal helper to log activity if monitoring is enabled."""
    # Only log if the user is authenticated, is staff, and has monitoring enabled
    if current_user.is_authenticated and current_user.role == 'staff' and current_user.can_be_monitored_by_admin:
        log_entry = ActivityLog(
            user_id=current_user.id,
            action=action,
            details=details or f"Accessed {request.path} with method {request.method}"
        )
        db.session.add(log_entry)
        db.session.commit()


# ===================== LOCK SYSTEM =====================
@app.before_request
def check_site_locked():
    """Check if site is locked and redirect to coming soon page if needed."""
    # Allow access to certain endpoints even when locked
    allowed_endpoints = ['static', 'login', 'logout', 'coming_soon']
    if request.endpoint in allowed_endpoints:
        return

    # If user is admin, allow access regardless of lock
    if current_user.is_authenticated and current_user.role == 'admin':
        return

    # Check if site is locked
    hotel = Hotel.query.first()
    if hotel and hotel.is_locked:
        # Redirect to coming soon page, passing the lock message
        return redirect(url_for('coming_soon'))

@app.route('/coming_soon')
def coming_soon():
    """Display coming soon message when site is locked."""
    hotel = Hotel.query.first()
    lock_message = hotel.lock_message if hotel else "We are currently undergoing maintenance. Please check back later."
    return render_template('coming_soon.html', lock_message=lock_message)

# ===================== CHATBOT LOGIC (AI for Users) =====================
# This is a simple rule-based chatbot. A true AI for user problem-solving
# would require integration with a more advanced NLP/ML service.
INTENTS = {
    "greeting": {
        "patterns": ["hello", "hi", "hey", "good morning", "good evening", "greetings", "bonjour", "salut", "hola"],
        "responses": [
            "Hello! Welcome to La-Maliva Vista Hotel. How can I assist you today?",
            "Hi there! I'm the digital concierge for La-Maliva Vista. Ask me about rooms, prices, or amenities!"
        ]
    },
    "check_in_out": {
        "patterns": ["check in", "check out", "time", "arrival", "departure", "when can i arrive", "what time is checkout"],
        "responses": [
            "Check-in is from 2:00 PM, and check-out is until 12:00 PM. Early check-in may be available upon request."
        ]
    },
    "amenities": {
        "patterns": ["amenities", "pool", "wifi", "internet", "food", "restaurant", "piscine", "comida"],
        "responses": [
            "We offer free high-speed Wi-Fi, 24/7 room service, a beautiful view of Buea, and an on-site restaurant serving local and international dishes."
        ]
    },
    "rooms": {
        "patterns": ["room", "price", "cost", "standard", "deluxe", "suite", "family", "chambre", "prix", "cuanto cuesta"],
        "responses": [
            "Our rooms: Standard (10,000 FCFA), Deluxe (15,000 FCFA), Suite (20,000 FCFA), and Family (25,000 FCFA). All include breakfast."
        ]
    },
    "booking": {
        "patterns": ["book", "booking", "reservation", "how to book", "reserve", "reserver"],
        "responses": [
            "You can book directly by clicking 'New Booking' in the menu or calling us at (+237) 679-915-967."
        ]
    },
    "location": {
        "patterns": ["location", "where", "address", "find you", "ubicacion"],
        "responses": [
            "We are located opposite Fako Heart Entrance, GRA Bokwaongo, Buea, Cameroon."
        ]
    },
    "support": {
        "patterns": ["help", "support", "contact", "issue", "problem"],
        "responses": [
            "For immediate support, please call us at (+237) 679-915-967. Our staff is ready to assist you."
        ]
    },
    "fallback": {
        "patterns": [],
        "responses": [
            "I'm not sure I understand. Could you rephrase? You can ask me about room prices, amenities, or check-in times. For direct assistance, please call (+237) 679-915-967.",
            "I'm your digital assistant. For complex questions or issues, please call reception at (+237) 679-915-967."
        ]
    }
}

def get_intent(message):
    message_lower = message.lower()
    for intent, data in INTENTS.items():
        for pattern in data["patterns"]:
            if re.search(rf"\b{pattern}\b", message_lower):
                return intent
    return "fallback"

@app.route('/chat', methods=['POST'])
def chat():
    data = request.get_json()
    user_message = data.get('message', '')
    if not user_message:
        return jsonify({"response": "Please say something."})
    intent = get_intent(user_message)
    reply = random.choice(INTENTS[intent]["responses"])
    if intent == "rooms":
        available_count = Room.query.filter_by(status='Available').count()
        if available_count > 0:
            reply += f" I've checked our live status: we have {available_count} rooms available right now!"
        else:
            reply += " I'm sorry, we appear to be fully booked at the moment."
    return jsonify({"response": reply})

# ===================== HELPER TO CREATE DATA =====================
def create_initial_data():
    with app.app_context():
        try:
            db.create_all()
            if not User.query.filter_by(username='admin').first():
                # Default administrator: admin / lamaliva@2026 — change it in
                # Change Password after first login.
                admin = User(username='admin', email='admin@lamaliva.com', password_hash=hash_password('lamaliva@2026'), role='admin', registered_on=datetime.now(timezone.utc), can_be_monitored_by_admin=True, first_login_done=True) # Admin's first login is done
                admin.email_verified = True  # seeded accounts skip email verification
                db.session.add(admin)

            # Ensure the default admin always has the official password
            admin_row = User.query.filter_by(username='admin', role='admin').first()
            if admin_row and not verify_password(admin_row.password_hash, 'lamaliva@2026') and not admin_row.password_changed:
                admin_row.password_hash = hash_password('lamaliva@2026')
                admin_row.email_verified = True
                db.session.commit()

            # Seed rooms only when the table is empty (FK constraints now
            # prevent wiping rooms that reservations reference).
            if Room.query.count() == 0:
                rooms_data = [
                # Standard Rooms
                {'number': '101', 'type': 'Standard', 'price': 10000, 'description': 'Basic comfort', 'image_url': '/static/uploads/rooms/room_1566073771259.jpg'},
                {'number': '102', 'type': 'Standard', 'price': 15000, 'description': 'Comfort with a view', 'image_url': '/static/uploads/rooms/room_1542314831.jpg'},
                {'number': '103', 'type': 'Standard', 'price': 15000, 'description': 'Comfort with a view', 'image_url': '/static/uploads/rooms/room_1571003123894.jpg'},
                {'number': '104', 'type': 'Standard', 'price': 10000, 'description': 'Basic comfort', 'image_url': '/static/uploads/rooms/room_1611892440504.jpg'},

                # Deluxe Rooms
                {'number': '201', 'type': 'Deluxe', 'price': 25000, 'description': 'With fridge, couch, and large space', 'image_url': '/static/uploads/rooms/room_1520250497591.jpg'},
                {'number': '202', 'type': 'Deluxe', 'price': 15000, 'description': 'Spacious comfort', 'image_url': '/static/uploads/rooms/room_1566073771259.jpg'},
                {'number': '203', 'type': 'Deluxe', 'price': 20000, 'description': 'With working space', 'image_url': '/static/uploads/rooms/room_1542314831.jpg'},
                {'number': '204', 'type': 'Deluxe', 'price': 20000, 'description': 'With working space', 'image_url': '/static/uploads/rooms/room_1571003123894.jpg'},
                {'number': '205', 'type': 'Deluxe', 'price': 15000, 'description': 'Spacious comfort', 'image_url': '/static/uploads/rooms/room_1611892440504.jpg'},
                {'number': '206', 'type': 'Deluxe', 'price': 15000, 'description': 'Spacious comfort', 'image_url': '/static/uploads/rooms/room_1520250497591.jpg'},
                {'number': '207', 'type': 'Deluxe', 'price': 15000, 'description': 'Spacious comfort', 'image_url': '/static/uploads/rooms/room_1566073771259.jpg'},
                {'number': '208', 'type': 'Deluxe', 'price': 15000, 'description': 'Spacious comfort', 'image_url': '/static/uploads/rooms/room_1542314831.jpg'},
                {'number': '209', 'type': 'Deluxe', 'price': 20000, 'description': 'With fridge and couch', 'image_url': '/static/uploads/rooms/room_1571003123894.jpg'},
                {'number': '210', 'type': 'Deluxe', 'price': 20000, 'description': 'With smart TV', 'image_url': '/static/uploads/rooms/room_1611892440504.jpg'},
                ]

                for r_data in rooms_data:
                    new_room = Room(
                        room_number=r_data['number'],
                        room_type=r_data['type'],
                        price=r_data['price'],
                        status='Available',
                        description=r_data['description'],
                        image_url=r_data['image_url'] # Assign image URL
                    )
                    db.session.add(new_room)
                db.session.commit()

            if not Hotel.query.first():
                hotel = Hotel()
                # Explicitly set lock system fields (though they have defaults)
                hotel.is_locked = False
                hotel.lock_message = "We are currently undergoing maintenance. Please check back later."
                db.session.add(hotel)
            db.session.commit()
        except Exception as e:
            print(f"DB Error: {e}")


def _migrate_schema():
    """Lightweight column migration for existing SQLite databases.

    Adds any columns introduced after initial release that ALTER TABLE
    would be needed for. Safe to run on every startup.
    """
    with app.app_context():
        try:
            result = db.session.execute(
                db.text("PRAGMA table_info(user)")
            ).fetchall()
            existing = {row[1] for row in result}
            migrations = [
                ("email_verified", "BOOLEAN DEFAULT 0"),
                ("verification_token", "VARCHAR(128)"),
                ("verification_sent_at", "DATETIME"),
                ("access_secret_hash", "VARCHAR(128)"),
                ("password_changed", "BOOLEAN DEFAULT 0"),
                ("api_token", "VARCHAR(64)"),
                ("api_token_issued", "DATETIME"),
                # ASVS L3: lockout, session invalidation, TOTP MFA
                ("failed_logins", "INTEGER DEFAULT 0"),
                ("locked_until", "DATETIME"),
                ("session_valid_after", "DATETIME"),
                ("totp_secret", "VARCHAR(64)"),
                ("totp_pending_secret", "VARCHAR(64)"),
            ]
            for column, ddl in migrations:
                if column not in existing:
                    db.session.execute(db.text(f"ALTER TABLE user ADD COLUMN {column} {ddl}"))

            # Hotel table toggles (feature flags for the PWA + native app)
            hotel_cols = {row[1] for row in db.session.execute(db.text("PRAGMA table_info(hotel)")).fetchall()}
            for column, ddl in (("payments_active", "BOOLEAN DEFAULT 0"), ("snackbar_active", "BOOLEAN DEFAULT 0"),
                                ("maps_url", "VARCHAR(500)")):
                if column not in hotel_cols:
                    db.session.execute(db.text(f"ALTER TABLE hotel ADD COLUMN {column} {ddl}"))

            # Snackbar table may not exist on old databases
            db.session.execute(db.text("SELECT 1 FROM snackbar_item LIMIT 1"))
            db.session.commit()
        except Exception:
            db.session.rollback()
            try:
                db.create_all()
                db.session.commit()
            except Exception:
                db.session.rollback()
        try:
            result = db.session.execute(
                db.text("PRAGMA table_info(user)")
            ).fetchall()
            existing = {row[1] for row in result}
            # Trust existing admin accounts created before email verification existed
            db.session.execute(db.text("UPDATE user SET email_verified = 1 WHERE role = 'admin'"))
            # one-time: no email gate anywhere — every existing account signs in freely
            db.session.execute(db.text("UPDATE user SET email_verified = 1 WHERE email_verified = 0"))
            db.session.commit()
        except Exception as e:
            db.session.rollback()
            print(f"Schema migration skipped: {e}")

        # Reservation.room_id was NOT NULL; offline app registrations sync
        # without a live room pick, so relax it via the SQLite 12-step rebuild.
        try:
            res_cols = {row[1]: row for row in db.session.execute(
                db.text("PRAGMA table_info(reservation)")).fetchall()}
            if res_cols and res_cols.get('room_id') is not None and res_cols['room_id'][3] == 1:
                db.session.execute(db.text(
                    "CREATE TABLE reservation_new ("
                    "id INTEGER PRIMARY KEY, guest_id INTEGER NOT NULL, room_id INTEGER, "
                    "check_in DATETIME NOT NULL, check_out DATETIME NOT NULL, "
                    "status VARCHAR(20), amount FLOAT, access_deadline DATETIME, "
                    "customer_arrived_paid BOOLEAN, "
                    "CONSTRAINT ck_res_dates CHECK (check_out > check_in), "
                    "FOREIGN KEY(guest_id) REFERENCES guest (id), "
                    "FOREIGN KEY(room_id) REFERENCES room (id))"))
                db.session.execute(db.text(
                    "INSERT INTO reservation_new SELECT id, guest_id, room_id, check_in, "
                    "check_out, status, amount, access_deadline, customer_arrived_paid "
                    "FROM reservation"))
                db.session.execute(db.text("DROP TABLE reservation"))
                db.session.execute(db.text("ALTER TABLE reservation_new RENAME TO reservation"))
                db.session.execute(db.text("CREATE INDEX IF NOT EXISTS ix_reservation_room_in ON reservation (room_id, check_in)"))
                db.session.execute(db.text("CREATE INDEX IF NOT EXISTS ix_reservation_status ON reservation (status)"))
                db.session.commit()
        except Exception as e:
            db.session.rollback()
            print(f"Reservation rebuild skipped: {e}")


# Call database initialization
_migrate_schema()
initialize_database()

# ===================== ROUTES =====================

@app.route('/')
def public_home():
    all_rooms = Room.query.order_by(Room.price).all() # Renamed to all_rooms
    return render_template('public_home.html', rooms=all_rooms)

@app.route('/verify-email/<token>')
def verify_email(token):
    """Confirm a signup email address via tokenized link."""
    user = User.query.filter_by(verification_token=token).first()
    if not user:
        flash('❌ Invalid or expired verification link. Please sign up again.', 'error')
        return redirect(url_for('signup'))
    user.email_verified = True
    user.verification_token = None
    db.session.commit()
    flash('✅ Email verified! Your account is active — please log in.', 'success')
    return redirect(url_for('login'))


@app.route('/resend-verification', methods=['POST'])
def resend_verification():
    """Re-send the verification email (form posts the email address)."""
    email = (request.form.get('email') or '').strip().lower()
    user = User.query.filter_by(email=email).first()
    # Always claim success to avoid account enumeration
    flash('ℹ️ If that address has a pending account, a new verification link has been sent.', 'info')
    if user and not user.email_verified:
        _issue_verification(user)
    return redirect(url_for('login'))


def _issue_verification(user):
    """Create + email a verification token for the user. Never raises."""
    try:
        user.verification_token = secrets.token_urlsafe(32)
        user.verification_sent_at = datetime.now(timezone.utc)
        db.session.commit()
        link = url_for('verify_email', token=user.verification_token, _external=True)
        # Never let a misconfigured proxy produce a useless localhost link
        if '//' in link:
            host = link.split('//', 1)[1].split('/', 1)[0]
            if host in ('localhost', '127.0.0.1') or host.startswith('0.0.0.0'):
                base = os.environ.get('RENDER_EXTERNAL_URL') or 'https://la-maliva-vista-hotel.onrender.com'
                link = base.rstrip('/') + '/verify-email/' + user.verification_token
        sent = send_verification_email(user.email, link)
        if not sent:
            logger.warning('Verification email for %s could not be sent (SMTP unconfigured/failed). Link: %s', user.email, link)
        return sent
    except Exception:
        logger.exception('Failed to issue verification for %s', user.email)
        return False


@app.route('/signup', methods=['GET', 'POST'])
def signup():
    if request.method == 'POST':
        username = request.form['username']
        email = request.form['email']
        password = request.form['password']

        # Real email address required (syntax + deliverability) — stored in the
        # backend database. No verification email gate: the account works right
        # away so guests can book immediately.
        email_check = validate_email_real(email)
        if not email_check['valid']:
            flash(f'❌ {email_check["reason"]}', 'error')
            return redirect(url_for('signup'))
        email = email_check['email']  # normalized (lowercase, trimmed)

        if User.query.filter((User.username == username) | (User.email == email)).first():
            flash('❌ Username or Email already exists!', 'error')
            return redirect(url_for('signup'))

        # Friendly password rule: 8+ characters (policy kept simple on purpose)
        if not password or len(password) < 8:
            flash('❌ Password must be at least 8 characters.', 'error')
            return redirect(url_for('signup'))

        new_user = User(username=username, email=email, password_hash=hash_password(password), role='user', registered_on=datetime.now(timezone.utc), first_login_done=False) # Set first_login_done to False
        new_user.email_verified = True  # no email gate — real email saved, account active
        db.session.add(new_user)
        db.session.commit()

        flash('✅ Account created! You can sign in now with your username or email.', 'success')
        return redirect(url_for('login'))
    return render_template('signup.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    """Single unified login for guests, staff and admin.

    One form, one password, immediate access. Argon2id hashing and rate
    limiting still protect the endpoint, but there is no lockout, no MFA
    challenge and no email gate — sign-in must "just work" on web and app.
    """
    if request.method == 'POST':
        identifier = request.form['username']
        password = request.form['password']

        user = User.query.filter((User.username == identifier) | (User.email == identifier)).first()

        if user and verify_password(user.password_hash, password):
            # transparent Argon2id upgrade (invisible to the user)
            if needs_rehash(user.password_hash):
                user.password_hash = hash_password(password)
                db.session.commit()

            session.clear()  # rotate session id (fixation defence)
            login_user(user, remember=bool(request.form.get('remember')))
            return _post_login_redirect(user)
        else:
            flash('❌ Invalid username/email or password.', 'error')
    return render_template('login.html')


def _post_login_redirect(user):
    """Shared post-login welcome logic (web)."""
    is_default_admin = (
        user.role == 'admin'
        and not user.password_changed
    )
    if is_default_admin:
        flash('👑 Welcome, Administrator. You are using the default password — please change it now under “Change Password”.', 'warning')
        return redirect(url_for('change_password'))
    if not user.first_login_done:
        flash(f'🎉 Welcome to La-Maliva Vista Hotel, {user.username}! We\'re excited to have you.', 'success')
        user.first_login_done = True
        db.session.commit()
    else:
        flash(f'Welcome back, {user.username}!', 'success')
    return redirect(url_for('dashboard'))


# ===================== MFA (admin, TOTP) =====================
@app.route('/mfa/setup', methods=['GET', 'POST'])
@login_required
def mfa_setup():
    """Enroll the signed-in admin into TOTP MFA (Google Authenticator compatible)."""
    if current_user.role != 'admin':
        flash('MFA enrollment is for administrator accounts.', 'info')
        return redirect(url_for('dashboard'))

    if request.method == 'POST':
        code = request.form.get('code', '').strip()
        secret = current_user.totp_pending_secret
        if secret and totp_verify(secret, code):
            current_user.totp_secret = secret
            current_user.totp_pending_secret = None
            db.session.commit()
            _perform_log(f"MFA enabled for {current_user.username}")
            flash('✅ Two-factor authentication is now ACTIVE on your account.', 'success')
            return redirect(url_for('dashboard'))
        flash('❌ Code did not match — scan the QR again and retry.', 'error')

    # (re)generate a pending secret for enrollment
    if not current_user.totp_pending_secret:
        current_user.totp_pending_secret = totp_secret()
        db.session.commit()
    secret = current_user.totp_pending_secret
    uri = totp_provisioning_uri(secret, current_user.email or current_user.username)
    qr = _qr_svg_data_uri(uri)
    return render_template('mfa_setup.html', secret=secret, qr_uri=qr,
                           mfa_active=bool(current_user.totp_secret))


@app.route('/mfa/disable', methods=['POST'])
@login_required
def mfa_disable():
    """Turning MFA off requires the password + a valid current code."""
    if current_user.role != 'admin':
        return redirect(url_for('dashboard'))
    pw = request.form.get('password', '')
    code = request.form.get('code', '').strip()
    if not verify_password(current_user.password_hash, pw) or not totp_verify(current_user.totp_secret or '', code):
        flash('❌ Password or MFA code incorrect — MFA remains active.', 'error')
        return redirect(url_for('mfa_setup'))
    current_user.totp_secret = None
    current_user.totp_pending_secret = None
    db.session.commit()
    _perform_log(f"MFA disabled for {current_user.username}")
    flash('⚠️ Two-factor authentication disabled. Re-enable it as soon as possible.', 'warning')
    return redirect(url_for('mfa_setup'))


def _qr_svg_data_uri(uri: str) -> str:
    """Render an otpauth URI as a QR (SVG data-URI) with zero third-party calls."""
    try:
        import qrcode
        import qrcode.image.svg
        img = qrcode.make(uri, image_factory=qrcode.image.svg.SvgPathImage,
                          box_size=12, border=2)
        buf = io.BytesIO()
        img.save(buf)
        b64 = base64.b64encode(buf.getvalue()).decode()
        return f'data:image/svg+xml;base64,{b64}'
    except ImportError:
        return ''


@app.route('/change_password', methods=['GET', 'POST'])
@login_required
def change_password():
    """Any signed-in user (guest, staff, admin) can change their own password."""
    if request.method == 'POST':
        current_pw = request.form.get('current_password', '')
        new_pw = request.form.get('new_password', '')
        confirm_pw = request.form.get('confirm_password', '')

        if not verify_password(current_user.password_hash, current_pw):
            flash('❌ Current password is incorrect.', 'error')
        elif not new_pw or len(new_pw) < 8:
            flash('❌ New password must be at least 8 characters.', 'error')
        elif new_pw != confirm_pw:
            flash('❌ New passwords do not match.', 'error')
        elif verify_password(current_user.password_hash, new_pw):
            flash('❌ New password must be different from the current one.', 'error')
        else:
            current_user.password_hash = hash_password(new_pw)
            current_user.password_changed = True
            db.session.commit()
            flash('✅ Password updated successfully.', 'success')
            return redirect(url_for('dashboard'))
    return render_template('change_password.html')

@app.route('/dashboard')
@login_required
@log_activity("Viewed Dashboard") # Log activity
def dashboard():
    today = datetime.now(timezone.utc).date()
    total_rooms = Room.query.count()
    occupied_rooms = Room.query.filter_by(status='Occupied').count()
    free_rooms = total_rooms - occupied_rooms
    occupancy_rate = int((occupied_rooms / total_rooms) * 100) if total_rooms > 0 else 0

    start_of_today = datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc)
    end_of_today = datetime.combine(today, datetime.max.time(), tzinfo=timezone.utc)

    arrivals = Reservation.query.filter(Reservation.check_in >= start_of_today, Reservation.check_in <= end_of_today).all()
    departures = Reservation.query.filter(Reservation.check_out >= start_of_today, Reservation.check_out <= end_of_today).all()

    return render_template('dashboard.html',
                           occupied=occupied_rooms,
                           free=free_rooms,
                           occupancy_rate=occupancy_rate,
                           arrivals=arrivals,
                           departures=departures)

@app.route('/calendar')
@login_required
@log_activity("Viewed Calendar") # Log activity
def calendar(): return render_template('calendar.html')

@app.route('/api/rooms')
@login_required
def api_rooms():
    all_rooms = Room.query.order_by(Room.price).all() # Renamed to all_rooms
    return jsonify([{'id': str(r.id), 'title': f'Room {r.room_number} ({r.room_type})', 'extendedProps': {'status': r.status}} for r in all_rooms])

@app.route('/api/reservations')
@login_required
def api_reservations():
    all_reservations = Reservation.query.all() # Renamed to all_reservations
    events = []
    for r in all_reservations:
        guest_name = r.guest.name if r.guest else 'N/A'
        room_number = r.room.room_number if r.room else 'N/A'
        color = '#28a745' if r.status == 'Checked-In' else '#6c757d' if r.status == 'Checked-Out' else '#007bff'
        events.append({'id': r.id, 'resourceId': str(r.room_id), 'title': f"{guest_name} ({room_number})", 'start': r.check_in.isoformat(), 'end': r.check_out.isoformat(), 'color': color})
    return jsonify(events)

@app.route('/rooms')
@login_required
@log_activity("Viewed Rooms List") # Log activity
def rooms():
    rooms_list = Room.query.order_by(Room.price).all()
    return render_template('rooms.html', rooms=rooms_list)

# ===================== ADMIN: ROOM MANAGEMENT =====================

def _save_room_photo(file):
    """Validate + store an uploaded room photo. Returns (web_path, error)."""
    import uuid as _uuid
    ext = os.path.splitext(file.filename or '')[1].lower()
    if ext not in ('.png', '.jpg', '.jpeg', '.webp'):
        return None, 'Unsupported photo type — use PNG, JPG or WebP.'
    err = _validate_image_upload(file)
    if err:
        return None, err
    fname = f"room_{_uuid.uuid4().hex[:10]}{ext}"
    upload_dir = os.path.join(basedir, 'static', 'uploads', 'rooms')
    os.makedirs(upload_dir, exist_ok=True)
    file.save(os.path.join(upload_dir, fname))
    return f"/static/uploads/rooms/{fname}", None


@app.route('/rooms/manage', methods=['GET', 'POST'])
@login_required
@require_roles('admin')
def rooms_admin():
    """Admin adds rooms, sets price/type/name/description, uploads real photos."""
    if request.method == 'POST':
        action = request.form.get('action', 'add')

        if action == 'delete':
            room = Room.query.get(request.form.get('room_id'))
            if room:
                if Reservation.query.filter_by(room_id=room.id).count() > 0:
                    flash('❌ Cannot delete a room with reservation history — set it to Maintenance instead.', 'error')
                else:
                    db.session.delete(room)
                    db.session.commit()
                    flash(f'🗑️ Room {room.room_number} deleted.', 'info')
            return redirect(url_for('rooms_admin'))

        if action == 'update':
            room = Room.query.get(request.form.get('room_id'))
            if not room:
                flash('❌ Room not found.', 'error')
                return redirect(url_for('rooms_admin'))
            try:
                room.price = float(request.form.get('price') or room.price)
            except ValueError:
                pass
            room.room_type = (request.form.get('room_type') or room.room_type).strip()
            room.description = (request.form.get('description') or '').strip() or room.description
            room.status = request.form.get('status') or room.status
            file = request.files.get('image_file')
            if file and file.filename:
                saved, img_err = _save_room_photo(file)
                if img_err:
                    flash(f'❌ {img_err}', 'error')
                    return redirect(url_for('rooms_admin'))
                if saved:
                    room.image_url = saved
            image_url = (request.form.get('image_url') or '').strip()
            if image_url and not file:
                room.image_url = image_url
            db.session.commit()
            _perform_log(f"Updated room {room.room_number}")
            flash(f'✅ Room {room.room_number} updated.', 'success')
            return redirect(url_for('rooms_admin'))

        # action == add
        number = (request.form.get('room_number') or '').strip()
        room_type = (request.form.get('room_type') or 'Standard').strip()
        try:
            price = float(request.form.get('price') or 0)
        except ValueError:
            price = 0
        description = (request.form.get('description') or '').strip()
        if not number or price <= 0:
            flash('❌ Room number and a positive price are required.', 'error')
            return redirect(url_for('rooms_admin'))
        if Room.query.filter_by(room_number=number).first():
            flash(f'❌ Room {number} already exists.', 'error')
            return redirect(url_for('rooms_admin'))

        image_url = (request.form.get('image_url') or '').strip() or None
        file = request.files.get('image_file')
        if file and file.filename:
            saved, img_err = _save_room_photo(file)
            if img_err:
                flash(f'❌ {img_err}', 'error')
                return redirect(url_for('rooms_admin'))
            if saved:
                image_url = saved
        room = Room(room_number=number, room_type=room_type, price=price,
                    status='Available', description=description, image_url=image_url)
        db.session.add(room)
        db.session.commit()
        _perform_log(f"Added room {number}")
        flash(f'✅ Room {number} added.', 'success')
        return redirect(url_for('rooms_admin'))

    rooms_list = Room.query.order_by(Room.room_number).all()
    return render_template('rooms_admin.html', rooms=rooms_list)

@app.route('/reservations')
@login_required
@log_activity("Viewed Reservations List") # Log activity
def reservations():
    res_list = Reservation.query.all()
    return render_template('reservations.html', reservations=res_list, now=datetime.now(timezone.utc))

@app.route('/guests')
@login_required
@require_roles('admin', 'staff')
@log_activity("Viewed Guests List") # Log activity
def guests():
    guest_list = Guest.query.all()
    return render_template('guests.html', guests=guest_list)

@app.route('/new_reservation', methods=['GET', 'POST'])
@login_required
@log_activity("Attempted New Reservation") # Log activity
def new_reservation():
    selected_room_id = request.args.get('room_id')
    if request.method == 'POST':
        guest = Guest(name=request.form['name'], phone=request.form['phone'], email=request.form['email'])
        db.session.add(guest)
        db.session.commit()
        room = Room.query.get(request.form['room_id'])

        # Parse check-in/out dates and times
        check_in = datetime.strptime(f"{request.form['check_in_date']} {request.form['check_in_time']}", '%Y-%m-%d %H:%M').replace(tzinfo=timezone.utc)
        check_out = datetime.strptime(f"{request.form['check_out_date']} {request.form['check_out_time']}", '%Y-%m-%d %H:%M').replace(tzinfo=timezone.utc)

        # Set access deadline (e.g., 24 hours after check-in)
        access_deadline = check_in + timedelta(hours=24)

        # Basic validation
        if check_out <= check_in:
            flash('❌ Check-out date must be after check-in date.', 'error')
            db.session.rollback() # Rollback guest creation
            return redirect(url_for('new_reservation', room_id=selected_room_id))

        days = max((check_out - check_in).total_seconds() / (24 * 3600), 1)
        amount = room.price * days
        res = Reservation(guest_id=guest.id, room_id=room.id, check_in=check_in, check_out=check_out, amount=amount, status='Confirmed', customer_arrived_paid=False, access_deadline=access_deadline)
        db.session.add(res)

        # If check-in is now or in the past, mark room as occupied
        if check_in <= datetime.now(timezone.utc):
            room.status = 'Occupied'
            res.status = 'Checked-In'

        db.session.commit()
        flash('✅ Reservation created successfully! Please ensure customer arrives by deadline.', 'success')
        _perform_log("Created New Reservation", details=f"Reservation ID: {res.id} for Room {room.room_number if room else 'N/A'}")
        return redirect(url_for('calendar'))
    available_rooms = Room.query.filter_by(status='Available').order_by(Room.price).all()
    return render_template('new_reservation.html', rooms=available_rooms, selected_room_id=selected_room_id)

@app.route('/checkin/<int:res_id>')
@login_required
@require_roles('admin', 'staff')
@log_activity("Attempted Check-in") # Log activity
def checkin(res_id):
    res = Reservation.query.get_or_404(res_id)


    if res.status == 'Checked-In':
        flash('ℹ️ Guest is already checked in.', 'info')
        return redirect(url_for('calendar'))

    # Check if access deadline has passed
    if res.access_deadline and datetime.now(timezone.utc) > res.access_deadline and res.status == 'Confirmed':
        res.status = 'Cancelled' # Automatically cancel if deadline passed and not checked in
        room = Room.query.get(res.room_id)
        if room: # Only if it was marked occupied by this reservation
            room.status = 'Available'
        db.session.commit()
        flash('❌ Reservation automatically cancelled: Access deadline passed.', 'error')
        _perform_log(f"Reservation {res.id} cancelled due to deadline.")
        return redirect(url_for('calendar'))

    res.customer_arrived_paid = True # Mark as arrived and paid
    res.status = 'Checked-In'
    room = Room.query.get(res.room_id)
    if room: # Ensure room exists before updating status
        room.status = 'Occupied'
    db.session.commit()
    flash('✅ Guest checked in and payment confirmed!', 'success')
    _perform_log(f"Checked-in Reservation {res.id}")
    return redirect(url_for('calendar'))

@app.route('/checkout/<int:res_id>')
@login_required
@require_roles('admin', 'staff')
@log_activity("Attempted Check-out") # Log activity
def checkout(res_id):
    res = Reservation.query.get_or_404(res_id)


    if res.status == 'Checked-Out':
        flash('ℹ️ Guest is already checked out.', 'info')
        return redirect(url_for('calendar'))

    res.status = 'Checked-Out'
    room = Room.query.get(res.room_id)
    if room: # Ensure room exists before updating status
        room.status = 'Available'
    db.session.commit()
    flash('✅ Guest checked out!', 'success')
    _perform_log(f"Checked-out Reservation {res.id}")
    return redirect(url_for('calendar'))

@app.route('/invoice/<int:res_id>')
@login_required
@log_activity("Viewed Invoice") # Log activity
def invoice(res_id):
    res = Reservation.query.get_or_404(res_id)
    # guest = Guest.query.get(res.guest_id) # No longer needed, accessed via res.guest
    # room = Room.query.get(res.room_id) # No longer needed, accessed via res.room
    days = max((res.check_out - res.check_in).total_seconds() / (24 * 3600), 1)
    return render_template('invoice.html', res=res, guest=res.guest, room=res.room, days=days, now=datetime.now(timezone.utc))

@app.route('/download_booking_proof/<int:res_id>')
@log_activity("Downloaded Booking Proof") # Log activity
def download_booking_proof(res_id):
    res = Reservation.query.get_or_404(res_id)
    # guest = Guest.query.get(res.guest_id) # No longer needed
    # room = Room.query.get(res.room_id) # No longer needed
    hotel = Hotel.query.first()

    if not res.guest or not res.room or not hotel: # Use res.guest and res.room directly
        flash('❌ Could not generate booking proof due to missing data.', 'error')
        return redirect(url_for('reservations'))

    buffer = io.BytesIO()
    p = canvas.Canvas(buffer, pagesize=letter)
    width, height = letter

    # Header
    p.setFont("Helvetica-Bold", 16)
    p.drawCentredString(width / 2.0, height - 50, f"{hotel.name} - Booking Confirmation")
    p.line(30, height - 60, width - 30, height - 60) # Separator line

    # Reservation Details
    p.setFont("Helvetica", 12)
    textobject = p.beginText(inch, height - 100)
    textobject.textLine(f"Reservation ID: {res.id}")
    textobject.textLine(f"Guest Name: {res.guest.name}")
    textobject.textLine(f"Guest Email: {res.guest.email}")
    textobject.textLine(f"Guest Phone: {res.guest.phone}")
    textobject.textLine("") # Empty line
    textobject.textLine(f"Room Number: {res.room.room_number} ({res.room.room_type})")
    textobject.textLine(f"Check-in: {res.check_in.strftime('%Y-%m-%d %H:%M')}")
    textobject.textLine(f"Check-out: {res.check_out.strftime('%Y-%m-%d %H:%M')}")
    textobject.textLine(f"Total Amount: FCFA {res.amount:,.0f}")
    textobject.textLine(f"Status: {res.status}")
    textobject.textLine("") # Empty line
    textobject.textLine(f"Hotel Address: {hotel.address}")
    textobject.textLine(f"Support Contact: (+237) 679-915-967")
    p.drawText(textobject)

    # Footer
    p.setFont("Helvetica-Oblique", 10)
    p.drawCentredString(width / 2.0, 30, "Thank you for choosing La-Maliva Vista Hotel!")

    p.showPage()
    p.save()

    buffer.seek(0) # Rewind the buffer to the beginning

    response = make_response(buffer.getvalue())
    response.headers.set('Content-Disposition', 'attachment', filename=f'booking_proof_res_{res.id}.pdf')
    response.headers.set('Content-Type', 'application/pdf')

    _perform_log(f"Generated booking proof for Reservation {res.id}")
    return response

@app.route('/logout')
@login_required
@log_activity("Logged Out") # Log activity
def logout():
    logout_user()
    flash('You have been logged out.', 'info')
    return redirect(url_for('login'))

@app.route('/export_data')
@login_required
@require_roles('admin', 'staff')
@log_activity("Exported Data") # Log activity
def export_data():
    all_guests = Guest.query.all() # Renamed to all_guests
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['Name', 'Phone', 'Email'])
    for g in all_guests: writer.writerow([g.name, g.phone, g.email])
    output.seek(0)
    return send_file(io.BytesIO(output.getvalue().encode('utf-8')), mimetype='text/csv', as_attachment=True, download_name='guests.csv')

@app.route('/settings', methods=['GET', 'POST'])
@login_required
@require_roles('admin')
@log_activity("Viewed/Edited Settings") # Log activity
def settings():
    hotel = Hotel.query.first()
    if request.method == 'POST':
        hotel.name = request.form['name']
        hotel.address = request.form['address']
        hotel.tax_rate = float(request.form['tax_rate'])
        # Google Maps location link (drives site contact page + native app Location option)
        maps = (request.form.get('maps_url') or '').strip()
        if maps and not maps.startswith(('http://', 'https://')):
            maps = 'https://' + maps
        hotel.maps_url = maps or hotel.maps_url
        # Handle lock settings
        hotel.is_locked = 'is_locked' in request.form
        hotel.lock_message = request.form.get('lock_message', hotel.lock_message)
        db.session.commit()
        flash('✅ Hotel settings updated successfully!', 'success')
        _perform_log("Updated Hotel Settings")
        return redirect(url_for('settings'))
    return render_template('settings.html', hotel=hotel)

@app.route('/users', methods=['GET', 'POST'])
@login_required
@require_roles('admin')
@log_activity("Viewed/Managed Users") # Log activity
def users():
    if request.method == 'POST':
        action = request.form.get('action')
        if action == 'add':
            username = request.form['username']
            email = request.form['email']
            password = request.form['password']
            role = request.form['role']
            if User.query.filter((User.username == username) | (User.email == email)).first():
                flash(f'❌ User {username} or email already exists!', 'error')
            else:
                if not password or len(password) < 8:
                    flash('❌ Password must be at least 8 characters.', 'error')
                    return redirect(url_for('users'))
                new_user = User(username=username, email=email, password_hash=hash_password(password), role=role, registered_on=datetime.now(timezone.utc), first_login_done=True) # Staff/Admin accounts are not new users
                new_user.email_verified = True  # created internally by admin -> pre-verified
                db.session.add(new_user)
                db.session.commit()
                flash(f'✅ User {username} added successfully!', 'info')
                _perform_log(f"Added User {username} with role {role}")
        elif action == 'delete':
            user_id = request.form.get('user_id')
            user_to_delete = User.query.get(user_id)
            if user_to_delete and user_to_delete.id != current_user.id: # Admin cannot delete themselves
                username = user_to_delete.username
                db.session.delete(user_to_delete)
                db.session.commit()
                flash(f'✅ User {username} deleted.', 'info')
                _perform_log(f"Deleted User {username}")
            else:
                flash('❌ Cannot delete this user (admin cannot delete themselves or user not found).', 'error')
        return redirect(url_for('users'))
    users_list = User.query.all()
    return render_template('users.html', users=users_list)

@app.route('/edit_user/<int:user_id>', methods=['GET', 'POST'])
@login_required
@require_roles('admin')
@log_activity("Viewed/Edited User Profile") # Log activity
def edit_user(user_id):
    user_to_edit = User.query.get_or_404(user_id)
    if request.method == 'POST':
        user_to_edit.username = request.form['username']
        user_to_edit.email = request.form['email']
        if request.form.get('password'):
            user_to_edit.password_hash = generate_password_hash(request.form.get('password'))
        user_to_edit.role = request.form['role']

        # Update can_be_monitored_by_admin only for staff roles
        if user_to_edit.role == 'staff':
            user_to_edit.can_be_monitored_by_admin = 'can_be_monitored_by_admin' in request.form
        else:
            user_to_edit.can_be_monitored_by_admin = False # Non-staff cannot be monitored

        db.session.commit()
        flash(f'✅ User {user_to_edit.username} updated successfully!', 'success')
        _perform_log(f"Updated User {user_to_edit.username}")
        return redirect(url_for('users'))
    return render_template('edit_user.html', user=user_to_edit)

@app.route('/backup')
@login_required
@require_roles('admin')
@log_activity("Performed Database Backup") # Log activity
def backup():
    return send_file(db_path, as_attachment=True, download_name='lamaliva_backup.db')

@app.route('/restore', methods=['GET', 'POST'])
@login_required
@require_roles('admin')
@log_activity("Attempted Database Restore") # Log activity
def restore():
    if request.method == 'POST':
        file = request.files['backup_file']
        if file and file.filename != '':
            try:
                file.save(db_path)
                flash('✅ Database restored successfully! Restart application for changes to take full effect.', 'success')
                _perform_log("Successfully Restored Database")
                return redirect(url_for('dashboard'))
            except Exception as e:
                flash(f'❌ Restore failed: {str(e)}', 'error')
                _perform_log(f"Failed Database Restore: {str(e)}")
    return render_template('restore.html')

@app.route('/stay')
def stay():
    """Public rooms & suites showcase page."""
    rooms_list = Room.query.order_by(Room.price).all()
    return render_template('stay.html', rooms=rooms_list)

@app.route('/contact')
def contact():
    """Public contact page."""
    hotel = Hotel.query.first()
    return render_template('contact.html', hotel=hotel)

@app.route('/about')
def about(): return render_template('about.html')

@app.route('/todays_arrivals')
@login_required
@log_activity("Viewed Today's Arrivals") # Log activity
def todays_arrivals():
    today = datetime.now(timezone.utc).date()
    arrivals = Reservation.query.filter(db.func.date(Reservation.check_in) == today).all()
    return render_template('arrivals.html', arrivals=arrivals, today=today)

@app.route('/todays_departures')
@login_required
@log_activity("Viewed Today's Departures") # Log activity
def todays_departures():
    today = datetime.now(timezone.utc).date()
    departures = Reservation.query.filter(db.func.date(Reservation.check_out) == today).all()

    if request.args.get('json'):
        return jsonify([{
            'id': d.id,
            'guest_name': d.guest.name if d.guest else f"Guest #{d.guest_id}", # Safely access guest name
            'room': d.room.room_number if d.room else 'N/A', # Safely access room number
            'status': d.status
        } for d in departures])

    return render_template('departures.html', departures=departures, today=today)

@app.route('/occupancy_report')
@login_required
@log_activity("Viewed Occupancy Report") # Log activity
def occupancy_report():
    total_rooms = Room.query.count()
    occupied_rooms = Room.query.filter_by(status='Occupied').count()
    free_rooms = total_rooms - occupied_rooms
    occupancy_rate = (occupied_rooms / total_rooms * 100) if total_rooms > 0 else 0
    all_rooms = Room.query.order_by(Room.price).all() # Renamed to all_rooms
    return render_template('occupancy.html', rooms=all_rooms, total=total_rooms, occupied=occupied_rooms, rate=occupancy_rate)

@app.route('/admin_monitoring')
@login_required
@require_roles('admin')
@log_activity("Viewed Admin Monitoring Page") # Log activity
def admin_monitoring():
    users_with_logs = []
    all_users = User.query.all()
    for user in all_users:
        # Only show staff accounts that can be monitored
        if user.role == 'staff' and user.can_be_monitored_by_admin:
            logs = ActivityLog.query.filter_by(user_id=user.id).order_by(ActivityLog.timestamp.desc()).limit(10).all()
            users_with_logs.append({'user': user, 'logs': logs})
        # Do not show logs for 'user' role or staff without monitoring permission
        elif user.role != 'user': # Still list non-monitored staff/admins, but without logs
             users_with_logs.append({'user': user, 'logs': []})

    return render_template('admin_monitoring.html', users_with_logs=users_with_logs)

@app.route('/send_message', methods=['POST'])
@login_required
@require_roles('admin')
@log_activity("Sent Message to User") # Log activity
def send_message():
    user_id = request.form.get('user_id')
    message_content = request.form.get('message_content')

    user = User.query.get(user_id)
    if user and user.role == 'staff': # Only allow sending messages to staff
        # In a real application, you would integrate with a messaging service (e.g., email, SMS, internal notification system)
        # For this example, we'll just flash a message.
        flash(f'✅ Message sent to {user.username}: "{message_content}"', 'success')
        _perform_log(f"Admin sent message to {user.username}", details=message_content)
    else:
        flash('❌ User not found or not a staff member.', 'error')

    return redirect(url_for('admin_monitoring'))

@app.route('/user_manual')
def user_manual():
    return render_template('user_manual.html')

# ===================== ADMIN TOOLS: TOGGLES & SNACKBAR =====================

def _get_hotel():
    hotel = Hotel.query.first()
    if not hotel:
        hotel = Hotel()
        db.session.add(hotel)
        db.session.commit()
    return hotel


@app.route('/admin/toggles', methods=['POST'])
@login_required
@require_roles('admin')
def admin_toggles():
    """Admin switchboard for app-wide feature flags (payments / snackbar).

    These toggles instantly control the payment & snackbar sections in BOTH
    the PWA and the native apps (they poll /api/features).
    """
    hotel = _get_hotel()
    hotel.payments_active = 'payments_active' in request.form
    hotel.snackbar_active = 'snackbar_active' in request.form
    db.session.commit()
    _perform_log(f"Toggled features — payments: {hotel.payments_active}, snackbar: {hotel.snackbar_active}")
    flash('✅ Feature switches updated. Apps pick up the change on next refresh.', 'success')
    return redirect(request.referrer or url_for('dashboard'))


@app.route('/snackbar', methods=['GET', 'POST'])
@login_required
@require_roles('admin', 'staff')
def snackbar_admin():
    """Admin manages snackbar menu items (photo, name, price, category)."""

    if request.method == 'POST':
        action = request.form.get('action', 'add')
        if action == 'delete':
            item = SnackbarItem.query.get(request.form.get('item_id'))
            if item:
                db.session.delete(item)
                db.session.commit()
                flash('🗑️ Menu item removed.', 'info')
            return redirect(url_for('snackbar_admin'))

        name = (request.form.get('name') or '').strip()
        category = (request.form.get('category') or 'Drinks').strip()
        try:
            price = float(request.form.get('price') or 0)
        except ValueError:
            price = 0
        if not name or price <= 0:
            flash('❌ Item name and a positive price are required.', 'error')
            return redirect(url_for('snackbar_admin'))

        image_url = (request.form.get('image_url') or '').strip() or None
        file = request.files.get('image_file')
        if file and file.filename:
            from werkzeug.utils import secure_filename
            import uuid as _uuid
            ext = os.path.splitext(file.filename)[1].lower()
            if ext in ('.png', '.jpg', '.jpeg', '.webp', '.gif'):
                err = _validate_image_upload(file)
                if err:
                    flash(f'❌ {err}', 'error')
                    return redirect(url_for('snackbar_admin'))
                fname = f"snack_{_uuid.uuid4().hex[:10]}{'.png' if ext == '.gif' else secure_filename(ext)}"
                upload_dir = os.path.join(basedir, 'static', 'uploads')
                os.makedirs(upload_dir, exist_ok=True)
                file.save(os.path.join(upload_dir, fname))
                image_url = url_for('static', filename=f'uploads/{fname}')

        item = SnackbarItem(name=name, category=category, price=price, image_url=image_url)
        db.session.add(item)
        db.session.commit()
        _perform_log(f"Added snackbar item {name}")
        flash(f'✅ “{name}” added to the snackbar menu.', 'success')
        return redirect(url_for('snackbar_admin'))

    items = SnackbarItem.query.order_by(SnackbarItem.category, SnackbarItem.name).all()
    hotel = _get_hotel()
    return render_template('snackbar_admin.html', items=items, hotel=hotel)


@app.route('/snackbar/<int:item_id>/toggle', methods=['POST'])
@login_required
@require_roles('admin', 'staff')
def snackbar_toggle_item(item_id):
    if current_user.role not in ('admin', 'staff'):
        flash('❌ Access denied.', 'error')
        return redirect(url_for('dashboard'))
    item = SnackbarItem.query.get_or_404(item_id)
    item.available = not item.available
    db.session.commit()
    return redirect(url_for('snackbar_admin'))


# ===================== PUBLIC APIs FOR NATIVE APP / PWA =====================

@app.route('/api/health')
def api_health():
    """Liveness + database integrity probe for Render health checks."""
    try:
        db.session.execute(db.text('SELECT 1'))
        db_ok = True
    except Exception:
        db.session.rollback()
        db_ok = False
    return jsonify({
        'status': 'healthy' if db_ok else 'degraded',
        'database': 'up' if db_ok else 'down',
        'version': APP_VERSION,
        'time': datetime.now(timezone.utc).isoformat(),
    }), (200 if db_ok else 503)


@app.route('/api/features')
def api_features():
    """Feature flags + hotel info the native app & PWA poll at startup."""
    hotel = _get_hotel()
    return jsonify({
        'hotel': {'name': hotel.name, 'address': hotel.address, 'maps_url': hotel.maps_url or ''},
        'payments_active': bool(hotel.payments_active),
        'snackbar_active': bool(hotel.snackbar_active),
        'site_locked': bool(hotel.is_locked),
        'version': APP_VERSION,
    })

# ===================== SEO: ROBOTS + SITEMAP =====================

SITE_URL = 'https://la-maliva-vista-hotel.onrender.com'


@app.route('/robots.txt')
def robots_txt():
    """Tell crawlers everything is indexable + where the sitemap lives."""
    return Response(
        'User-agent: *\nAllow: /\n\n'
        f'Sitemap: {SITE_URL}/sitemap.xml\n',
        mimetype='text/plain')


@app.route('/sitemap.xml')
def sitemap_xml():
    """Static sitemap of every public page — helps Google index the site
    under its name (LA-MALIVA VISTA HOTEL), not the hosting platform."""
    urls = [
        ('/', '1.0', 'weekly'),
        ('/stay', '0.9', 'daily'),
        ('/rooms', '0.8', 'daily'),
        ('/downloads', '0.7', 'weekly'),
        ('/contact', '0.7', 'monthly'),
        ('/about', '0.6', 'monthly'),
        ('/user_manual', '0.5', 'monthly'),
        ('/login', '0.3', 'monthly'),
        ('/signup', '0.3', 'monthly'),
    ]
    today = datetime.now(timezone.utc).strftime('%Y-%m-%d')
    body = ['<?xml version="1.0" encoding="UTF-8"?>',
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">']
    for path, prio, freq in urls:
        body.append(
            f'  <url><loc>{SITE_URL}{path}</loc>'
            f'<lastmod>{today}</lastmod><changefreq>{freq}</changefreq>'
            f'<priority>{prio}</priority></url>')
    body.append('</urlset>')
    return Response('\n'.join(body), mimetype='application/xml')


# ===================== DOWNLOADS & VERSIONING =====================
APP_RELEASES = {
    'android': {'file': 'la-maliva-vista-{v}.apk', 'label': 'Android APK', 'min_os': 'Android 8.0+', 'size': '~56 MB'},
    'windows': {'file': 'La-Maliva-Vista-{v}-windows.zip', 'label': 'Windows App', 'min_os': 'Windows 10/11 (64-bit)', 'size': '~16 MB'},
    'pwa': {'file': None, 'label': 'Progressive Web App', 'min_os': 'Any modern browser', 'size': '~2 MB'},
}


def _release_meta(platform_key):
    meta = dict(APP_RELEASES[platform_key])
    meta['version'] = APP_VERSION
    meta['channel'] = BUILD_CHANNEL
    meta['filename'] = meta['file'].format(v=APP_VERSION) if meta['file'] else None
    release_path = os.path.join(basedir, 'static', 'releases', meta['filename'] or '')
    meta['available'] = os.path.exists(release_path)
    try:
        meta['size_bytes'] = os.path.getsize(release_path) if meta['available'] else 0
    except OSError:
        meta['size_bytes'] = 0
    return meta


@app.route('/downloads')
def downloads():
    """Native app downloads page (APK / Windows / PWA) with live version info."""
    return render_template(
        'downloads.html',
        app_version=APP_VERSION,
        build_channel=BUILD_CHANNEL,
        releases={k: _release_meta(k) for k in APP_RELEASES},
    )


@app.route('/api/version')
def api_version():
    """Machine-readable version endpoint — download cards bind to this."""
    return jsonify({
        'app': 'LA-MALIVA VISTA',
        'version': APP_VERSION,
        'channel': BUILD_CHANNEL,
        'releases': {k: _release_meta(k) for k in APP_RELEASES},
    })


@app.route('/downloads/<platform>')
def download_release(platform):
    """Serve the requested native bundle from static/releases."""
    platform = platform.lower()
    if platform not in APP_RELEASES or platform == 'pwa':
        flash('Unknown platform requested.', 'error')
        return redirect(url_for('downloads'))
    meta = _release_meta(platform)
    release_path = os.path.join(basedir, 'static', 'releases', meta['filename'])
    if meta['available']:
        return send_file(release_path, as_attachment=True, download_name=meta['filename'])
    flash(f"The {meta['label']} for v{APP_VERSION} is being packaged — check back shortly.", 'info')
    return redirect(url_for('downloads'))


# ===================== EMAIL VALIDATION API =====================
@app.route('/api/public-rooms')
def api_public_rooms():
    """Public room list for the native mobile/desktop apps (offline cache seed)."""
    rooms = Room.query.order_by(Room.price).all()
    return jsonify([{
        'id': r.id,
        'room_number': r.room_number,
        'room_type': r.room_type,
        'price': r.price,
        'description': r.description,
        'image_url': r.image_url,
        'status': r.status,
    } for r in rooms])


@app.route('/api/snackbar')
def api_snackbar():
    """Snackbar menu for the apps — empty unless admin enabled the section."""
    hotel = _get_hotel()
    if not hotel.snackbar_active:
        return jsonify({'active': False, 'items': []})
    items = SnackbarItem.query.filter_by(available=True).order_by(SnackbarItem.category, SnackbarItem.name).all()
    return jsonify({
        'active': True,
        'items': [{
            'id': i.id, 'name': i.name, 'category': i.category,
            'price': i.price, 'image_url': i.image_url,
        } for i in items],
    })


@app.route('/api/book', methods=['POST'])
def api_book():
    """Create a booking straight from the native app / PWA (public)."""
    data = request.get_json(silent=True) or {}
    try:
        name = (data.get('name') or '').strip()
        phone = (data.get('phone') or '').strip()
        email = (data.get('email') or '').strip()
        room_id = int(data.get('room_id') or 0)
        check_in = datetime.strptime(data.get('check_in') or '', '%Y-%m-%d').replace(tzinfo=timezone.utc)
        check_out = datetime.strptime(data.get('check_out') or '', '%Y-%m-%d').replace(tzinfo=timezone.utc)
    except (ValueError, TypeError):
        return jsonify({'ok': False, 'error': 'Invalid booking details.'}), 400

    if not name or not phone:
        return jsonify({'ok': False, 'error': 'Guest name and phone are required.'}), 400
    if check_out <= check_in:
        return jsonify({'ok': False, 'error': 'Check-out must be after check-in.'}), 400

    room = Room.query.get(room_id)
    if not room or room.status != 'Available':
        return jsonify({'ok': False, 'error': 'Room unavailable — please pick another.'}), 409

    days = max((check_out - check_in).total_seconds() / 86400, 1)
    guest = Guest(name=name, phone=phone, email=email)
    db.session.add(guest)
    db.session.commit()
    res = Reservation(
        guest_id=guest.id, room_id=room.id, check_in=check_in, check_out=check_out,
        amount=room.price * days, status='Confirmed',
        access_deadline=check_in + timedelta(hours=24),
    )
    if check_in <= datetime.now(timezone.utc):
        room.status = 'Occupied'
        res.status = 'Checked-In'
    db.session.add(res)
    db.session.commit()
    return jsonify({'ok': True, 'reservation_id': res.id, 'amount': res.amount,
                    'room': room.room_number, 'message': 'Booking confirmed! Present your ID at the front desk.'})


@app.route('/api/register-device', methods=['POST'])
def api_register_device():
    """Record a native-app / PWA install so staff can see app bookings in the log."""
    data = request.get_json(silent=True) or {}
    platform = (data.get('platform') or 'unknown')[:40]
    _perform_log(f"App session from {platform}")
    return jsonify({'ok': True})


@app.route('/api/sync-offline-registrations', methods=['POST'])
def api_sync_offline_registrations():
    """Bulk-upload guest registrations captured by staff while the app was
    offline. Creates real Guests + Reservations in the same database. Does
    not touch room inventory (rooms were registered without a live pick)."""
    data = request.get_json(silent=True) or {}
    regs = data.get('registrations')
    if not isinstance(regs, list) or not regs:
        return jsonify({'ok': False, 'error': 'No registrations supplied.'}), 400
    if len(regs) > 200:
        return jsonify({'ok': False, 'error': 'Too many records (max 200).'}), 400

    created = []
    for reg in regs:
        name = (reg.get('name') or '').strip()
        phone = (reg.get('phone') or '').strip()
        if not name or not phone:
            continue
        email = (reg.get('email') or '').strip()
        try:
            nights = max(int(reg.get('nights') or 1), 1)
        except (TypeError, ValueError):
            nights = 1
        try:
            rate = float(reg.get('rate') or 0)
        except (TypeError, ValueError):
            rate = 0.0
        check_in = datetime.now(timezone.utc)
        check_out = check_in + timedelta(days=nights)
        guest = Guest(name=name, phone=phone, email=email)
        db.session.add(guest)
        db.session.flush()
        res = Reservation(
            guest_id=guest.id, room_id=None, check_in=check_in, check_out=check_out,
            amount=rate * nights, status='Pending',
            access_deadline=check_in + timedelta(hours=24),
        )
        db.session.add(res)
        created.append({'name': name, 'reservation_id': res.id})
    db.session.commit()
    _perform_log(f"Synced {len(created)} offline registration(s) from native app")
    return jsonify({'ok': True, 'synced': len(created), 'records': created})


# ===================== APP API: AUTH (token-based, same database) =====================

# ASVS 3.3: uniform lockout constants for web + API
_LOCK_THRESHOLD = 5
_LOCK_WINDOW = timedelta(minutes=15)


def _register_failed_login(user):
    """Count a failure; lock the account at the threshold for the window."""
    user.failed_logins = (user.failed_logins or 0) + 1
    if user.failed_logins >= _LOCK_THRESHOLD:
        user.locked_until = datetime.now(timezone.utc) + _LOCK_WINDOW
        user.failed_logins = 0
        _perform_log_later(f"ACCOUNT LOCKED: {user.username} after {_LOCK_THRESHOLD} failed logins")
    db.session.commit()


def _reset_failed_logins(user):
    if user.failed_logins or user.locked_until:
        user.failed_logins = 0
        user.locked_until = None
        db.session.commit()


def _lock_message(user) -> str | None:
    if user and user.locked_until:
        locked_at = user.locked_until
        if locked_at.tzinfo is None:
            locked_at = locked_at.replace(tzinfo=timezone.utc)  # SQLite strips tz
        remaining = locked_at - datetime.now(timezone.utc)
        if remaining > timedelta(0):
            mins = int(remaining.total_seconds() // 60) + 1
            return f'Account temporarily locked after repeated failed logins. Try again in ~{mins} min.'
        # lock expired
        user.locked_until = None
        user.failed_logins = 0
        db.session.commit()
    return None


def _issue_api_token(user):
    """Generate and persist a bearer token (raw token returned to the app;
    only its SHA-256 hash is stored in the database)."""
    raw = new_api_token()
    user.api_token = _token_hash(raw)
    user.api_token_issued = datetime.now(timezone.utc)
    db.session.commit()
    return raw


def _current_api_user():
    """Resolve the API caller from their Bearer token (or web session as fallback)."""
    auth = request.headers.get('Authorization', '')
    if auth.startswith('Bearer '):
        token = auth[7:].strip()
        if token:
            return User.query.filter_by(api_token=_token_hash(token)).first()
    if current_user.is_authenticated:
        return current_user
    return None


@app.route('/api/auth/login', methods=['POST'])
def api_auth_login():
    """Native-app login against the SAME user database as the website.

    Simple and reliable: username/email + password → token. No lockout,
    no MFA, no email gate. Argon2id verify + transparent rehash stay.
    """
    data = request.get_json(silent=True) or {}
    identifier = (data.get('username') or data.get('email') or '').strip()
    password = data.get('password') or ''
    if not identifier or not password:
        return jsonify({'ok': False, 'error': 'Username and password are required.'}), 400

    user = User.query.filter((User.username == identifier) | (User.email == identifier)).first()
    if not user or not verify_password(user.password_hash, password):
        return jsonify({'ok': False, 'error': 'Invalid username/email or password.'}), 401

    if needs_rehash(user.password_hash):
        user.password_hash = hash_password(password)

    token = _issue_api_token(user)
    return jsonify({
        'ok': True,
        'token': token,
        'must_change_password': user.role == 'admin' and not user.password_changed,
        'user': {
            'id': user.id, 'username': user.username, 'email': user.email,
            'role': user.role,
        },
    })


@app.route('/api/auth/me')
def api_auth_me():
    user = _current_api_user()
    if not user:
        return jsonify({'ok': False, 'error': 'Not authenticated.'}), 401
    return jsonify({'ok': True, 'user': {
        'id': user.id, 'username': user.username, 'email': user.email, 'role': user.role,
        'must_change_password': user.role == 'admin' and not user.password_changed,
    }})


@app.route('/api/auth/logout', methods=['POST'])
def api_auth_logout():
    user = _current_api_user()
    if user and request.headers.get('Authorization', '').startswith('Bearer '):
        user.api_token = None
        db.session.commit()
    return jsonify({'ok': True})


@app.route('/api/auth/change-password', methods=['POST'])
def api_auth_change_password():
    user = _current_api_user()
    if not user:
        return jsonify({'ok': False, 'error': 'Not authenticated.'}), 401
    data = request.get_json(silent=True) or {}
    current_pw = data.get('current_password', '')
    new_pw = data.get('new_password', '')
    if not verify_password(user.password_hash, current_pw):
        return jsonify({'ok': False, 'error': 'Current password is incorrect.'}), 400
    if not new_pw or len(new_pw) < 8:
        return jsonify({'ok': False, 'error': 'New password must be at least 8 characters.'}), 400
    user.password_hash = hash_password(new_pw)
    user.password_changed = True
    db.session.commit()
    _perform_log_later(f"Password changed via app by {user.username}")
    return jsonify({'ok': True, 'message': 'Password updated.'})


# ===================== APP API: GUEST DATA =====================

@app.route('/api/my-bookings')
def api_my_bookings():
    """Bookings for the token holder, matched by account email."""
    user = _current_api_user()
    if not user:
        return jsonify({'ok': False, 'error': 'Not authenticated.'}), 401
    matches = Guest.query.filter(
        (Guest.email == user.email) | (Guest.email == user.username)
    ).all() if user.email else []
    guest_ids = [g.id for g in matches]
    bookings = Reservation.query.filter(Reservation.guest_id.in_(guest_ids)).order_by(Reservation.check_in.desc()).all() if guest_ids else []
    return jsonify({'ok': True, 'bookings': [{
        'id': r.id, 'room': r.room.room_number if r.room else None,
        'room_type': r.room.room_type if r.room else None,
        'check_in': r.check_in.isoformat(), 'check_out': r.check_out.isoformat(),
        'status': r.status, 'amount': r.amount,
        'guest_name': r.guest.name if r.guest else None,
    } for r in bookings]})


@app.route('/api/booking/<int:res_id>')
def api_booking_detail(res_id):
    """Single booking receipt — owner or staff/admin only."""
    user = _current_api_user()
    if not user:
        return jsonify({'ok': False, 'error': 'Not authenticated.'}), 401
    r = Reservation.query.get(res_id)
    if not r:
        return jsonify({'ok': False, 'error': 'Not found.'}), 404
    owns = r.guest and user.email and (r.guest.email == user.email or r.guest.email == user.username)
    if not owns and user.role not in ('admin', 'staff'):
        return jsonify({'ok': False, 'error': 'Insufficient permissions.'}), 403
    hotel = _get_hotel()
    return jsonify({'ok': True, 'booking': {
        'id': r.id,
        'guest_name': r.guest.name if r.guest else None,
        'guest_email': r.guest.email if r.guest else None,
        'guest_phone': r.guest.phone if r.guest else None,
        'room': r.room.room_number if r.room else None,
        'room_type': r.room.room_type if r.room else None,
        'check_in': r.check_in.isoformat(), 'check_out': r.check_out.isoformat(),
        'status': r.status, 'amount': r.amount,
        'hotel': {'name': hotel.name, 'address': hotel.address, 'phone': '(+237) 679-915-967'},
    }})


# ===================== APP API: STAFF/ADMIN TOOLS =====================

@app.route('/api/staff/overview')
def api_staff_overview():
    """Live ops snapshot for the app's staff/admin dashboard."""
    user = _current_api_user()
    if not user or user.role not in ('admin', 'staff'):
        return jsonify({'ok': False, 'error': 'Staff access only.'}), 403
    total = Room.query.count()
    occupied = Room.query.filter_by(status='Occupied').count()
    today = datetime.now(timezone.utc).date()
    start = datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc)
    end = datetime.combine(today, datetime.max.time(), tzinfo=timezone.utc)
    arrivals = Reservation.query.filter(Reservation.check_in >= start, Reservation.check_in <= end).count()
    departures = Reservation.query.filter(Reservation.check_out >= start, Reservation.check_out <= end).count()
    return jsonify({'ok': True, 'total_rooms': total, 'occupied': occupied,
                    'free': total - occupied, 'arrivals_today': arrivals, 'departures_today': departures})


@app.route('/api/staff/reservations')
def api_staff_reservations():
    user = _current_api_user()
    if not user or user.role not in ('admin', 'staff'):
        return jsonify({'ok': False, 'error': 'Staff access only.'}), 403
    status = request.args.get('status')
    q = Reservation.query.order_by(Reservation.check_in.desc())
    if status:
        q = q.filter_by(status=status)
    recent = q.limit(50).all()
    return jsonify({'ok': True, 'reservations': [{
        'id': r.id,
        'guest_name': r.guest.name if r.guest else '—',
        'guest_phone': r.guest.phone if r.guest else None,
        'room': r.room.room_number if r.room else '—',
        'check_in': r.check_in.isoformat(), 'check_out': r.check_out.isoformat(),
        'status': r.status, 'amount': r.amount,
    } for r in recent]})


@app.route('/api/staff/checkin/<int:res_id>', methods=['POST'])
def api_staff_checkin(res_id):
    user = _current_api_user()
    if not user or user.role not in ('admin', 'staff'):
        return jsonify({'ok': False, 'error': 'Staff access only.'}), 403
    r = Reservation.query.get(res_id)
    if not r:
        return jsonify({'ok': False, 'error': 'Not found.'}), 404
    if r.status != 'Checked-In':
        r.status = 'Checked-In'
        room = Room.query.get(r.room_id)
        if room:
            room.status = 'Occupied'
        db.session.commit()
    return jsonify({'ok': True, 'status': r.status})


@app.route('/api/staff/checkout/<int:res_id>', methods=['POST'])
def api_staff_checkout(res_id):
    user = _current_api_user()
    if not user or user.role not in ('admin', 'staff'):
        return jsonify({'ok': False, 'error': 'Staff access only.'}), 403
    r = Reservation.query.get(res_id)
    if not r:
        return jsonify({'ok': False, 'error': 'Not found.'}), 404
    if r.status != 'Checked-Out':
        r.status = 'Checked-Out'
        room = Room.query.get(r.room_id)
        if room:
            room.status = 'Available'
        db.session.commit()
    return jsonify({'ok': True, 'status': r.status})


# ===================== APP API: ADMIN CONTROLS =====================

@app.route('/api/admin/rooms', methods=['GET', 'POST'])
def api_admin_rooms():
    """Native-app room management: list (staff) / add-edit (admin, multipart photo)."""
    user = _current_api_user()
    if not user or user.role not in ('admin', 'staff'):
        return jsonify({'ok': False, 'error': 'Staff access only.'}), 403
    if request.method == 'GET':
        rooms = Room.query.order_by(Room.room_number).all()
        return jsonify({'ok': True, 'rooms': [{
            'id': r.id, 'room_number': r.room_number, 'room_type': r.room_type,
            'price': r.price, 'description': r.description,
            'image_url': r.image_url, 'status': r.status,
        } for r in rooms]})
    if user.role != 'admin':
        return jsonify({'ok': False, 'error': 'Admin access only.'}), 403
    action = request.form.get('action', 'add')
    if action == 'delete':
        room = Room.query.get(request.form.get('room_id'))
        if not room:
            return jsonify({'ok': False, 'error': 'Room not found.'}), 404
        if Reservation.query.filter_by(room_id=room.id).count() > 0:
            return jsonify({'ok': False, 'error': 'Room has reservation history — set it to Maintenance instead.'}), 409
        db.session.delete(room)
        db.session.commit()
        return jsonify({'ok': True})
    if action == 'update':
        room = Room.query.get(request.form.get('room_id'))
        if not room:
            return jsonify({'ok': False, 'error': 'Room not found.'}), 404
        try:
            room.price = float(request.form.get('price') or room.price)
        except ValueError:
            pass
        room.room_type = (request.form.get('room_type') or room.room_type).strip()
        room.description = (request.form.get('description') or '').strip() or room.description
        room.status = request.form.get('status') or room.status
        file = request.files.get('image')
        if file and file.filename:
            saved, img_err = _save_room_photo(file)
            if img_err:
                return jsonify({'ok': False, 'error': img_err}), 400
            if saved:
                room.image_url = saved
        db.session.commit()
        return jsonify({'ok': True, 'room': {'id': room.id, 'room_number': room.room_number,
                                              'price': room.price, 'image_url': room.image_url}})
    # add
    number = (request.form.get('room_number') or '').strip()
    room_type = (request.form.get('room_type') or 'Standard').strip()
    try:
        price = float(request.form.get('price') or 0)
    except ValueError:
        price = 0
    if not number or price <= 0:
        return jsonify({'ok': False, 'error': 'Room number and positive price required.'}), 400
    if Room.query.filter_by(room_number=number).first():
        return jsonify({'ok': False, 'error': 'Room number already exists.'}), 409
    image_url = (request.form.get('image_url') or '').strip() or None
    file = request.files.get('image')
    if file and file.filename:
        saved, img_err = _save_room_photo(file)
        if img_err:
            return jsonify({'ok': False, 'error': img_err}), 400
        if saved:
            image_url = saved
    room = Room(room_number=number, room_type=room_type, price=price,
                status='Available', description=(request.form.get('description') or '').strip(),
                image_url=image_url)
    db.session.add(room)
    db.session.commit()
    return jsonify({'ok': True, 'room': {'id': room.id, 'room_number': room.room_number,
                                          'price': room.price, 'image_url': room.image_url}})


@app.route('/api/admin/toggles', methods=['POST'])
def api_admin_toggles():
    """Admin flips payments/snackbar switches from the native app."""
    user = _current_api_user()
    if not user or user.role != 'admin':
        return jsonify({'ok': False, 'error': 'Admin access only.'}), 403
    data = request.get_json(silent=True) or {}
    hotel = _get_hotel()
    if 'payments_active' in data:
        hotel.payments_active = bool(data['payments_active'])
    if 'snackbar_active' in data:
        hotel.snackbar_active = bool(data['snackbar_active'])
    db.session.commit()
    _perform_log(f"App toggle by {user.username}: payments={hotel.payments_active} snackbar={hotel.snackbar_active}")
    return jsonify({'ok': True, 'payments_active': hotel.payments_active, 'snackbar_active': hotel.snackbar_active})


@app.route('/api/admin/users', methods=['GET', 'POST'])
def api_admin_users():
    """Admin lists users / creates staff accounts from the native app."""
    user = _current_api_user()
    if not user or user.role != 'admin':
        return jsonify({'ok': False, 'error': 'Admin access only.'}), 403
    if request.method == 'POST':
        data = request.get_json(silent=True) or {}
        username = (data.get('username') or '').strip()
        email = (data.get('email') or '').strip().lower()
        password = data.get('password') or ''
        role = data.get('role') or 'staff'
        if role not in ('staff', 'admin'):
            return jsonify({'ok': False, 'error': 'Role must be staff or admin.'}), 400
        if not username or not email:
            return jsonify({'ok': False, 'error': 'Username and email are required.'}), 400
        if not password or len(password) < 8:
            return jsonify({'ok': False, 'error': 'Password must be at least 8 characters.'}), 400
        if User.query.filter((User.username == username) | (User.email == email)).first():
            return jsonify({'ok': False, 'error': 'Username or email already exists.'}), 409
        nu = User(username=username, email=email, password_hash=hash_password(password),
                  role=role, first_login_done=True)
        nu.email_verified = True
        nu.password_changed = True  # admin sets the password, so no default prompt
        db.session.add(nu)
        db.session.commit()
        return jsonify({'ok': True, 'user': {'id': nu.id, 'username': nu.username, 'role': nu.role}})
    users = User.query.order_by(User.registered_on.desc()).all()
    return jsonify({'ok': True, 'users': [{
        'id': u.id, 'username': u.username, 'email': u.email, 'role': u.role,
        'verified': bool(u.email_verified), 'registered': u.registered_on.isoformat() if u.registered_on else None,
    } for u in users]})


@app.route('/api/snackbar/items', methods=['GET', 'POST'])
def api_snackbar_items():
    """List (public, gated by toggle) and add (staff/admin, multipart photo upload)."""
    if request.method == 'GET':
        return api_snackbar()
    user = _current_api_user()
    if not user or user.role not in ('admin', 'staff'):
        return jsonify({'ok': False, 'error': 'Staff access only.'}), 403
    name = (request.form.get('name') or '').strip()
    category = (request.form.get('category') or 'Drinks').strip()
    try:
        price = float(request.form.get('price') or 0)
    except ValueError:
        price = 0
    if not name or price <= 0:
        return jsonify({'ok': False, 'error': 'Name and positive price required.'}), 400
    image_url = (request.form.get('image_url') or '').strip() or None
    file = request.files.get('image')
    if file and file.filename:
        from werkzeug.utils import secure_filename
        import uuid as _uuid
        ext = os.path.splitext(file.filename)[1].lower()
        if ext in ('.png', '.jpg', '.jpeg', '.webp', '.gif'):
            err = _validate_image_upload(file)
            if err:
                return jsonify({'ok': False, 'error': err}), 400
            fname = f"snack_{_uuid.uuid4().hex[:10]}{'.png' if ext == '.gif' else secure_filename(ext)}"
            upload_dir = os.path.join(basedir, 'static', 'uploads')
            os.makedirs(upload_dir, exist_ok=True)
            file.save(os.path.join(upload_dir, fname))
            image_url = url_for('static', filename=f'uploads/{fname}', _external=True)
    item = SnackbarItem(name=name, category=category, price=price, image_url=image_url)
    db.session.add(item)
    db.session.commit()
    return jsonify({'ok': True, 'item': {'id': item.id, 'name': item.name, 'category': item.category,
                                          'price': item.price, 'image_url': item.image_url}})


@app.route('/api/validate-email', methods=['POST'])
def api_validate_email():
    """Live endpoint powering the signup form's real-time email verification."""
    data = request.get_json(silent=True) or {}
    result = validate_email_real(data.get('email', ''))
    # Never leak existence of accounts; this only checks the ADDRESS itself.
    return jsonify(result)


@app.route('/manifest.json')
def manifest():
    return jsonify({
        'name': 'La-Maliva Vista Hotel',
        'short_name': 'La-Maliva',
        'description': 'Book rooms, order from the snackbar and manage your stay — A Taste of Paradise, Buea.',
        'id': '/',
        'start_url': '/',
        'scope': '/',
        'display': 'standalone',
        'orientation': 'portrait-primary',
        'background_color': '#08123A',
        'theme_color': '#08123A',
        'lang': 'en',
        'categories': ['travel', 'lifestyle'],
        'icons': [
            {'src': '/static/icons/icon-192.png', 'sizes': '192x192', 'type': 'image/png', 'purpose': 'any'},
            {'src': '/static/icons/icon-512.png', 'sizes': '512x512', 'type': 'image/png', 'purpose': 'any'},
            {'src': '/static/icons/icon-192-maskable.png', 'sizes': '192x192', 'type': 'image/png', 'purpose': 'maskable'},
            {'src': '/static/icons/icon-512-maskable.png', 'sizes': '512x512', 'type': 'image/png', 'purpose': 'maskable'},
        ],
        'shortcuts': [
            {'name': 'Rooms & Suites', 'url': '/stay'},
            {'name': 'My Bookings', 'url': '/dashboard'},
            {'name': 'Get the App', 'url': '/downloads'},
        ],
    })

@app.route('/sw.js')
def service_worker():
    return app.send_static_file('sw.js')


@app.route('/offline')
def offline_page():
    """Offline fallback page served by the service worker."""
    response = make_response(render_template('offline.html'))
    response.headers['Cache-Control'] = 'public, max-age=3600'
    return response

# ===================== MTN MOBILE MONEY PAYMENT INTEGRATION =====================
@app.route('/pay/<int:res_id>', methods=['GET'])
@login_required
@log_activity("Accessed Payment Page") # Log activity
def payment_form(res_id):
    """Render the payment form for a specific reservation."""
    reservation = Reservation.query.get_or_404(res_id)
    # Only allow the user who made the reservation or admin/staff to access payment
    if not current_user.is_authenticated or (current_user.id != reservation.guest.id and current_user.role not in ['admin', 'staff']):
        flash('❌ Access denied. You do not have permission to access this payment page.', 'error')
        return redirect(url_for('reservations'))
    # Pre-fill amount from reservation, but allow user to modify? We'll show the amount as default.
    return render_template('payment.html', reservation=reservation)

@app.route('/pay/<int:res_id>', methods=['POST'])
@login_required
@log_activity("Processed Payment") # Log activity
def process_payment(res_id):
    """Process MTN Mobile Money payment for a reservation."""
    reservation = Reservation.query.get_or_404(res_id)
    # Only allow the user who made the reservation or admin/staff to process payment
    if not current_user.is_authenticated or (current_user.id != reservation.guest.id and current_user.role not in ['admin', 'staff']):
        flash('❌ Access denied. You do not have permission to process this payment.', 'error')
        return redirect(url_for('reservations'))

    phone_number = request.form.get('phone_number')
    amount_str = request.form.get('amount')

    # Validate input
    if not phone_number or not amount_str:
        flash('❌ Phone number and amount are required.', 'error')
        return redirect(url_for('payment_form', res_id=res_id))

    try:
        amount = float(amount_str)
        if amount <= 0:
            raise ValueError
    except ValueError:
        flash('❌ Amount must be a positive number.', 'error')
        return redirect(url_for('payment_form', res_id=res_id))

    # Check if amount matches reservation amount (optional, can be overridden)
    # if amount != reservation.amount:
    #     flash('❌ Amount does not match the reservation amount.', 'error')
    #     return redirect(url_for('payment_form', res_id=res_id))

    # Prepare MTN MoMo API credentials
    subscription_key = app.config['MTN_MOMO_SUBSCRIPTION_KEY']
    api_user = app.config['MTN_MOMO_API_USER']
    api_key = app.config['MTN_MOMO_API_KEY']
    base_url = app.config['MTN_MOMO_API_URL']
    target_env = app.config['MTN_MOMO_TARGET_ENV']

    if not all([subscription_key, api_user, api_key]):
        flash('❌ MTN Mobile Money credentials are not configured properly.', 'error')
        return redirect(url_for('payment_form', res_id=res_id))

    try:
        # Step 1: Get access token
        token_url = f"{base_url}/collection/token/"
        headers = {
            'Ocp-Apim-Subscription-Key': subscription_key,
            'Authorization': 'Basic ' + base64.b64encode(f"{api_user}:{api_key}".encode()).decode(),
            'Content-Type': 'application/json'
        }
        token_response = requests.post(token_url, headers=headers, json={})
        token_response.raise_for_status() # Raise exception for bad status codes
        access_token = token_response.json()['access_token']

        # Step 2: Initiate payment request
        payment_url = f"{base_url}/collection/v1_0/requesttopay"
        headers = {
            'Authorization': f'Bearer {access_token}',
            'X-Callback-Url': 'https://example.com/callback', # Placeholder - implement callback handling if needed
            'X-Target-Environment': target_env,
            'Content-Type': 'application/json',
            'Ocp-Apim-Subscription-Key': subscription_key
        }
        payload = {
            'amount': str(amount),
            'currency': 'EUR', # Consider making currency configurable or based on hotel location (XAF for Cameroon?)
            'externalId': str(reservation.id),
            'payer': {
                'partyIdType': 'MSISDN',
                'partyId': phone_number
            },
            'payerMessage': 'Payment for hotel reservation',
            'payeeNote': 'Thank you for your business'
        }
        payment_response = requests.post(payment_url, headers=headers, json=payload)
        payment_response.raise_for_status()

        # If we get here, the request was accepted (HTTP 202)
        # Note: Mobile money payments are asynchronous. We assume success for now.
        # In a real implementation, you would check the transaction status via the transaction ID.
        flash('✅ Payment has been initiated. Please complete the payment on your mobile money account.', 'success')
        # Log the payment attempt
        _perform_log(f"Initiated MoMo payment for Reservation {reservation.id}", details=f"Amount: {amount}, Phone: {phone_number}")
        return redirect(url_for('reservations'))

    except requests.exceptions.RequestException as e:
        error_msg = f'❌ Payment initiation failed: {str(e)}'
        if hasattr(e, 'response') and e.response is not None:
            try:
                error_detail = e.response.json()
                error_msg += f' - Details: {error_detail}'
            except:
                error_msg += f' - Response: {e.response.text}'
        flash(error_msg, 'error')
        _perform_log(f"MoMo payment failed for Reservation {reservation.id}", details=str(e))
        return redirect(url_for('payment_form', res_id=res_id))
    except Exception as e:
        flash(f'❌ An unexpected error occurred: {str(e)}', 'error')
        _perform_log(f"Unexpected error in payment processing for Reservation {reservation.id}", details=str(e))
        return redirect(url_for('payment_form', res_id=res_id))

# ===================== ERROR HANDLERS (clean boundaries) =====================
@app.errorhandler(404)
def not_found_error(error):
    if request.path.startswith('/api/'):
        return jsonify({'error': 'Not found'}), 404
    try:
        return render_template('errors/404.html'), 404
    except Exception:
        return '404 — Page not found', 404


@app.errorhandler(500)
def internal_error(error):
    try:
        db.session.rollback()
    except Exception:
        pass
    if request.path.startswith('/api/'):
        return jsonify({'error': 'Internal server error'}), 500
    try:
        return render_template('errors/500.html'), 500
    except Exception:
        return '500 — Internal Server Error', 500


@app.errorhandler(Exception)
def unhandled_exception(error):
    from werkzeug.exceptions import HTTPException
    if isinstance(error, HTTPException):
        return error
    try:
        db.session.rollback()
    except Exception:
        pass
    if request.path.startswith('/api/'):
        return jsonify({'error': 'Internal server error'}), 500
    try:
        return render_template('errors/500.html'), 500
    except Exception:
        return '500 — Internal Server Error', 500


if __name__ == '__main__':
    app.run(debug=False)