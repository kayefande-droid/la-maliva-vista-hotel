from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, send_file, make_response
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
from functools import wraps

# ReportLab imports (optional; may require package in requirements)
try:
    from reportlab.lib.pagesizes import letter
    from reportlab.pdfgen import canvas
    from reportlab.lib.units import inch
except Exception:
    # ReportLab may not be installed in some environments; PDF features will be disabled if missing
    letter = None
    canvas = None
    inch = None

app = Flask(__name__)
CORS(app)

# --- CONFIGURATION ---
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'lamaliva_vista_paradise_2026')
basedir = os.path.abspath(os.path.dirname(__file__))
db_path = os.path.join(basedir, 'instance', 'lamaliva.db')
app.config['SQLALCHEMY_DATABASE_URI'] = f'sqlite:///{db_path}'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# Ensure instance folder exists
instance_folder = os.path.join(basedir, 'instance')
if not os.path.exists(instance_folder):
    os.makedirs(instance_folder)

db = SQLAlchemy(app)
login_manager = LoginManager(app)
login_manager.login_view = 'login'

# ===================== MODELS =====================
class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True)
    email = db.Column(db.String(120), unique=True)
    password_hash = db.Column(db.String(128))
    role = db.Column(db.String(20), default='user')
    registered_on = db.Column(db.DateTime, default=datetime.now(timezone.utc))
    can_be_monitored_by_admin = db.Column(db.Boolean, default=False)

class Room(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    room_number = db.Column(db.String(10), unique=True)
    room_type = db.Column(db.String(50))
    price = db.Column(db.Float)
    status = db.Column(db.String(20), default='Available')
    description = db.Column(db.String(255), nullable=True)
    image_url = db.Column(db.String(255), nullable=True)

class Guest(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100))
    phone = db.Column(db.String(20))
    email = db.Column(db.String(100))

class Reservation(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    guest_id = db.Column(db.Integer, db.ForeignKey('guest.id'))
    room_id = db.Column(db.Integer, db.ForeignKey('room.id'))
    check_in = db.Column(db.DateTime)
    check_out = db.Column(db.DateTime)
    status = db.Column(db.String(20), default='Confirmed')
    amount = db.Column(db.Float)
    access_deadline = db.Column(db.DateTime, nullable=True)
    customer_arrived_paid = db.Column(db.Boolean, default=False)

class Hotel(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), default='LA-MALIVA VISTA HOTEL')
    address = db.Column(db.String(200), default='Opposite Fako Heart Entrance, GRA Bokwaongo, Buea, Cameroon')
    tax_rate = db.Column(db.Float, default=0.0)

class ActivityLog(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'))
    timestamp = db.Column(db.DateTime, default=datetime.now(timezone.utc))
    action = db.Column(db.String(255))
    details = db.Column(db.Text, nullable=True)

    user = db.relationship('User', backref=db.backref('activity_logs', lazy=True))

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))

# ===================== ACTIVITY LOGGING =====================
def _perform_log(action, details=None):
    try:
        if current_user.is_authenticated and current_user.role == 'staff' and current_user.can_be_monitored_by_admin:
            log_entry = ActivityLog(
                user_id=current_user.id,
                action=action,
                details=details or f"Accessed {request.path} with method {request.method}"
            )
            db.session.add(log_entry)
            db.session.commit()
    except Exception:
        # Don't let logging break the app
        pass

def log_activity(action_description):
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            _perform_log(action_description)
            return f(*args, **kwargs)
        return decorated_function
    return decorator

# ===================== SIMPLE CHATBOT =====================
INTENTS = {
    "greeting": {
        "patterns": ["hello", "hi", "hey"],
        "responses": ["Hello! Welcome to La-Maliva Vista Hotel. How can I assist you today?"]
    },
    "fallback": {
        "patterns": [],
        "responses": ["I'm not sure I understand. Could you rephrase?"]
    }
}

def get_intent(message):
    message_lower = (message or '').lower()
    for intent, data in INTENTS.items():
        for pattern in data.get('patterns', []):
            if re.search(rf"\b{re.escape(pattern)}\b", message_lower):
                return intent
    return 'fallback'

@app.route('/chat', methods=['POST'])
def chat():
    data = request.get_json() or {}
    user_message = data.get('message', '')
    if not user_message:
        return jsonify({"response": "Please say something."})
    intent = get_intent(user_message)
    reply = random.choice(INTENTS.get(intent, INTENTS['fallback'])['responses'])
    return jsonify({"response": reply})

# ===================== HELPERS =====================
def create_initial_data():
    with app.app_context():
        try:
            db.create_all()
            if not User.query.filter_by(username='admin').first():
                admin = User(username='admin', email='admin@lamaliva.com', password_hash=generate_password_hash('admin123'), role='admin', registered_on=datetime.now(timezone.utc), can_be_monitored_by_admin=False)
                db.session.add(admin)

            # Minimal set of rooms if none exist
            if Room.query.count() == 0:
                sample_rooms = [
                    {'number': '101', 'type': 'Standard', 'price': 10000, 'description': 'Basic comfort', 'image_url': ''},
                    {'number': '201', 'type': 'Deluxe', 'price': 15000, 'description': 'Spacious comfort', 'image_url': ''}
                ]
                for r in sample_rooms:
                    new_room = Room(room_number=r['number'], room_type=r['type'], price=r['price'], status='Available', description=r['description'], image_url=r['image_url'])
                    db.session.add(new_room)

            if not Hotel.query.first():
                db.session.add(Hotel())
            db.session.commit()
        except Exception as e:
            print(f"DB Error: {e}")

# ===================== ROUTES =====================
@app.route('/')
def public_home():
    # Guard database/template errors so the homepage returns a friendly page instead of 500
    try:
        all_rooms = Room.query.order_by(Room.price).all()
    except Exception as e:
        print(f"public_home DB/Rendering error: {e}")
        all_rooms = []
    try:
        return render_template('public_home.html', rooms=all_rooms)
    except Exception as e:
        # If rendering fails, return a minimal fallback HTML to avoid Internal Server Error
        print(f"public_home template render error: {e}")
        return "<html><body><h1>LA-MALIVA VISTA HOTEL</h1><p>Sorry, the site is temporarily unavailable.</p></body></html>", 200

@app.route('/signup', methods=['GET', 'POST'])
def signup():
    if request.method == 'POST':
        username = request.form.get('username')
        email = request.form.get('email')
        password = request.form.get('password')
        if not email or not email.endswith('@gmail.com'):
            flash('❌ Only genuine Gmail accounts (@gmail.com) are allowed for user registration!', 'error')
            return redirect(url_for('signup'))
        if User.query.filter((User.username == username) | (User.email == email)).first():
            flash('❌ Username or Email already exists!', 'error')
            return redirect(url_for('signup'))
        new_user = User(username=username, email=email, password_hash=generate_password_hash(password), role='user', registered_on=datetime.now(timezone.utc))
        db.session.add(new_user)
        db.session.commit()
        flash('✅ Account created successfully! Please login.', 'success')
        return redirect(url_for('login'))
    return render_template('signup.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        identifier = request.form.get('username')
        password = request.form.get('password')
        user = User.query.filter((User.username == identifier) | (User.email == identifier)).first()
        if user and check_password_hash(user.password_hash, password):
            login_user(user)
            flash(f'Welcome, {user.username}!', 'success')
            return redirect(url_for('dashboard'))
        else:
            flash('❌ Invalid username/email or password.', 'error')
    return render_template('login.html')

@app.route('/dashboard')
@login_required
@log_activity('Viewed Dashboard')
def dashboard():
    today = datetime.now(timezone.utc).date()
    total_rooms = Room.query.count()
    occupied_rooms = Room.query.filter_by(status='Occupied').count()
    free_rooms = total_rooms - occupied_rooms
    occupancy_rate = int((occupied_rooms / total_rooms) * 100) if total_rooms > 0 else 0
    arrivals = Reservation.query.filter(Reservation.check_in >= datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc), Reservation.check_in <= datetime.combine(today, datetime.max.time(), tzinfo=timezone.utc)).all()
    departures = Reservation.query.filter(Reservation.check_out >= datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc), Reservation.check_out <= datetime.combine(today, datetime.max.time(), tzinfo=timezone.utc)).all()
    return render_template('dashboard.html', occupied=occupied_rooms, free=free_rooms, occupancy_rate=occupancy_rate, arrivals=arrivals, departures=departures)

@app.route('/manifest.json')
def manifest():
    return jsonify({"name": "LaMalaVista", "short_name": "LaMalaVista", "start_url": "/dashboard", "display": "standalone", "background_color": "#001a4d", "theme_color": "#0052cc", "icons": []})

# Serve Google verification file at site root
@app.route('/google78cbf317abe48f6e.html')
def google_verification():
    return app.send_static_file('google78cbf317abe48f6e.html')

@app.route('/sw.js')
def service_worker():
    return app.send_static_file('sw.js')

if __name__ == '__main__':
    with app.app_context():
        create_initial_data()
    app.run(debug=False)
