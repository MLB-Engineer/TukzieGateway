# Tukzie Gateway

The Raspberry Pi-side gateway that sits between the vehicle's sensors/actuators
and the MQTT broker. It has three jobs:

1. Read sensor data (from the STM32, later) and publish it as telemetry.
2. Receive control commands from the dashboard, validate them, and either
   act on them (reject invalid/replayed/rate-limited ones) or ack them.
3. Publish telemetry to MQTT broker.

## Version 1
Entirely laptop-based |
Sensor data is *simulated* in software. Local Mosquitto broker (Docker) |
Command validation + mock ack responder + dashboard, all wired together

**Version 1 deliberately skips:** real hardware (STM32/USB dongles) and
adaptive network switching. Everything is built so that swapping in real
hardware later only touches the one function documented below — nothing
else in the pipeline changes.

## Architecture (Version 1)

```
[gateway/sensor_simulator.py]  --publishes telemetry-->  [local Mosquitto : Docker, your laptop]
        (fakes STM data)                            

[dashboard/app.py + templates/index.html]  --publishes command-->  tukzie/commands
        (Flask control UI, buttons)                 <--reads ack--   tukzie/acks

[gateway/command_validation.py]  (run via gateway/mock_ack_responder.py)
        subscribes to tukzie/commands, checks schema + HMAC auth + replay
        age + rate limit, ACCEPTS or REJECTS each command, and if
        accepted, the mock rig publishes a fake ack to tukzie/acks
        (stands in for the real STM/rig hardware until it exists)
```

## Repo layout — what each file is for

```
config/config.yaml           Single source of truth for broker connection
                              details (host, port, TLS, credentials, topic
                              names) for the local_docker. Nothing else in
                              the codebase should ever hardcode a host,
                              port, or password — change it here.

gateway/
  broker.py                  Loads a profile from config.yaml and wraps
                              paho-mqtt. Every other module only ever
                              talks to a BrokerConnection object, never
                              to config.yaml directly.
  schema.py                  TelemetryPacket and CommandPacket dataclasses.
                              This is the single source of truth for what
                              fields a telemetry/command payload has.
                              >>> Add new sensors here first. <<<
  sensor_simulator.py         Fakes STM32 sensor readings and
                              publishes them. Swap `read_from_stm()`
                              for a real serial/USB read once hardware
                              exists — nothing else changes.
  command_validation.py       Validates incoming commands: schema check,
                              HMAC auth, replay-age check, rate limiting.
                              One validate() call path so there's one
                              thing to test.
  mock_ack_responder.py       Stands in for the real STM/rig hardware.
                              Subscribes to commands, runs them through
                              CommandValidator, and publishes a fake ack
                              for anything accepted. Delete this once real
                              hardware acks are wired up — nothing else
                              changes.
  buffering.py                 Store-and-forward: if a publish fails
                              (broker unreachable), the payload is queued
                              in a local SQLite file and retried later via
                              .flush(). Used per-broker inside
                              sensor_simulator.py so a dead Hostinger link
                              never blocks local telemetry.
  dead_letter.py                Quarantines malformed telemetry instead of
                              silently dropping it — republishes it (with
                              a reason) to tukzie/telemetry/rejected.
  adaptive_scoring.py         Not wired in yet. Scores the 3 USB
                              dongles (signal/latency/loss) and picks the
                              best one with hysteresis, so links don't
                              flap. Fully implemented — just not called
                              from anywhere until the Pi + dongles exist.

dashboard/
  app.py                       Minimal Flask control UI. Buttons POST to
                              /command, which signs + publishes to
                              tukzie/commands, and polls /status/<cmd> for
                              the ack.
  templates/index.html          The actual buttons/page.

broker-config/
  mosquitto/mosquitto.conf      Config for your local Docker Mosquitto
                              broker: TLS + username/password auth.
  mosquitto/acl.conf            Who can publish/subscribe to what, on the
                              local broker. Simplified to one full-access
                              dev user for V1 (see comments in the file
                              for the role-scoped version to switch back
                              to once this leaves your laptop).
  generate_local_certs.sh       One-off script: generates a self-signed
                              CA + server cert for the local broker.

tests/                          The existing "done when" proof scripts for
                              buffering, command validation, dead-letter,
                              and adaptive scoring. Run with e.g.
                              `python -m tests.test_command_validation`.
```

## How to add a new sensor (or any new data point)

1. **`gateway/schema.py`** — add the field to `TelemetryPacket`.
2. **`gateway/sensor_simulator.py`** — add a fake-value generator for it
   inside `read_from_stm()` (or, once hardware exists, wherever you're
   reading the real value from).
3. **Dashboard display (if needed)** — the Dashboard Team's app reads
   fields by name in `sensor_manager.js`; add the matching label there so
   it shows up on screen.

Nothing else needs to change — `schema.py` is the only place the shape of
a telemetry packet is defined, and everything downstream (buffering,
dead-letter handling, MQTT publish) just serializes whatever's on the
dataclass.

## Running Version 1 (laptop only)

### 0. Install dependencies
```bash
python3 -m venv venv
source venv/bin/activate         # venv\Scripts\activate on Windows
pip install -r requirements.txt
```

### 1. Set up local broker (Docker + TLS)
```bash
bash broker-config/generate_local_certs.sh
mosquitto_passwd -c broker-config/mosquitto/passwd dev_publisher #see note below
```
(Note: If you don't have `mosquitto_passwd` locally? Run it inside the same Docker image:
`docker run --rm -it -v "$(pwd)/broker-config/mosquitto:/mosquitto/config" --entrypoint mosquitto_passwd eclipse-mosquitto -c /mosquitto/config/passwd dev_publisher`)

### 2. Run MQTT broker
```bash
docker run -it -p 8883:8883 \
  -v "$(pwd)/broker-config/mosquitto:/mosquitto/config" \
  eclipse-mosquitto
```

### 3. Export the password you set
```bash
export TUKZIE_LOCAL_MQTT_PASSWORD="whatever you typed into mosquitto_passwd"
#in every subsequent terminal
```

### 4. Start the pieces (each in its own terminal, from the repo root)
```bash
python3 -m gateway.mock_ack_responder      # stands in for the real control rig
python3 -m gateway.sensor_simulator        # fakes STM telemetry 
FLASK_APP=dashboard/app.py PYTHONPATH=. flask run
```

Open `http://localhost:5000`, click a button, and you should see the
command get validated, acked by the mock rig, and the dashboard update 


