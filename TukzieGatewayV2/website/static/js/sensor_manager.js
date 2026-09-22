/*
  Sensor Manager for Tukzie Dashboard — WebSocket Relay Version
  Connects to FastAPI backend via WebSocket, receives live telemetry.

  No MQTT credentials in browser. Password lives safely on server.

  ---------------------------------------------------------------------
  FIELD-NAME TRANSLATION lives in app.js's mapSensorPayload(), not here:
  ---------------------------------------------------------------------
  The gateway (gateway/schema.py -> TelemetryPacket) publishes the real
  STM sensor field names: cImu, rImu, fRadar, bRadar, brake, light,
  lever, throttle, rain, bVoltage, bTemp, bCurrent, bSOC, bFault.

  app.js's main telemetry renderer (speed dial, hero cards, trip
  calculations, graphs) already had exactly one function whose job is
  translating whatever's on the wire into its internal camelCase model
  — mapSensorPayload(). It originally only recognized the old
  sensor_1../bms_* naming; it's now been extended there (not
  duplicated here) to also recognize the real schema names. This file
  just passes the raw parsed payload straight through as the
  "telemetry-update" event detail, plus feeds the separate ground-truth
  panel below.
*/

function num(v) {
  const n = parseFloat(v);
  return Number.isFinite(n) ? n : null;
}

function fmt(v, decimals) {
  return v === null ? "--" : v.toFixed(decimals);
}

function updateRawSensorCards(raw) {
  // Writes real schema fields straight to the "Raw sensor feed (STM32)"
  // cards — no derivation, no fallback math. Anything missing just
  // stays "--". Separate from app.js's mapSensorPayload(): that
  // function feeds the older, higher-level widgets; this one is the
  // ground-truth panel.
  const setText = (id, value) => {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  };

  const parseImu = (value) => {
    try {
      const obj = JSON.parse(value);
      return { pitch: num(obj.pitch), roll: num(obj.roll) };
    } catch {
      return { pitch: null, roll: null };
    }
  };

  if (raw.cImu !== undefined) {
    const { pitch, roll } = parseImu(raw.cImu);
    setText("stm-fimu-pitch", fmt(pitch, 1));
    setText("stm-fimu-roll", fmt(roll, 1));
  }
  if (raw.rImu !== undefined) {
    const { pitch, roll } = parseImu(raw.rImu);
    setText("stm-rimu-pitch", fmt(pitch, 1));
    setText("stm-rimu-roll", fmt(roll, 1));
  }
  if (raw.fRadar !== undefined) setText("stm-fradar", fmt(num(raw.fRadar), 2));
  if (raw.bRadar !== undefined) setText("stm-bradar", fmt(num(raw.bRadar), 2));
  if (raw.throttle !== undefined) setText("stm-throttle", fmt(num(raw.throttle), 0));
  if (raw.brake !== undefined) setText("stm-brake", fmt(num(raw.brake), 0));
  if (raw.lever !== undefined) setText("stm-lever", raw.lever ?? "--");
  if (raw.light !== undefined) setText("stm-light", fmt(num(raw.light), 0));
  if (raw.rain !== undefined) setText("stm-rain", fmt(num(raw.rain), 2));
  if (raw.bSOC !== undefined) setText("stm-batt-soc", fmt(num(raw.bSOC), 0));
  if (raw.bVoltage !== undefined) setText("stm-batt-voltage", fmt(num(raw.bVoltage), 1));
  if (raw.bTemp !== undefined) setText("stm-batt-temp", fmt(num(raw.bTemp), 1));
  if (raw.bCurrent !== undefined) setText("stm-batt-current", fmt(num(raw.bCurrent), 2));
  if (raw.bFault !== undefined) setText("stm-batt-fault", raw.bFault ?? "--");
}

// Legacy (pre-gateway) mapping — kept only because the CSS selectors it
// targets overlap with app.js's own rendering below, and it silently
// no-ops against real telemetry (none of these keys exist in the real
// schema or in translateSchemaToDashboard's output). Safe to delete
// once you're sure nothing upstream still sends this shape.
const SENSOR_DISPLAY = {
  sensor_1:  { selector: "#speed-value",           unit: "",    decimals: 1, fallback: "--" },
  sensor_2:  { selector: "#throttle-value",        unit: "%",   decimals: 0, fallback: "--" },
  sensor_3:  { selector: "#brake-value",           unit: "%",   decimals: 0, fallback: "--" },
  bms_soc:  { selector: "#soc-value",             unit: "",    decimals: 0, fallback: "--" },
  sensor_5:  { selector: "#range-value",           unit: "",    decimals: 1, fallback: "--" },
  sensor_6:  { selector: "#consumption-value",     unit: "",    decimals: 2, fallback: "--" },
  sensor_7:  { selector: "#weather-temp",          unit: "°C",  decimals: 0, fallback: "--", also: "#status-temp" },
  sensor_8:  { selector: "#hero-health",           unit: "%",   decimals: 0, fallback: "--", also: "#modal-health" },
  sensor_9:  { selector: "#motor-temp",            unit: "°C",  decimals: 0, fallback: "--" },
  sensor_10: { selector: "#tyre-pressure",         unit: " kPa", decimals: 0, fallback: "--" },
  sensor_11: { selector: "#vehicle-load",          unit: " kg", decimals: 0, fallback: "--" },
  bms_voltage: { selector: "#battery-voltage",       unit: " V",  decimals: 1, fallback: "--" },
  bms_temp_t1: { selector: "#modal-core-temp",       unit: "°C",  decimals: 0, fallback: "--" },
  sensor_14: { selector: "#solar-power",           unit: "",    decimals: 0, fallback: "--" },
  sensor_15: { selector: "#hero-mode",             unit: "",    decimals: null, fallback: "--" },
  sensor_16: { selector: "#solar-voltage",         unit: "",    decimals: 1, fallback: "--" },
  sensor_17: { selector: "#solar-current",         unit: "",    decimals: 1, fallback: "--" },
  sensor_18: { selector: "#time-full",             unit: "",    decimals: null, fallback: "--" },
};

const DERIVED_SENSORS = {
  hero_range:   { source: "sensor_5", selector: "#hero-range",       unit: "", decimals: 1, fallback: "--" },
  status_battery: { source: "bms_soc", selector: "#status-battery", unit: "%", decimals: 0, fallback: "--" },
  speed_dial:   { source: "sensor_1", selector: ".speed-dial", type: "css", cssProperty: "--speed-progress", maxValue: 120, fallback: "0" },
  range_meter:  { source: "sensor_5", selector: "#range-meter-fill", type: "css", cssProperty: "width", maxValue: 70, unit: "%", fallback: "0%" },
  battery_soc:  { source: "sensor_4", selector: ".vehicle-soc", type: "battery", fallback: "--" },
};

class SensorManager {
  constructor() {
    this.readings = {};
    this.timestamps = {};
    this.ws = null;
    this.connected = false;
    this.reconnectTimer = null;
    this.sensorTimeoutMs = 5000;
    this.staleCheckInterval = 1000;
    this.pollTimer = null;
    this.pollIntervalMs = 1000;

    this._initFallbackValues();
    this._startStaleCheck();
  }

  _startStaleCheck() {
    const checkLoop = () => {
      this._checkStaleSensors();
      requestAnimationFrame(checkLoop);
    };
    requestAnimationFrame(checkLoop);
  }

  connect() {
    if (this.ws) return;

    // Use location.host to include port if not 80/443
    const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    const wsUrl = protocol + "//" + window.location.host + "/ws/telemetry";

    console.log("[SensorManager] Connecting to:", wsUrl);

    try {
      this.ws = new WebSocket(wsUrl);

      this.ws.onopen = () => {
        console.log("[SensorManager] WebSocket connected");
        this.connected = true;
      };

      this.ws.onmessage = (event) => {
        try {
          const original = JSON.parse(event.data);
          updateRawSensorCards(original);
          const telemetry = original;
          const now = Date.now();

          // NEW: Dispatch event so app.js can update charts and trip logic
          window.dispatchEvent(new CustomEvent("telemetry-update", {
            detail: { telemetry: telemetry }
          }));

          // Process individual sensors for simple text updates
          Object.entries(telemetry).forEach(([sensorId, rawValue]) => {
            if (!SENSOR_DISPLAY[sensorId]) return;

            let value = rawValue;
            if (rawValue && typeof rawValue === "object" && typeof rawValue.value !== "undefined") {
              value = rawValue.value;
            }

            this.readings[sensorId] = value;
            this.timestamps[sensorId] = now;
            this._updateDisplay(sensorId, value);
          });

          Object.keys(telemetry).forEach((sensorId) => {
            this._updateDerivedSensors(sensorId);
          });

        } catch (err) {
          console.error("[SensorManager] Parse error:", err);
        }
      };

      this.ws.onclose = (event) => {
        console.log("[SensorManager] WebSocket closed. Reconnecting in 2s...");
        this.connected = false;
        this.ws = null;
        clearTimeout(this.reconnectTimer);
        this.reconnectTimer = setTimeout(() => this.connect(), 2000);
      };

      this.ws.onerror = (err) => {
        console.error("[SensorManager] WebSocket error:", err);
        this.ws.close();
      };

    } catch (err) {
      console.error("[SensorManager] Failed to create WebSocket:", err);
      this.reconnectTimer = setTimeout(() => this.connect(), 2000);
    }
  }

  disconnect() {
    clearTimeout(this.reconnectTimer);
    if (this.ws) {
      this.ws.close();
      this.ws = null;
      this.connected = false;
    }
  }

  _updateDisplay(sensorId, value) {
    const config = SENSOR_DISPLAY[sensorId];
    if (!config) return;

    const displayValue = this._formatValue(value, config);

    const primaryEl = document.querySelector(config.selector);
    if (primaryEl) {
      primaryEl.textContent = displayValue;
    }

    if (config.also) {
      const alsoEl = document.querySelector(config.also);
      if (alsoEl) alsoEl.textContent = displayValue;
    }
  }

  _formatValue(value, config) {
    if (value === null || value === undefined || value === "") {
      return config.fallback;
    }
    if (typeof value === "string") return value;
    if (typeof value === "number") {
      if (config.decimals !== null && config.decimals !== undefined) {
        return value.toFixed(config.decimals);
      }
      return String(value);
    }
    return String(value);
  }

  _updateDerivedSensors(changedSensorId) {
    Object.entries(DERIVED_SENSORS).forEach(([derivedId, config]) => {
      if (config.source !== changedSensorId) return;

      const rawValue = this.readings[config.source];
      const elements = document.querySelectorAll(config.selector);
      if (!elements.length) return;

      elements.forEach((el) => {
        if (config.type === "css") {
          let cssValue;
          if (rawValue === null || rawValue === undefined) {
            cssValue = config.fallback;
          } else {
            const progress = Math.min(1, Math.max(0, Number(rawValue) / config.maxValue));
            cssValue = config.unit ? `${(progress * 100).toFixed(1)}%` : progress.toFixed(3);
          }
          el.style.setProperty(config.cssProperty, cssValue);
        } else if (config.type === "battery") {
          const soc = Number(rawValue);
          if (isNaN(soc) || rawValue === null || rawValue === undefined) {
            el.style.setProperty("--soc-level", "0%");
            el.style.setProperty("--soc-color", "var(--muted)");
          } else {
            const color = this._getSocColor(soc);
            el.style.setProperty("--soc-level", `${Math.min(100, Math.max(0, soc))}%`);
            el.style.setProperty("--soc-color", color);
          }
        } else {
          el.textContent = this._formatValue(rawValue, config);
        }
      });
    });
  }

  _getSocColor(soc) {
    if (soc < 15) return "var(--danger)";
    if (soc <= 74) return "var(--warning)";
    return "var(--success)";
  }

  _checkStaleSensors() {
    const now = Date.now();
    Object.keys(SENSOR_DISPLAY).forEach((sensorId) => {
      const lastUpdate = this.timestamps[sensorId];
      if (!lastUpdate || (now - lastUpdate > this.sensorTimeoutMs)) {
        if (this.readings[sensorId] !== undefined) {
          this._updateDisplay(sensorId, null);
        }
      }
    });
    Object.entries(DERIVED_SENSORS).forEach(([derivedId, config]) => {
      const lastUpdate = this.timestamps[config.source];
      if (!lastUpdate || (now - lastUpdate > this.sensorTimeoutMs)) {
        const elements = document.querySelectorAll(config.selector);
        if (!elements.length) return;
        elements.forEach((el) => {
          if (config.type === "css") {
            el.style.setProperty(config.cssProperty, config.fallback);
          } else if (config.type === "battery") {
            el.style.setProperty("--soc-level", "0%");
            el.style.setProperty("--soc-color", "var(--muted)");
          } else {
            el.textContent = config.fallback;
          }
        });
      }
    });
  }

  _initFallbackValues() {
    Object.entries(SENSOR_DISPLAY).forEach(([sensorId, config]) => {
      const el = document.querySelector(config.selector);
      if (el) el.textContent = config.fallback;
      if (config.also) {
        const alsoEl = document.querySelector(config.also);
        if (alsoEl) alsoEl.textContent = config.fallback;
      }
    });
    Object.entries(DERIVED_SENSORS).forEach(([derivedId, config]) => {
      const elements = document.querySelectorAll(config.selector);
      if (!elements.length) return;
      elements.forEach((el) => {
        if (config.type === "css") {
          el.style.setProperty(config.cssProperty, config.fallback);
        } else if (config.type === "battery") {
          el.style.setProperty("--soc-level", "0%");
          el.style.setProperty("--soc-color", "var(--muted)");
        } else {
          el.textContent = config.fallback;
        }
      });
    });
  }

  reset() {
    this.readings = {};
    this.timestamps = {};
    this._initFallbackValues();
  }

  getReading(sensorId) { return this.readings[sensorId] ?? null; }
  getAllReadings() { return { ...this.readings }; }
  isConnected() { return this.connected; }
  isSensorLive(sensorId) {
    const lastUpdate = this.timestamps[sensorId];
    if (!lastUpdate) return false;
    return (Date.now() - lastUpdate) <= this.sensorTimeoutMs;
  }
}

const sensorManager = new SensorManager();
window.sensorManager = sensorManager;

function startSensorManager() {
  sensorManager.connect();
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", startSensorManager);
} else {
  startSensorManager();
}