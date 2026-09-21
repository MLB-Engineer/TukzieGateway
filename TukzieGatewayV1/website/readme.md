# Tukzie E-Vehicle Dashboard

A lightweight FastAPI + static frontend prototype for an electric tuk-tuk dashboard.

The project includes:
- `main.py`: FastAPI backend with JWT login, a static asset server, and demo telemetry routes.
- `database.py`: SQLite user store with password hashing and default user initialization.
- `seed_db.py`: optional script to recreate `users.db` and seed development credentials.
- `static/`: frontend UI assets and dashboard logic.

## Features

- JWT token authentication via `/token`
- User registration via `/register`
- Health check endpoint at `/health`
- Demo telemetry endpoint at `/api/v1/telemetry/live`
- Static dashboard served from `/` and `/static`
- Role-based dashboard access in the frontend (guest, driver, developer)

## Requirements

- Python 3.11+ (recommended)
- `fastapi`
- `uvicorn`
- `python-jose[cryptography]`
- `passlib[bcrypt]`
- `python-multipart`
- `influxdb-client` (included in requirements, not currently used by the example routes)

Install dependencies:

```powershell
python -m pip install -r requirements.txt
```

## Run the app

Start the application locally:

```powershell
python main.py
```

Or use Uvicorn directly:

```powershell
uvicorn main:app --host 0.0.0.0 --port 80 --reload
```

The dashboard is available at:

- `http://localhost:80/`

## Environment variables

The app reads these variables from the environment:

- `SECRET_KEY` -
- `PORT` - 

Example in PowerShell:

```powershell
$env:SECRET_KEY = "your-secret-key"
$env:PORT = "8080"
python main.py
```

## Database setup

The application initializes `users.db` automatically on startup if it does not exist.

To recreate the database and seed sample credentials, run:

```powershell
python seed_db.py
```



## Authentication flow

- Login with `/token` using form data `username` and `password`
- A valid token is returned as `access_token`
- Dashboard frontend stores the token and checks protected roles for driver/developer access

## Frontend

The static UI in `static/` includes:
- `index.html` — dashboard shell and login screen
- `styles.css` — dashboard styling
- `app.js` — UI logic, role handling, and dashboard updates
- `sensor_manager.js` — MQTT sensor configuration and live telemetry wiring

The frontend currently uses mock telemetry data and can be extended to call the FastAPI endpoints or live MQTT telemetry.

## Notes

- The demo telemetry endpoint returns static sample values.
- The dashboard is structured for a future React/modern UI migration.
- `influxdb-client` is installed but not used by the current sample routes.
