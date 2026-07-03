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
from functools import wraps # Import wraps for decorator

# ReportLab imports
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
from reportlab.lib.units import inch

app = Flask(__name__)
CORS(app)

# --- CONFIGURATION ---
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'lamaliva_vista_paradise_2026')
# Use absolute path for database to ensure it runs correctly everywhere
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
    role = db.Column(db.String(20), default='user') # 'user', 'staff', 'admin'
    registered_on = db.Column(db.DateTime, default=datetime.now(timezone.utc)) # New: Registration timestamp
    can_be_monitored_by_admin = db.Column(db.Boolean, default=False) # New: Permission for screen view
    first_login_done = db.Column(db.Boolean, default=False) # New: Track first login for welcome message

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
    guest_id = db.Column(db.Integer, db.ForeignKey('guest.id'))
    room_id = db.Column(db.Integer, db.ForeignKey('room.id'))
    check_in = db.Column(db.DateTime)
    check_out = db.Column(db.DateTime)
    status = db.Column(db.String(20), default='Confirmed') # Confirmed, Checked-In, Checked-Out, Cancelled
    amount = db.Column(db.Float)
    access_deadline = db.Column(db.DateTime, nullable=True) # New: Deadline for room access
    customer_arrived_paid = db.Column(db.Boolean, default=False) # New: Checkbox for arrival/payment

    # Define relationships
    guest = db.relationship('Guest', backref='reservations')
    room = db.relationship('Room', backref='reservations')

class Hotel(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), default='LA-MALIVA VISTA HOTEL')
    address = db.Column(db.String(200), default='Opposite Fako Heart Entrance, GRA Bokwaongo, Buea, Cameroon')
    tax_rate = db.Column(db.Float, default=0.0)

class ActivityLog(db.Model): # New ActivityLog Model
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

def log_activity(action_description):
    """Decorator for logging route access."""
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            _perform_log(action_description)
            return f(*args, **kwargs)
        return decorated_function
    return decorator

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
                admin = User(username='admin', email='admin@lamaliva.com', password_hash=generate_password_hash('admin123'), role='admin', registered_on=datetime.now(timezone.utc), can_be_monitored_by_admin=True, first_login_done=True) # Admin's first login is done
                db.session.add(admin)
            
            # Clear existing room data to ensure only the new, specified rooms are present
            Room.query.delete()
            db.session.commit()

            rooms_data = [
                # Standard Rooms
                {'number': '101', 'type': 'Standard', 'price': 10000, 'description': 'Basic comfort', 'image_url': 'https://images.unsplash.com/photo-1566073771259-6a8506099945?q=80&w=1920&auto=format&fit=crop'},
                {'number': '102', 'type': 'Standard', 'price': 15000, 'description': 'Comfort with a view', 'image_url': 'https://images.unsplash.com/photo-1542314831-068cd1dbfeeb?q=80&w=1920&auto=format&fit=crop'},
                {'number': '103', 'type': 'Standard', 'price': 15000, 'description': 'Comfort with a view', 'image_url': 'https://images.unsplash.com/photo-1571003123894-1f0594d2b5d9?q=80&w=1920&auto=format&fit=crop'},
                {'number': '104', 'type': 'Standard', 'price': 10000, 'description': 'Basic comfort', 'image_url': 'https://images.unsplash.com/photo-1611892440504-42a792e24d32?q=80&w=1920&auto=format&fit=crop'},
                
                # Deluxe Rooms
                {'number': '201', 'type': 'Deluxe', 'price': 25000, 'description': 'With fridge, couch, and large space', 'image_url': 'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?q=80&w=1920&auto=format&fit=crop'},
                {'number': '202', 'type': 'Deluxe', 'price': 15000, 'description': 'Spacious comfort', 'image_url': 'https://images.unsplash.com/photo-1566073771259-6a8506099945?q=80&w=1920&auto=format&fit=crop'},
                {'number': '203', 'type': 'Deluxe', 'price': 20000, 'description': 'With working space', 'image_url': 'https://images.unsplash.com/photo-1542314831-068cd1dbfeeb?q=80&w=1920&auto=format&fit=crop'},
                {'number': '204', 'type': 'Deluxe', 'price': 20000, 'description': 'With working space', 'image_url': 'https://images.unsplash.com/photo-1571003123894-1f0594d2b5d9?q=80&w=1920&auto=format&fit=crop'},
                {'number': '205', 'type': 'Deluxe', 'price': 15000, 'description': 'Spacious comfort', 'image_url': 'https://images.unsplash.com/photo-1611892440504-42a792e24d32?q=80&w=1920&auto=format&fit=crop'},
                {'number': '206', 'type': 'Deluxe', 'price': 15000, 'description': 'Spacious comfort', 'image_url': 'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?q=80&w=1920&auto=format&fit=crop'},
                {'number': '207', 'type': 'Deluxe', 'price': 15000, 'description': 'Spacious comfort', 'image_url': 'https://images.unsplash.com/photo-1566073771259-6a8506099945?q=80&w=1920&auto=format&fit=crop'},
                {'number': '208', 'type': 'Deluxe', 'price': 15000, 'description': 'Spacious comfort', 'image_url': 'https://images.unsplash.com/photo-1542314831-068cd1dbfeeb?q=80&w=1920&auto=format&fit=crop'},
                {'number': '209', 'type': 'Deluxe', 'price': 20000, 'description': 'With fridge and couch', 'image_url': 'https://images.unsplash.com/photo-1571003123894-1f0594d2b5d9?q=80&w=1920&auto=format&fit=crop'},
                {'number': '210', 'type': 'Deluxe', 'price': 20000, 'description': 'With smart TV', 'image_url': 'https://images.unsplash.com/photo-1611892440504-42a792e24d32?q=80&w=1920&auto=format&fit=crop'}
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

            if not Hotel.query.first():
                db.session.add(Hotel())
            db.session.commit()
        except Exception as e: print(f"DB Error: {e}")

# ===================== ROUTES =====================
@app.route('/')
def public_home():
    all_rooms = Room.query.order_by(Room.price).all() # Renamed to all_rooms
    return render_template('public_home.html', rooms=all_rooms)

@app.route('/signup', methods=['GET', 'POST'])
def signup():
    if request.method == 'POST':
        username = request.form['username']
        email = request.form['email']
        password = request.form['password']
        
        # Basic validation
        if not email.endswith('@gmail.com'):
            flash('❌ Only genuine Gmail accounts (@gmail.com) are allowed for user registration!', 'error')
            return redirect(url_for('signup'))
        if User.query.filter((User.username == username) | (User.email == email)).first():
            flash('❌ Username or Email already exists!', 'error')
            return redirect(url_for('signup'))
        
        # Default role for new signups is 'user'
        new_user = User(username=username, email=email, password_hash=generate_password_hash(password), role='user', registered_on=datetime.now(timezone.utc), first_login_done=False) # Set first_login_done to False
        db.session.add(new_user)
        db.session.commit()
        flash('✅ Account created successfully! Please login.', 'success')
        return render_template('signup.html') # Render signup template again to show flash message
    return render_template('signup.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        identifier = request.form['username']
        password = request.form['password']
        user = User.query.filter((User.username == identifier) | (User.email == identifier)).first()
        if user and check_password_hash(user.password_hash, password):
            login_user(user)
            if not user.first_login_done:
                flash(f'🎉 Welcome to La-Maliva Vista Hotel, {user.username}! We\'re excited to have you. Please review our terms of service and privacy policy.', 'success')
                user.first_login_done = True
                db.session.commit()
            else:
                flash(f'Welcome back, {user.username}!', 'success') # Welcome message for all users
            return redirect(url_for('dashboard'))
        else:
            flash('❌ Invalid username/email or password.', 'error')
    return render_template('login.html')

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

@app.route('/reservations')
@login_required
@log_activity("Viewed Reservations List") # Log activity
def reservations():
    res_list = Reservation.query.all()
    return render_template('reservations.html', reservations=res_list)

@app.route('/guests')
@login_required
@log_activity("Viewed Guests List") # Log activity
def guests():
    # Only admin and staff can view guests list
    if current_user.role not in ['admin', 'staff']:
        flash('❌ Access denied. Only staff and administrators can view guests.', 'error')
        return redirect(url_for('dashboard'))
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
@log_activity("Attempted Check-in") # Log activity
def checkin(res_id):
    res = Reservation.query.get_or_404(res_id)
    
    # Check if current user is admin or staff to allow setting customer_arrived_paid
    if current_user.role not in ['admin', 'staff']:
        flash('❌ Access denied. You do not have permission to perform this action.', 'error')
        return redirect(url_for('calendar'))

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
@log_activity("Attempted Check-out") # Log activity
def checkout(res_id):
    res = Reservation.query.get_or_404(res_id)
    
    if current_user.role not in ['admin', 'staff']:
        flash('❌ Access denied. You do not have permission to perform this action.', 'error')
        return redirect(url_for('calendar'))

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
@login_required
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
@log_activity("Exported Data") # Log activity
def export_data():
    if current_user.role not in ['admin', 'staff']:
        flash('❌ Access denied. Only staff and administrators can export data.', 'error')
        return redirect(url_for('dashboard'))
    
    all_guests = Guest.query.all() # Renamed to all_guests
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['Name', 'Phone', 'Email'])
    for g in all_guests: writer.writerow([g.name, g.phone, g.email])
    output.seek(0)
    return send_file(io.BytesIO(output.getvalue().encode('utf-8')), mimetype='text/csv', as_attachment=True, download_name='guests.csv')

@app.route('/settings', methods=['GET', 'POST'])
@login_required
@log_activity("Viewed/Edited Settings") # Log activity
def settings():
    if current_user.role != 'admin':
        flash('❌ Access denied. Only administrators can change settings.', 'error')
        return redirect(url_for('dashboard'))
    hotel = Hotel.query.first()
    if request.method == 'POST':
        hotel.name = request.form['name']
        hotel.address = request.form['address']
        hotel.tax_rate = float(request.form['tax_rate'])
        db.session.commit()
        flash('✅ Hotel settings updated successfully!', 'success')
        _perform_log("Updated Hotel Settings")
        return redirect(url_for('settings'))
    return render_template('settings.html', hotel=hotel)

@app.route('/users', methods=['GET', 'POST'])
@login_required
@log_activity("Viewed/Managed Users") # Log activity
def users():
    if current_user.role != 'admin':
        flash('❌ Access denied. Only administrators can manage users.', 'error')
        return redirect(url_for('dashboard'))
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
                new_user = User(username=username, email=email, password_hash=generate_password_hash(password), role=role, registered_on=datetime.now(timezone.utc), first_login_done=True) # Staff/Admin accounts are not new users
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
@log_activity("Viewed/Edited User Profile") # Log activity
def edit_user(user_id):
    if current_user.role != 'admin':
        flash('❌ Access denied. Only administrators can edit user profiles.', 'error')
        return redirect(url_for('dashboard'))
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
@log_activity("Performed Database Backup") # Log activity
def backup():
    if current_user.role != 'admin':
        flash('❌ Access denied. Only administrators can perform backups.', 'error')
        return redirect(url_for('dashboard'))
    return send_file(db_path, as_attachment=True, download_name='lamaliva_backup.db')

@app.route('/restore', methods=['GET', 'POST'])
@login_required
@log_activity("Attempted Database Restore") # Log activity
def restore():
    if current_user.role != 'admin':
        flash('❌ Access denied. Only administrators can restore databases.', 'error')
        return redirect(url_for('dashboard'))
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
@log_activity("Viewed Admin Monitoring Page") # Log activity
def admin_monitoring():
    if current_user.role != 'admin':
        flash('❌ Access denied. Administrators only.', 'error')
        return redirect(url_for('dashboard'))
    
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
@log_activity("Sent Message to User") # Log activity
def send_message():
    if current_user.role != 'admin':
        flash('❌ Access denied. Administrators only.', 'error')
        return redirect(url_for('dashboard'))
    
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

@app.route('/manifest.json')
def manifest():
    return jsonify({"name": "LaMalaVista", "short_name": "LaMalaVista", "start_url": "/dashboard", "display": "standalone", "background_color": "#001a4d", "theme_color": "#0052cc", "icons": [{"src": "/static/logo.png", "sizes": "192x192", "type": "image/png"}]})

@app.route('/sw.js')
def service_worker():
    return app.send_static_file('sw.js')

if __name__ == '__main__':
    with app.app_context():
        create_initial_data()
    app.run(debug=False)