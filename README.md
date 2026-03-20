# LA-MALIVA VISTA HOTEL - A Taste of Paradise

## Overview
This is a comprehensive Hotel Management System (PMS) built with Python (Flask) designed specifically for **LA-MALIVA VISTA HOTEL** in Buea, Cameroon.

The system mimics the functionality and visual layout of KWHotel, featuring a resource timeline calendar, reservation management, guest database, and invoicing.

## Features
- **Public Booking Engine**: Allows guests to view rooms and book online.
- **Admin Dashboard**: Overview of today's arrivals, occupancy rates, and quick actions.
- **Interactive Calendar**: Drag-and-drop timeline view for managing reservations.
- **Room Management**: Manage room status (Available, Occupied, Cleaning) and pricing.
- **Guest Database**: Store guest details for quick check-ins.
- **Invoicing**: Generate printable invoices for guests.
- **Secure Authentication**: User signup and login system.
- **Responsive Design**: Works on mobile, tablet, and desktop.

## Installation & Setup

1.  **Install Dependencies**:
    ```bash
    pip install -r requirements.txt
    ```

2.  **Run the Application**:
    ```bash
    python app.py
    ```

3.  **Access the System**:
    - Open your browser and go to: `http://127.0.0.1:5000`
    - **Admin Login**:
        - Username: `admin`
        - Password: `admin123`
    - **New User**: Click "Sign Up" on the login page.

## Project Structure
- `app.py`: Main application logic and database models.
- `templates/`: HTML templates for the user interface.
- `static/`: (Optional) CSS/JS files if separated from templates.
- `lamaliva.db`: SQLite database (created automatically on first run).

## Deployment (Render)
This project is configured for deployment on Render.com.
1. Push code to GitHub.
2. Create a new Web Service on Render.
3. Connect your GitHub repository.
4. Set Build Command: `pip install -r requirements.txt`
5. Set Start Command: `gunicorn app:app`

## Credits
Built for LA-MALIVA VISTA HOTEL.
