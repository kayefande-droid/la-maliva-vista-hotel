LA MALIVA VISTA - STAFF APPS AND SERVER
=======================================

WHAT IS RUNNING
---------------
The hotel API runs on this Windows PC and is available to the staff apps.

  Server address   http://192.168.1.128:8000
  Health check     http://192.168.1.128:8000/healthz
  Service name     Scheduled task "La Maliva Vista API" (starts at logon)

Sign in:
  Username   admin
  Password   MalivaVista#2026
  Role       admin
  (Change this password before the apps leave the building - see below.)


WHAT CHANGED IN THE DESIGN
--------------------------
The console was rebuilt around the hotel's own brand and its setting:
- A photographic sign-in: Mount Cameroon at dusk behind the hotel mark, with
  a slow drift across the image (held still if Windows reduced motion is on).
- Cormorant Garamond for titles and figures, Inter for everything read in a
  list. Both fonts ship inside the app, so it looks the same on any machine.
- A navy rail on the PC (Overview, Rooms, Bookings, Guests) and a navy bottom
  bar on the phone, so the two apps stay recognisable but not identical.
- Today's screen leads with arrivals, departures, who is in the house and the
  occupancy rate, then the arrivals list and a live room-status bar.
- Rooms, Bookings and Guests are tables on the PC and thumb-sized cards on the
  phone, with hairlines, tabular figures and quiet hover states.
- Every panel has loading, empty, error and full states; errors say the server
  did not answer and offer Try again.


THE TWO APPS
------------
Windows   Windows\LaMalivaStaff\lamaliva_staff.exe
          Talks to http://127.0.0.1:8000 (same PC, so it always works).

Android   Android\LaMalivaStaff-debug.apk
          Talks to http://192.168.1.128:8000, compiled into the APK.


INSTALLING ON THE PHONE
-----------------------
1. The phone and this PC must be on the same Wi-Fi ("Efande Residence 2").
2. Copy LaMalivaStaff-debug.apk to the phone (USB cable, or send it to
   yourself) and open it. Android will ask to allow installs from this
   source - allow it, then finish the install.
3. Open "La Maliva Staff" and sign in with the credentials above.

If the phone says it cannot reach the server, check these in order:
  a) The PC is awake and the task is running:
       Get-ScheduledTask -TaskName "La Maliva Vista API"
  b) The PC's address is still 192.168.1.128:
       ipconfig
     If the router handed out a different address, the APK must be rebuilt
     with the new one (see below) - or reserve 192.168.1.128 for this PC in
     the router settings so it never changes.
  c) The firewall rule "La Maliva Vista API 8000" is enabled and the Wi-Fi
     network is set to Private (it is, as of setup).


USEFUL COMMANDS (run in the backend folder)
-------------------------------------------
Start the server by hand
    python wsgi.py

Restart the background service
    Stop-ScheduledTask  -TaskName "La Maliva Vista API"
    Start-ScheduledTask -TaskName "La Maliva Vista API"

See who is signed in / reset a password
    python scripts/reset_staff_password.py --list
    python scripts/reset_staff_password.py --username admin --apply
    (prints a one-time password once; the account must change it next login)

Rebuild the Android app for a different server address
    cd android_app
    flutter build apk --debug --dart-define=LAMALIVA_API=http://<PC-IP>:8000

Rebuild the Windows app
    cd windows_app
    flutter build windows


NOTES AND CURRENT LIMITS
------------------------
- The database is currently SQLite (backend\lamaliva_dev.db), not PostgreSQL:
  the PostgreSQL installer could not be downloaded because this connection
  drops large transfers. The schema and all data are the real migrated hotel
  data (14 rooms, 2 guests, 2 reservations), so switching to PostgreSQL later
  is a database swap, not a rewrite.
- The API is a development-grade server (Flask). It is fine for a handful of
  staff devices on the hotel network; it is not hardened for the open
  internet. Do not port-forward 8000 on the router.
- Neither app prompts for the forced password change yet; the password above
  is already set and marked as changed.
