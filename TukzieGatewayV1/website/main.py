import asyncio
import csv
import hashlib
import hmac
import io
import json
import os
import ssl
import sys
import threading
import time
from contextlib import asynccontextmanager
from datetime import datetime, timedelta
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, HTMLResponse, PlainTextResponse
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.staticfiles import StaticFiles
from jose import JWTError, jwt

import database
import paho.mqtt.client as mqtt
from influxdb_client import InfluxDBClient

BASE_DIR = Path(__file__).resolve().parent
STATIC_DIR = BASE_DIR / "static"

# --- CONFIGURATION (set these in Dokploy environment variables) ---
SECRET_KEY = os.getenv("SECRET_KEY")
if not SECRET_KEY:
    raise RuntimeError("SECRET_KEY environment variable is not set")

ALGORITHM = "HS256"
PORT = int(os.getenv("PORT", "80"))

# --- INFLUXDB CONFIGURATION (history endpoint, see website/infra/) ---
# Optional: if unset, /api/v1/telemetry/history just returns an error
# instead of crashing the whole app, since Version 1 works fine without it.
INFLUX_URL = os.getenv("INFLUX_URL", "http://localhost:8086")
INFLUX_TOKEN = os.getenv("INFLUX_TOKEN")
INFLUX_ORG = os.getenv("INFLUX_ORG", "tukzie-dev")
INFLUX_BUCKET = os.getenv("INFLUX_BUCKET", "telemetry")

# --- MQTT CONFIGURATION ---
#MQTT_HOST = os.getenv("MQTT_HOST", "broker.tukzie.com")
#MQTT_PORT = int(os.getenv("MQTT_PORT", "8883"))
#MQTT_USER = os.getenv("MQTT_USER")
#MQTT_PASSWORD = os.getenv("MQTT_PASSWORD")
#MQTT_TOPIC = os.getenv("MQTT_TOPIC", "tukzie/telemetry")
# --- LOCAL MQTT CONFIGURATION ---
MQTT_HOST = os.getenv("MQTT_HOST", "localhost")
MQTT_PORT = int(os.getenv("MQTT_PORT", "8883"))
MQTT_USER = os.getenv("MQTT_USER")
MQTT_PASSWORD = os.getenv("MQTT_PASSWORD")
MQTT_TOPIC = os.getenv("MQTT_TOPIC", "tukzie/telemetry")
# Control tab: commands out, acks back. Must match config/config.yaml's
# topic names at the repo root (gateway/mock_ack_responder.py is what
# actually validates and acks these).
MQTT_COMMANDS_TOPIC = os.getenv("MQTT_COMMANDS_TOPIC", "tukzie/commands")
MQTT_ACKS_TOPIC = os.getenv("MQTT_ACKS_TOPIC", "tukzie/acks")
# Must match gateway/mock_ack_responder.py's SHARED_SECRET (and
# dashboard/app.py's, if you're still running that too).
COMMAND_SHARED_SECRET = os.getenv("COMMAND_SHARED_SECRET", "test-secret-change-me")
# Default points at the same local broker cert the gateway/dashboard use
# (see broker-config/generate_local_certs.sh at the repo root). Override
# with MQTT_CA_CERT_PATH if you keep certs somewhere else.
MQTT_CA_CERT_PATH = os.getenv(
    "MQTT_CA_CERT_PATH",
    str(BASE_DIR / ".." / "broker-config" / "mosquitto" / "certs" / "ca.crt"),
)

# Safety Check: Ensure credentials exist before trying to connect
if not MQTT_USER or not MQTT_PASSWORD:
    print("[MQTT] WARNING: MQTT_USER or MQTT_PASSWORD not set. Connection will likely fail.")
    
# --- GLOBAL STATE ---
latest_telemetry = {}
telemetry_clients = set()
mqtt_client = None
main_loop = None
mqtt_connected = False              # is THIS website connected to the broker?
last_telemetry_at: float | None = None   # last time a telemetry message arrived
                                          # (used to infer whether the gateway
                                          # itself is still publishing)
GATEWAY_HEALTHY_AFTER_SECONDS = 5     # last telemetry within this -> "healthy"
GATEWAY_WARNING_AFTER_SECONDS = 15    # within this -> "warning", else "critical"

_latest_acks: dict[str, dict] = {}
_acks_lock = threading.Lock()

# In-memory only (resets on restart) — a real deployment would persist
# this. Good enough for "who's signed in" on Version 1.
_login_log: list[dict] = []
_login_log_lock = threading.Lock()
LOGIN_LOG_MAX_ENTRIES = 200

# --- LIFESPAN MANAGER (starts MQTT thread once) ---
@asynccontextmanager
async def lifespan(app: FastAPI):
    global main_loop
    main_loop = asyncio.get_running_loop()  # Capture the loop here
    
    mqtt_thread_instance = threading.Thread(target=mqtt_thread, daemon=True)
    mqtt_thread_instance.start()
    yield
    if mqtt_client:
        mqtt_client.disconnect()

app = FastAPI(title="Tukzie API", version="1.0.0", lifespan=lifespan)
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

# Make sure the sqlite database exists on startup.
database.initialize_db()

def create_access_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(hours=24)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


async def get_current_claims(token: str = Depends(oauth2_scheme)) -> dict:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str | None = payload.get("sub")
        role: str | None = payload.get("role")
        if username is None or role is None:
            raise HTTPException(status_code=401, detail="Invalid session")
        return {"username": username, "role": role}
    except JWTError as exc:
        raise HTTPException(status_code=401, detail="Invalid session") from exc


async def get_current_user(claims: dict = Depends(get_current_claims)) -> str:
    """Kept for backward compatibility with anything expecting just the
    username string."""
    return claims["username"]


def require_role(*allowed_roles: str):
    """Dependency factory: 403s unless the caller's JWT role is one of
    allowed_roles. Mirrors the client-side data-access gating in
    app.js's applyAccessControl(), but enforced server-side too — the
    frontend hiding a tab was never actual access control."""

    async def _dependency(claims: dict = Depends(get_current_claims)) -> dict:
        if claims["role"] not in allowed_roles:
            raise HTTPException(status_code=403, detail=f"requires role in {allowed_roles}")
        return claims

    return _dependency


@app.get("/health")
async def health_check():
    return {"status": "ok"}


@app.post("/token")
async def login(form_data: OAuth2PasswordRequestForm = Depends()):
    user = database.get_user(form_data.username)

    if not user:
        raise HTTPException(status_code=400, detail="Incorrect email or password")

    is_valid = database.verify_password(form_data.password, user["password"])
    if not is_valid:
        raise HTTPException(status_code=400, detail="Incorrect email or password")

    access_token = create_access_token(data={"sub": form_data.username, "role": user["role"]})

    with _login_log_lock:
        _login_log.append({
            "username": form_data.username,
            "role": user["role"],
            "at": datetime.utcnow().isoformat() + "Z",
        })
        del _login_log[:-LOGIN_LOG_MAX_ENTRIES]  # cap growth

    return {"access_token": access_token, "token_type": "bearer", "role": user["role"]}


@app.post("/register")
async def register(username: str, password: str, role: str = "operator", _=Depends(require_role("developer"))):
    """Account creation now requires a valid Developer session — see
    README's "Accounts / login" section for the previous, open version
    of this route."""
    if database.get_user(username):
        raise HTTPException(status_code=400, detail="User already exists")
    database.create_user(username, password, role)
    return {"msg": "User created successfully"}


# --- WEBSOCKET ENDPOINT FOR TELEMETRY ---
@app.websocket("/ws/telemetry")
async def telemetry_websocket(websocket: WebSocket):
    await websocket.accept()
    telemetry_clients.add(websocket)
    print(f"[WS] Client connected. Total clients: {len(telemetry_clients)}")
    
    # Send current snapshot immediately so UI isn't blank
    if latest_telemetry:
        try:
            await websocket.send_json(latest_telemetry)
        except Exception:
            pass
    
    try:
        while True:
            # Keep connection alive, optionally handle client pings
            data = await websocket.receive_text()
            # Client can send pings or commands here if needed
    except WebSocketDisconnect:
        print("[WS] Client disconnected")
    except Exception as e:
        print(f"[WS] Error: {e}")
    finally:
        telemetry_clients.discard(websocket)
        print(f"[WS] Client removed. Total clients: {len(telemetry_clients)}")


@app.get("/api/v1/telemetry/live")
async def get_telemetry():
    """REST fallback — returns last known telemetry."""
    if latest_telemetry:
        return latest_telemetry
    # Fallback mock data if MQTT hasn't connected yet
    return {
        "speed": 0,
        "throttle": 0,
        "brake": 0,
        "soc": 81,
        "range": 69.7,
        "consumption": 0.18,
        "ambientTemp": 24,
        "batteryHealth": 91,
        "motorTemp": 41,
        "tyrePressure": 220,
        "vehicleLoad": 320,
        "voltage": 358,
        "coreTemp": 48,
        "driveMode": "D",
    }


@app.get("/api/v1/telemetry/history")
async def get_telemetry_history(
    range: str = "-1h",
    field: str | None = None,
    format: str = "json",
    _=Depends(require_role("operator", "developer")),
):
    """Historical telemetry from InfluxDB (filled in by Telegraf — see
    website/infra/). `range` is any Flux duration string InfluxDB
    accepts, e.g. -1h, -24h, -7d. `field` optionally restricts to one
    sensor field (e.g. bSOC); omit it to get everything. `format=csv`
    returns a downloadable CSV instead of JSON — used by the Analytics
    tab's export button."""
    if not INFLUX_TOKEN:
        raise HTTPException(
            status_code=503,
            detail="INFLUX_TOKEN is not set — the InfluxDB/Telegraf stack "
                    "in website/infra/ isn't wired up yet.",
        )

    field_filter = f'|> filter(fn: (r) => r._field == "{field}")' if field else ""
    query = f"""
        from(bucket: "{INFLUX_BUCKET}")
          |> range(start: {range})
          |> filter(fn: (r) => r._measurement == "telemetry")
          {field_filter}
    """

    try:
        with InfluxDBClient(url=INFLUX_URL, token=INFLUX_TOKEN, org=INFLUX_ORG) as client:
            tables = client.query_api().query(query)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"InfluxDB query failed: {e}") from e

    points = [
        {"time": record.get_time().isoformat(), "field": record.get_field(), "value": record.get_value()}
        for table in tables
        for record in table.records
    ]

    if format == "csv":
        buf = io.StringIO()
        writer = csv.DictWriter(buf, fieldnames=["time", "field", "value"])
        writer.writeheader()
        writer.writerows(points)
        return PlainTextResponse(
            buf.getvalue(),
            media_type="text/csv",
            headers={"Content-Disposition": "attachment; filename=telemetry_history.csv"},
        )

    return {"points": points}


# --- CONTROL TAB: sign + publish commands, track their acks ---
def _sign_command(cmd: str, target: str, timestamp: float) -> str:
    payload = f"{cmd}:{target}:{timestamp}"
    return hmac.new(COMMAND_SHARED_SECRET.encode(), payload.encode(), hashlib.sha256).hexdigest()


@app.post("/api/v1/control/command")
async def send_control_command(body: dict, _=Depends(require_role("operator", "developer"))):
    """Signs and publishes a command the same way gateway/mock_ack_responder.py
    (or eventually the real rig) expects it — see gateway/command_validation.py.
    A REAL rejection (bad auth, rate-limited, stale) never reaches this
    process as an ack, so the frontend has to treat a timeout in
    /control/status as a failure, same as dashboard/app.py already does."""
    if mqtt_client is None or not mqtt_connected:
        raise HTTPException(status_code=503, detail="Not connected to the broker — command not sent.")

    cmd = body.get("cmd")
    target = body.get("target", "vehicle")
    if not cmd:
        raise HTTPException(status_code=400, detail="Missing 'cmd'")

    timestamp = time.time()
    payload = {
        "cmd": cmd,
        "target": target,
        "timestamp": timestamp,
        "auth_token": _sign_command(cmd, target, timestamp),
        "schema_version": "0.1.0",
    }
    mqtt_client.publish(MQTT_COMMANDS_TOPIC, json.dumps(payload))
    return {"published": True, "cmd": cmd}


@app.get("/api/v1/control/status/{cmd}")
async def get_control_status(cmd: str, _=Depends(require_role("operator", "developer"))):
    with _acks_lock:
        ack = _latest_acks.get(cmd)
    return ack or {"status": "pending"}


# --- SYSTEM HEALTH TAB ---
@app.get("/api/v1/system/health")
async def get_system_health(_=Depends(require_role("developer"))):
    seconds_since_telemetry = (time.time() - last_telemetry_at) if last_telemetry_at else None

    if seconds_since_telemetry is None:
        gateway_status = "critical"
    elif seconds_since_telemetry <= GATEWAY_HEALTHY_AFTER_SECONDS:
        gateway_status = "healthy"
    elif seconds_since_telemetry <= GATEWAY_WARNING_AFTER_SECONDS:
        gateway_status = "warning"
    else:
        gateway_status = "critical"

    return {
        "web_to_broker": "healthy" if mqtt_connected else "critical",
        "gateway_to_broker": gateway_status,
        "seconds_since_last_telemetry": seconds_since_telemetry,
        "checked_at": datetime.utcnow().isoformat() + "Z",
    }


@app.get("/api/v1/system/logs")
async def get_system_logs(_=Depends(require_role("developer"))):
    with _login_log_lock:
        return {"logins": list(reversed(_login_log))}


app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


@app.get("/")
async def serve_index():
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/{filename}")
async def serve_root_files(filename: str):
    file_path = STATIC_DIR / filename
    if file_path.is_file():
        return FileResponse(file_path)
    raise HTTPException(status_code=404, detail="File not found")


# --- MQTT BACKGROUND THREAD ---
def broadcast_to_clients(data: str):
    """Safely send data to WebSocket clients from the MQTT thread."""
    if not telemetry_clients or main_loop is None:
        return
    
    for ws in list(telemetry_clients):
        try:
            # Use call_soon_threadsafe to schedule the send in the main loop
            main_loop.call_soon_threadsafe(
                lambda w=ws, d=data: asyncio.create_task(w.send_text(d))
            )
        except Exception as e:
            print(f"[WS] Broadcast error: {e}")


def on_mqtt_connect(client, userdata, flags, rc):
    global mqtt_connected
    if rc == 0:
        mqtt_connected = True
        print(f"[MQTT] Connected to {MQTT_HOST}:{MQTT_PORT}")
        client.subscribe(MQTT_TOPIC)
        client.subscribe(MQTT_ACKS_TOPIC)
        print(f"[MQTT] Subscribed to {MQTT_TOPIC} and {MQTT_ACKS_TOPIC}")
    else:
        mqtt_connected = False
        print(f"[MQTT] Connection failed with code {rc}")


def on_mqtt_message(client, userdata, msg):
    global last_telemetry_at
    try:
        payload = json.loads(msg.payload)

        if msg.topic == MQTT_ACKS_TOPIC:
            # Control tab: an ack for a command sent via /api/v1/control/command
            with _acks_lock:
                _latest_acks[payload["cmd"]] = payload
            return

        latest_telemetry.update(payload)
        last_telemetry_at = time.time()

        if telemetry_clients:
            data = json.dumps(payload)
            broadcast_to_clients(data)

    except json.JSONDecodeError:
        print("[MQTT] Failed to parse JSON payload")
    except Exception as e:
        print(f"[MQTT] Message handling error: {e}")

def on_mqtt_disconnect(client, userdata, rc):
    global mqtt_connected
    mqtt_connected = False
    if rc != 0:
        print(f"[MQTT] Unexpected disconnection (code {rc}), will retry...")


def mqtt_thread():
    """Runs MQTT client in a background thread."""
    global mqtt_client
    
    mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1)
    mqtt_client.username_pw_set(MQTT_USER, MQTT_PASSWORD)
    
    # TLS with your CA certificate
    cert_path = Path(MQTT_CA_CERT_PATH)
    if cert_path.exists():
        mqtt_client.tls_set(ca_certs=str(cert_path))
        print(f"[MQTT] Using CA certificate: {cert_path}")
    else:
        # Fallback: disable verification (for local dev only)
        mqtt_client.tls_set(cert_reqs=ssl.CERT_NONE)
        mqtt_client.tls_insecure_set(True)
        print("[MQTT] WARNING: CA certificate not found, using insecure TLS")
    
    mqtt_client.on_connect = on_mqtt_connect
    mqtt_client.on_message = on_mqtt_message
    mqtt_client.on_disconnect = on_mqtt_disconnect
    
    try:
        mqtt_client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
        mqtt_client.loop_forever()
    except Exception as e:
        print(f"[MQTT] Fatal error: {e}")



print("[MQTT] Background thread started")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=PORT, log_level="info")

    