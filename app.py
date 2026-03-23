from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, send_file
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime, date, timedelta
import os
import io
import csv
import random
import re

app = Flask(__name__)
CORS(app)  # Allow chatbot requests if needed

# Use environment variable for secret key in production, fallback to dev key locally
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'lamaliva_vista_paradise_2026')
# Use absolute path for database to avoid location issues on Render
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

# ===================== CHATBOT LOGIC =====================
INTENTS = {
    "greeting": {
        "patterns": ["hello", "hi", "hey", "good morning", "good evening"],
        "responses": [
            "Hello! Welcome to La-Maliva Vista Hotel. How can I assist you today?",
            "Hi there! Need help with a booking or hotel information?"
        ]
    },
    "check_in_out": {
        "patterns": ["check in", "check out", "time", "arrival", "departure"],
        "responses": [
            "Check-in is from 2:00 PM, and check-out is until 12:00 PM. Early check-in may be available upon request."
        ]
    },
    "amenities": {
        "patterns": ["amenities", "pool", "gym", "wifi", "internet", "food", "restaurant"],
        "responses": [
            "We offer free high-speed Wi-Fi, 24/7 room service, and a beautiful view of Buea. Our restaurant serves local and international dishes."
        ]
    },
    "rooms": {
        "patterns": ["room", "price", "cost", "standard", "deluxe", "suite", "family"],
        "responses": [
            "Our rooms: Standard (10,000 FCFA), Deluxe (15,000 FCFA), Suite (20,000 FCFA), and Family (25,000 FCFA). All include breakfast."
        ]
    },
    "booking": {
        "patterns": ["book", "reservation", "how to book"],
        "responses": [
            "You can book directly by clicking 'New Booking' in the menu or calling us at (+237) 679-915-967."
        ]
    },
    "location": {
        "patterns": ["location", "where", "address", "find you"],
        "responses": [
            "We are located opposite Fako Heart Entrance, GRA Bokwaongo, Buea, Cameroon."
        ]
    },
    "fallback": {
        "patterns": [],
        "responses": [
            "I'm not sure I understand. Could you rephrase? You can also call reception at (+237) 679-915-967.",
            "I'm your digital assistant. Ask me about rooms, prices, or check-in times!"
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
    return jsonify({"response": reply})

# ===================== MODELS =====================
class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True)
    email = db.Column(db.String(120), unique=True)
    password_hash = db.Column(db.String(128))
    role = db.Column(db.String(20), default='user')

class Room(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    room_number = db.Column(db.String(10), unique=True)
    room_type = db.Column(db.String(50))
    price = db.Column(db.Float)
    status = db.Column(db.String(20), default='Available')

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

class Hotel(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), default='LA-MALIVA VISTA HOTEL')
    address = db.Column(db.String(200), default='Opposite Fako Heart Entrance, GRA Bokwaongo, Buea, Cameroon')
    tax_rate = db.Column(db.Float, default=0.0)

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))

# ===================== HELPER TO CREATE DATA =====================
def create_initial_data():
    with app.app_context():
        try:
            db.create_all()
            
            if not User.query.filter_by(username='admin').first():
                admin = User(username='admin', email='admin@lamaliva.com', password_hash=generate_password_hash('admin123'), role='admin')
                db.session.add(admin)
            
            # --- STRICT ROOM CONFIGURATION ---
            try:
                room_301 = Room.query.filter_by(room_number='301').first()
                if room_301:
                    db.session.delete(room_301)
                
                old_family = Room.query.filter_by(price=55000).first()
                if old_family:
                    db.session.delete(old_family)
            except Exception as e:
                print(f"Cleanup warning: {e}")

            rooms_data = [
                {'number': '101', 'type': 'Standard', 'price': 10000},
                {'number': '102', 'type': 'Deluxe', 'price': 15000},
                {'number': '201', 'type': 'Suite', 'price': 20000},
                {'number': '202', 'type': 'Family', 'price': 25000}
            ]
            
            for r_data in rooms_data:
                existing_room = Room.query.filter_by(room_number=r_data['number']).first()
                if existing_room:
                    existing_room.room_type = r_data['type']
                    existing_room.price = r_data['price']
                else:
                    new_room = Room(
                        room_number=r_data['number'], 
                        room_type=r_data['type'], 
                        price=r_data['price'], 
                        status='Available'
                    )
                    db.session.add(new_room)
            
            if not Hotel.query.first():
                default_hotel = Hotel()
                db.session.add(default_hotel)
            
            db.session.commit()
            print("Database initialized successfully.")
        except Exception as e:
            print(f"Database initialization error: {e}")

try:
    create_initial_data()
except Exception as e:
    print(f"Startup Error: {e}")

# ===================== ROUTES =====================
@app.route('/')
def public_home():
    rooms = Room.query.order_by(Room.price).all()
    return render_template('public_home.html', rooms=rooms)

@app.route('/signup', methods=['GET', 'POST'])
def signup():
    if request.method == 'POST':
        username = request.form['username']
        email = request.form['email']
        password = request.form['password']
        
        if not email.endswith('@gmail.com'):
            flash('❌ Only genuine Gmail accounts (@gmail.com) are allowed!', 'error')
            return redirect(url_for('signup'))
        
        existing_user = User.query.filter((User.username == username) | (User.email == email)).first()
        if existing_user:
            flash('❌ Username or Email already exists!', 'error')
            return redirect(url_for('signup'))
        
        new_user = User(username=username, email=email, password_hash=generate_password_hash(password))
        db.session.add(new_user)
        db.session.commit()
        
        flash('✅ Account created successfully! Please login.', 'success')
        return redirect(url_for('login'))
        
    return render_template('signup.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        identifier = request.form['username']
        password = request.form['password']
        user = User.query.filter((User.username == identifier) | (User.email == identifier)).first()
        
        if user and check_password_hash(user.password_hash, password):
            login_user(user)
            return redirect(url_for('dashboard'))
        else:
            flash('Invalid credentials')
    return render_template('login.html')

@app.route('/dashboard')
@login_required
def dashboard():
    today = datetime.today().date()
    total_rooms = Room.query.count()
    occupied_rooms = Room.query.filter_by(status='Occupied').count()
    free_rooms = total_rooms - occupied_rooms
    occupancy_rate = int((occupied_rooms / total_rooms) * 100) if total_rooms > 0 else 0
    arrivals = Reservation.query.filter(Reservation.check_in >= datetime.combine(today, datetime.min.time()), Reservation.check_in < datetime.combine(today + timedelta(days=1), datetime.min.time())).all()
    return render_template('dashboard.html', occupied=occupied_rooms, free=free_rooms, occupancy_rate=occupancy_rate, arrivals=arrivals)

@app.route('/calendar')
@login_required
def calendar():
    return render_template('calendar.html')

@app.route('/api/rooms')
@login_required
def api_rooms():
    rooms = Room.query.order_by(Room.price).all()
    return jsonify([{'id': str(r.id), 'title': f'Room {r.room_number} ({r.room_type})'} for r in rooms])

@app.route('/api/reservations')
@login_required
def api_reservations():
    reservations = Reservation.query.all()
    events = []
    for r in reservations:
        guest = Guest.query.get(r.guest_id)
        color = '#28a745' if r.status == 'Checked-In' else '#6c757d' if r.status == 'Checked-Out' else '#007bff'
        events.append({
            'id': r.id,
            'resourceId': str(r.room_id),
            'title': f"{guest.name} ({r.status})" if guest else 'Reservation',
            'start': r.check_in.isoformat(),
            'end': r.check_out.isoformat(),
            'color': color
        })
    return jsonify(events)

@app.route('/rooms')
@login_required
def rooms():
    rooms_list = Room.query.order_by(Room.price).all()
    return render_template('rooms.html', rooms=rooms_list)

@app.route('/reservations')
@login_required
def reservations():
    res_list = Reservation.query.all()
    return render_template('reservations.html', reservations=res_list)

@app.route('/guests')
@login_required
def guests():
    if current_user.role not in ['admin', 'staff']:
        flash('Access denied')
        return redirect(url_for('dashboard'))
    guest_list = Guest.query.all()
    return render_template('guests.html', guests=guest_list)

@app.route('/new_reservation', methods=['GET', 'POST'])
@login_required
def new_reservation():
    if request.method == 'POST':
        guest = Guest(name=request.form['name'], phone=request.form['phone'], email=request.form['email'])
        db.session.add(guest)
        db.session.commit()
        
        room = Room.query.get(request.form['room_id'])
        check_in = datetime.strptime(f"{request.form['check_in_date']} {request.form['check_in_time']}", '%Y-%m-%d %H:%M')
        check_out = datetime.strptime(f"{request.form['check_out_date']} {request.form['check_out_time']}", '%Y-%m-%d %H:%M')
        days = max((check_out - check_in).total_seconds() / (24 * 3600), 1)
        amount = room.price * days
        
        res = Reservation(guest_id=guest.id, room_id=room.id, check_in=check_in, check_out=check_out, amount=amount, status='Confirmed')
        db.session.add(res)
        db.session.commit()
        flash('Reservation created successfully!')
        return redirect(url_for('calendar'))
    
    available_rooms = Room.query.filter_by(status='Available').order_by(Room.price).all()
    return render_template('new_reservation.html', rooms=available_rooms)

@app.route('/checkin/<int:res_id>')
@login_required
def checkin(res_id):
    res = Reservation.query.get_or_404(res_id)
    if res.status == 'Checked-In':
        flash('Already checked in!')
        return redirect(url_for('calendar'))
    res.status = 'Checked-In'
    room = Room.query.get(res.room_id)
    room.status = 'Occupied'
    db.session.commit()
    flash('Check-in successful!')
    return redirect(url_for('calendar'))

@app.route('/checkout/<int:res_id>')
@login_required
def checkout(res_id):
    res = Reservation.query.get_or_404(res_id)
    if res.status == 'Checked-Out':
        flash('Already checked out!')
        return redirect(url_for('calendar'))
    res.status = 'Checked-Out'
    room = Room.query.get(res.room_id)
    room.status = 'Available'
    db.session.commit()
    flash('Check-out successful!')
    return redirect(url_for('calendar'))

@app.route('/invoice/<int:res_id>')
@login_required
def invoice(res_id):
    res = Reservation.query.get_or_404(res_id)
    guest = Guest.query.get(res.guest_id)
    room = Room.query.get(res.room_id)
    duration_seconds = (res.check_out - res.check_in).total_seconds()
    days = duration_seconds / (24 * 3600)
    return render_template('invoice.html', res=res, guest=guest, room=room, days=days, now=datetime.now())

@app.route('/logout')
@login_required
def logout():
    logout_user()
    return redirect(url_for('login'))

@app.route('/export_data')
@login_required
def export_data():
    if current_user.role not in ['admin', 'staff']:
        flash('Access denied')
        return redirect(url_for('dashboard'))
    guests = Guest.query.all()
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['Name', 'Phone', 'Email'])
    for g in guests:
        writer.writerow([g.name, g.phone, g.email])
    output.seek(0)
    return send_file(io.BytesIO(output.getvalue().encode('utf-8')), mimetype='text/csv', as_attachment=True, download_name='guests.csv')

@app.route('/settings', methods=['GET', 'POST'])
@login_required
def settings():
    if current_user.role != 'admin':
        flash('Access denied')
        return redirect(url_for('dashboard'))
    hotel = Hotel.query.first()
    if request.method == 'POST':
        hotel.name = request.form['name']
        hotel.address = request.form['address']
        hotel.tax_rate = float(request.form['tax_rate'])
        db.session.commit()
        flash('Settings updated')
        return redirect(url_for('settings'))
    return render_template('settings.html', hotel=hotel)

@app.route('/users', methods=['GET', 'POST'])
@login_required
def users():
    if current_user.role != 'admin':
        flash('Access denied')
        return redirect(url_for('dashboard'))
    if request.method == 'POST':
        action = request.form.get('action')
        if action == 'add':
            username = request.form['username']
            email = request.form['email']
            password = request.form['password']
            role = request.form['role']
            if User.query.filter((User.username == username) | (User.email == email)).first():
                flash('User already exists')
            else:
                new_user = User(username=username, email=email, password_hash=generate_password_hash(password), role=role)
                db.session.add(new_user)
                db.session.commit()
                flash('User added')
        elif action == 'delete':
            user_id = request.form.get('user_id')
            user = User.query.get(user_id)
            if user and user.id != current_user.id:
                db.session.delete(user)
                db.session.commit()
                flash('User deleted')
        return redirect(url_for('users'))
    users_list = User.query.all()
    return render_template('users.html', users=users_list)

@app.route('/edit_user/<int:user_id>', methods=['GET', 'POST'])
@login_required
def edit_user(user_id):
    if current_user.role != 'admin':
        flash('Access denied')
        return redirect(url_for('dashboard'))
    user = User.query.get_or_404(user_id)
    if request.method == 'POST':
        username = request.form['username']
        email = request.form['email']
        password = request.form.get('password')
        role = request.form['role']
        existing = User.query.filter(((User.username == username) | (User.email == email)) & (User.id != user_id)).first()
        if existing:
            flash('Username or Email already exists')
        else:
            user.username = username
            user.email = email
            if password:
                user.password_hash = generate_password_hash(password)
            user.role = role
            db.session.commit()
            flash('User updated')
            return redirect(url_for('users'))
    return render_template('edit_user.html', user=user)

@app.route('/backup')
@login_required
def backup():
    if current_user.role != 'admin':
        flash('Access denied')
        return redirect(url_for('dashboard'))
    return send_file(db_path, as_attachment=True, download_name='lamaliva_backup.db')

@app.route('/restore', methods=['GET', 'POST'])
@login_required
def restore():
    if current_user.role != 'admin':
        flash('Access denied')
        return redirect(url_for('dashboard'))
    if request.method == 'POST':
        file = request.files['backup_file']
        if file:
            file.save(db_path)
            flash('Database restored. Please restart the application.')
            return redirect(url_for('dashboard'))
    return render_template('restore.html')

@app.route('/about')
def about():
    return render_template('about.html')

@app.route('/todays_arrivals')
@login_required
def todays_arrivals():
    today = date.today()
    arrivals = Reservation.query.filter(db.func.date(Reservation.check_in) == today).all()
    return render_template('arrivals.html', arrivals=arrivals, today=today)

@app.route('/todays_departures')
@login_required
def todays_departures():
    today = date.today()
    departures = Reservation.query.filter(db.func.date(Reservation.check_out) == today).all()
    return render_template('departures.html', departures=departures, today=today)

@app.route('/occupancy_report')
@login_required
def occupancy_report():
    total_rooms = Room.query.count()
    occupied_rooms = Room.query.filter_by(status='Occupied').count()
    occupancy_rate = (occupied_rooms / total_rooms * 100) if total_rooms > 0 else 0
    rooms = Room.query.order_by(Room.price).all()
    return render_template('occupancy.html', rooms=rooms, total=total_rooms, occupied=occupied_rooms, rate=occupancy_rate)

@app.route('/user_manual')
def user_manual():
    return render_template('user_manual.html')

# Generate manifest.json for PWA
@app.route('/manifest.json')
def manifest():
    return jsonify({
        "name": "LaMalaVista",
        "short_name": "LaMalaVista",
        "start_url": "/dashboard",
        "display": "standalone",
        "background_color": "#001a4d",
        "theme_color": "#0052cc",
        "icons": [{
            "src": "/static/logo.png",
            "sizes": "192x192",
            "type": "image/png"
        }]
    })

# Service Worker for PWA
@app.route('/sw.js')
def service_worker():
    return app.send_static_file('sw.js')

if __name__ == '__main__':
    app.run(debug=True)