from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime, date

app = Flask(__name__)
app.config['SECRET_KEY'] = 'lamaliva_vista_paradise_2026'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///lamaliva.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)
login_manager = LoginManager(app)
login_manager.login_view = 'login'

# ===================== MODELS =====================
class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True)
    password_hash = db.Column(db.String(128))

class Room(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    room_number = db.Column(db.String(10), unique=True)
    room_type = db.Column(db.String(50))
    price = db.Column(db.Float)
    status = db.Column(db.String(20), default='Available')  # Available, Occupied, Cleaning

class Guest(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100))
    phone = db.Column(db.String(20))
    email = db.Column(db.String(100))

class Reservation(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    guest_id = db.Column(db.Integer, db.ForeignKey('guest.id'))
    room_id = db.Column(db.Integer, db.ForeignKey('room.id'))
    check_in = db.Column(db.Date)
    check_out = db.Column(db.Date)
    status = db.Column(db.String(20), default='Confirmed')
    amount = db.Column(db.Float)

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))

# ===================== HELPER TO CREATE DATA =====================
def create_initial_data():
    db.create_all()
    if not User.query.filter_by(username='admin').first():
        admin = User(username='admin', password_hash=generate_password_hash('admin123'))
        db.session.add(admin)
        
        rooms = [
            Room(room_number='101', room_type='Deluxe', price=45000, status='Available'),
            Room(room_number='102', room_type='Standard', price=35000, status='Available'),
            Room(room_number='201', room_type='Suite', price=75000, status='Available'),
            Room(room_number='301', room_type='Family', price=55000, status='Available'),
        ]
        db.session.bulk_save_objects(rooms)
        db.session.commit()

# ===================== ROUTES =====================
@app.route('/')
def public_home():
    rooms = Room.query.all()
    return render_template('public_home.html', rooms=rooms)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        user = User.query.filter_by(username=request.form['username']).first()
        if user and check_password_hash(user.password_hash, request.form['password']):
            login_user(user)
            return redirect(url_for('dashboard'))
        flash('Invalid credentials')
    return render_template('login.html')

@app.route('/dashboard')
@login_required
def dashboard():
    today = datetime.today().date()
    # Calculate occupancy stats dynamically
    total_rooms = Room.query.count()
    occupied_rooms = Room.query.filter_by(status='Occupied').count()
    free_rooms = total_rooms - occupied_rooms
    
    occupancy_rate = int((occupied_rooms / total_rooms) * 100) if total_rooms > 0 else 0
    
    arrivals = Reservation.query.filter_by(check_in=today).all()
    
    return render_template('dashboard.html', 
                           occupied=occupied_rooms, 
                           free=free_rooms, 
                           occupancy_rate=occupancy_rate,
                           arrivals=arrivals)

@app.route('/calendar')
@login_required
def calendar():
    return render_template('calendar.html')

@app.route('/api/rooms')
@login_required
def api_rooms():
    rooms = Room.query.all()
    return jsonify([{'id': str(r.id), 'title': f'Room {r.room_number} ({r.room_type})'} for r in rooms])

@app.route('/api/reservations')
@login_required
def api_reservations():
    reservations = Reservation.query.all()
    events = []
    for r in reservations:
        guest = Guest.query.get(r.guest_id)
        # Color coding: Green for Check-In, Blue for Confirmed, Gray for Checked-Out
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
    rooms_list = Room.query.all()
    return render_template('rooms.html', rooms=rooms_list)

@app.route('/reservations')
@login_required
def reservations():
    res_list = Reservation.query.all()
    return render_template('reservations.html', reservations=res_list)

@app.route('/guests')
@login_required
def guests():
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
        days = (datetime.strptime(request.form['check_out'], '%Y-%m-%d').date() - 
                datetime.strptime(request.form['check_in'], '%Y-%m-%d').date()).days
        amount = room.price * days if days > 0 else room.price
        
        res = Reservation(guest_id=guest.id, room_id=room.id,
                          check_in=datetime.strptime(request.form['check_in'], '%Y-%m-%d').date(),
                          check_out=datetime.strptime(request.form['check_out'], '%Y-%m-%d').date(),
                          amount=amount, status='Confirmed')
        db.session.add(res)
        db.session.commit()
        flash('Reservation created successfully!')
        return redirect(url_for('calendar'))
    
    available_rooms = Room.query.filter_by(status='Available').all()
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
    flash('Check-in successful! Room marked as Occupied.')
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
    room.status = 'Available'  # Frees up the room immediately
    db.session.commit()
    flash('Check-out successful! Room is now Available.')
    return redirect(url_for('calendar'))

@app.route('/invoice/<int:res_id>')
@login_required
def invoice(res_id):
    res = Reservation.query.get_or_404(res_id)
    guest = Guest.query.get(res.guest_id)
    room = Room.query.get(res.room_id)
    days = (res.check_out - res.check_in).days
    return render_template('invoice.html', res=res, guest=guest, room=room, days=days)

@app.route('/logout')
@login_required
def logout():
    logout_user()
    return redirect(url_for('login'))

if __name__ == '__main__':
    with app.app_context():
        create_initial_data()
    app.run(debug=True)