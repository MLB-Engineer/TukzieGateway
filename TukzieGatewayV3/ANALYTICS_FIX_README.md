# Analytics / InfluxDB repair — 10 October 2026

## Observed evidence
The supplied InfluxDB screenshot queries `_field = timestamp`, showing a ~1.792G Unix timestamp. This does **not** demonstrate that `bVoltage`, `bSOC`, or other real sensor fields are present. The website health screenshot verifies recent MQTT and Influx traffic but not sensor-field completeness.

## Changes
- Telegraf converts numeric telemetry strings (`bVoltage`, `bSOC`, etc.) to numeric Influx fields before writing. IMU JSON and other text are left intact.
- Authenticated `GET /api/v1/telemetry/fields?range=-1h` lists stored fields and sample counts within the selected range.
- Analytics discovers fields and marks absent options as unavailable. When the selected field is absent it selects an available data field. If only `timestamp` / `sequence` exist, it shows an explicit warning rather than a meaningless timestamp chart.

## Deploy
Keep your EXISTING `.env`, Mosquitto credentials/certificates, database volumes and any live sensor gateway files. Do not overwrite secrets. From the project folder (with `.env` already present):

    docker compose up -d --build --force-recreate website telegraf
    docker compose logs --tail=100 telegraf
    docker compose logs --tail=100 website

Reload the website using a hard refresh (Ctrl+Shift+R), open Analytics and click Refresh. Select the field and range. Check http://localhost:8086 (if Docker is local) for available fields in InfluxDB Data Explorer.

## Diagnose if still no sensor fields

1. Check the real MQTT payload (use the same username/password/TLS settings as the website):

       docker compose exec mosquitto mosquitto_sub -h localhost -p 8883 --cafile /mosquitto/config/certs/ca.crt -u YOUR_MQTT_USER -P YOUR_MQTT_PASSWORD -t tukzie/telemetry -C 1

   NOTE: host/server TLS name may differ with your locally generated certificate; adjust TLS options for your own environment. Avoid writing passwords directly in shared terminal transcripts.
2. It **must** contain actual nonempty `bVoltage`, `bSOC`, etc. Example: `{"timestamp":1791639000,"bVoltage":"52.4","bSOC":"81.1"}`. The code cannot generate real voltage measurements if your publisher sends only `timestamp`.
3. Check `docker compose logs --tail=100 telegraf` for JSON parsing or Influx write/type conflict messages. A preexisting string-valued field and the new float type might conflict for older series. If so, configure a **new bucket** for corrected telemetry and update `INFLUX_BUCKET` consistently for influx/telegraf/website after provisioning it. Do not delete historical buckets without a backup.
4. Verify the endpoint `/api/v1/telemetry/fields?range=-1h` while logged in (the browser can authenticate using its normal session code).
5. The health indicators report service/traffic presence rather than individual sensor validity. The UI only charts stored fields with data in the selected time range.

## Additional issues observed
- The uploaded source includes `.env`, TLS private keys, and application private keys. They are deliberately not copied into this deliverable. Keep these locally, never publish them in Git or shared ZIPs, and consider rotating credentials if the ZIP was shared broadly.
- The uploaded repository includes a Python virtualenv (`venv/`) which should be recreated from dependency files, not packaged.
- `gateway/sensor_simulator.py` produces sensor values as *strings*; Telegraf conversion is intended to handle these. Any other MQTT publisher must send actual sensor keys and values.
- No access to the user's live Docker/Influx environment was available. A live end-to-end validation remains necessary.
