#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// --- OLED Configuration ---
#define SCREEN_WIDTH 128 
#define SCREEN_HEIGHT 64 
#define I2C_SDA 21
#define I2C_SCL 18
#define OLED_ADDR 0x3C
#define OLED_RESET -1 
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// --- Pin Definitions ---
#define LEFT_LED_PIN   4
#define RIGHT_LED_PIN  15
#define BUZZER_PIN     5

// --- Dedicated UART Pins connected to USB Adapter ---
#define RX2_PIN 16  // Connects to Adapter TX
#define TX2_PIN 17  // Connects to Adapter RX

// --- System States ---
enum SystemState {
  STATE_OFF,
  STATE_BUZZER,
  STATE_FLASH_LEFT,
  STATE_FLASH_RIGHT,
  STATE_FLASH_BOTH
};

SystemState currentState = STATE_OFF;
bool oledConnected = false;

// Non-blocking LED timing
unsigned long previousMillis = 0;
const long flashInterval = 500; // 500ms ON / 500ms OFF
bool ledState = false;

// Safely quote arbitrary OLED text in JSON acknowledgement notes.
String jsonEscape(const String &input) {
  String out = "";
  for (size_t i = 0; i < input.length(); i++) {
    char c = input.charAt(i);
    if (c == '\\') out += "\\\\";
    else if (c == '"') out += "\\\"";
    else if (c == '\n') out += "\\n";
    else if (c == '\r') out += "\\r";
    else if ((uint8_t)c < 0x20) out += " ";
    else out += c;
  }
  return out;
}

// --- Helper: Send Structured JSON Response over RX2/TX2 ---
void sendPiResponse(String commandName, String status, String noteMessage) {
  String responseJson = "{\"cmd\":\"" + jsonEscape(commandName) +
                         "\",\"target\":\"esp32\",\"status\":\"" + jsonEscape(status) +
                         "\",\"note\":\"" + jsonEscape(noteMessage) + "\"}";
  Serial2.println(responseJson);
  Serial.print("[Debug Log] Sent to Pi: ");
  Serial.println(responseJson);
}

// --- Health Check 1: OLED I2C Probe ---
bool checkOLEDHealth() {
  Wire.beginTransmission(OLED_ADDR);
  return (Wire.endTransmission() == 0);
}

// --- Health Check 2: GPIO Output Hardware Verification ---
bool checkGPIOHealth(uint8_t pin, uint8_t expectedLevel) {
  digitalWrite(pin, expectedLevel);
  delayMicroseconds(10); // Short settling delay
  // Read back actual physical level from ESP32 GPIO peripheral register
  return (digitalRead(pin) == expectedLevel);
}

// --- Helper: Update OLED Display Safely ---
bool updateOLEDText(String msg) {
  if (!checkOLEDHealth()) {
    oledConnected = false;
    Serial.println("[Hardware Error] OLED disconnected!");
    return false;
  }

  if (!oledConnected) {
    display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR);
    oledConnected = true;
  }

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  
  if (msg.length() > 10) {
    display.setTextSize(1);
  } else {
    display.setTextSize(2);
  }
  
  display.setCursor(0, 0);
  display.println(msg);
  display.display();
  return true;
}

// --- Helper: Turn Off All Peripheral Outputs ---
void turnOffAll() {
  currentState = STATE_OFF;
  digitalWrite(LEFT_LED_PIN, LOW);
  digitalWrite(RIGHT_LED_PIN, LOW);
  digitalWrite(BUZZER_PIN, LOW);
}

void setup() {
  // 1. USB Serial Monitor (Debugging)
  Serial.begin(115200);

  // 2. Hardware Serial 2 (Pi USB Adapter via RX2/TX2)
  Serial2.begin(115200, SERIAL_8N1, RX2_PIN, TX2_PIN);

  // 3. Configure Output Pins
  pinMode(LEFT_LED_PIN, OUTPUT);
  pinMode(RIGHT_LED_PIN, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);

  turnOffAll();

  // 4. Initialize OLED Display
  Wire.begin(I2C_SDA, I2C_SCL);
  if (display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR)) { 
    oledConnected = true;
    updateOLEDText("ESP32\nRX2/TX2 INIT");
  } else {
    oledConnected = false;
    Serial.println(F("[Hardware Warning] OLED display not found on boot."));
  }
}

void processCommand(String cmd) {
  cmd.trim(); // Clean input string

  // Array to build hardware failure messages
  String hwErrors = "";

  // ===================================================================
  // Developer UI v0.2: explicit, idempotent state commands.
  // LED modes are mutually exclusive by this rig's existing design.
  // ===================================================================
  if (cmd == "HOOT") {
    // A momentary hoot must NOT toggle or cancel the indicator mode.
    if (!checkGPIOHealth(BUZZER_PIN, HIGH)) {
      digitalWrite(BUZZER_PIN, LOW);
      sendPiResponse(cmd, "error", "Buzzer GPIO check failed");
    } else {
      delay(300);
      digitalWrite(BUZZER_PIN, LOW);
      sendPiResponse(cmd, "ack", "Hooter sounded");
    }
    return;
  }

  if (cmd == "LEFT_INDICATOR_ON" || cmd == "RIGHT_INDICATOR_ON" ||
      cmd == "HAZARDS_ON" || cmd == "LEFT_INDICATOR_OFF" ||
      cmd == "RIGHT_INDICATOR_OFF" || cmd == "HAZARDS_OFF") {

    const bool isOff = cmd.endsWith("_OFF");
    SystemState wanted = STATE_OFF;
    if (cmd.startsWith("LEFT_")) wanted = STATE_FLASH_LEFT;
    else if (cmd.startsWith("RIGHT_")) wanted = STATE_FLASH_RIGHT;
    else wanted = STATE_FLASH_BOTH;

    if (isOff) {
      // OFF of an inactive function is a no-op, not a toggle.
      if (currentState == wanted) {
        turnOffAll();
      }
      sendPiResponse(cmd, "ack", "Requested indicator function off");
      return;
    }
    if (currentState == wanted) {
      sendPiResponse(cmd, "ack", "Requested indicator function already on");
      return;
    }

    // Disable other modes before enabling the requested mode.
    turnOffAll();
    bool healthy = true;
    if (wanted == STATE_FLASH_LEFT || wanted == STATE_FLASH_BOTH)
      healthy = checkGPIOHealth(LEFT_LED_PIN, HIGH) && healthy;
    if (wanted == STATE_FLASH_RIGHT || wanted == STATE_FLASH_BOTH)
      healthy = checkGPIOHealth(RIGHT_LED_PIN, HIGH) && healthy;
    digitalWrite(LEFT_LED_PIN, LOW);
    digitalWrite(RIGHT_LED_PIN, LOW);
    if (!healthy) {
      sendPiResponse(cmd, "error", "Indicator GPIO check failed");
      return;
    }
    currentState = wanted;
    // OLED failure does not imply LED action failure.
    sendPiResponse(cmd, "ack", "Requested indicator function on");
    return;
  }

  // ==========================================
  // COMMAND: BUZZER_ON (TOGGLE ENABLED)
  // ==========================================
  if (cmd == "BUZZER_ON") {
    if (currentState == STATE_BUZZER) {
      turnOffAll();
      updateOLEDText("Buzzer\nStopped");
      sendPiResponse("BUZZER_ON", "ack", "Buzzer toggled OFF");
      return;
    }

    turnOffAll();

    // Health Check Buzzer GPIO
    if (!checkGPIOHealth(BUZZER_PIN, HIGH)) {
      hwErrors += "[Buzzer GPIO Fault] ";
    }

    // Beep briefly
    delay(300);
    digitalWrite(BUZZER_PIN, LOW);

    currentState = STATE_BUZZER;
    bool oledOk = updateOLEDText("Buzzer: ON");
    if (!oledOk) hwErrors += "[OLED Disconnected] ";

    if (hwErrors.length() == 0) {
      sendPiResponse("BUZZER_ON", "ack", "Buzzer activated short beep");
    } else {
      sendPiResponse("BUZZER_ON", "error", hwErrors);
    }

  // ==========================================
  // COMMAND: LEFT_LED_FLASH (TOGGLE ENABLED)
  // ==========================================
  } else if (cmd == "LEFT_LED_FLASH") {
    if (currentState == STATE_FLASH_LEFT) {
      turnOffAll();
      updateOLEDText("Left LED\nStopped");
      sendPiResponse("LEFT_LED_FLASH", "ack", "Left LED flashing toggled OFF");
      return;
    }

    turnOffAll();

    // Health Check Left LED GPIO
    if (!checkGPIOHealth(LEFT_LED_PIN, HIGH)) {
      hwErrors += "[Left LED GPIO Fault] ";
    }
    digitalWrite(LEFT_LED_PIN, LOW);

    currentState = STATE_FLASH_LEFT;
    bool oledOk = updateOLEDText("Flash Left");
    if (!oledOk) hwErrors += "[OLED Disconnected] ";

    if (hwErrors.length() == 0) {
      sendPiResponse("LEFT_LED_FLASH", "ack", "Left LED flashing started");
    } else {
      sendPiResponse("LEFT_LED_FLASH", "error", hwErrors);
    }

  // ==========================================
  // COMMAND: RIGHT_LED_FLASH (TOGGLE ENABLED)
  // ==========================================
  } else if (cmd == "RIGHT_LED_FLASH") {
    if (currentState == STATE_FLASH_RIGHT) {
      turnOffAll();
      updateOLEDText("Right LED\nStopped");
      sendPiResponse("RIGHT_LED_FLASH", "ack", "Right LED flashing toggled OFF");
      return;
    }

    turnOffAll();

    // Health Check Right LED GPIO
    if (!checkGPIOHealth(RIGHT_LED_PIN, HIGH)) {
      hwErrors += "[Right LED GPIO Fault] ";
    }
    digitalWrite(RIGHT_LED_PIN, LOW);

    currentState = STATE_FLASH_RIGHT;
    bool oledOk = updateOLEDText("Flash Right");
    if (!oledOk) hwErrors += "[OLED Disconnected] ";

    if (hwErrors.length() == 0) {
      sendPiResponse("RIGHT_LED_FLASH", "ack", "Right LED flashing started");
    } else {
      sendPiResponse("RIGHT_LED_FLASH", "error", hwErrors);
    }

  // ==========================================
  // COMMAND: BOTH_LED_FLASH (TOGGLE ENABLED)
  // ==========================================
  } else if (cmd == "BOTH_LED_FLASH") {
    if (currentState == STATE_FLASH_BOTH) {
      turnOffAll();
      updateOLEDText("Both LEDs\nStopped");
      sendPiResponse("BOTH_LED_FLASH", "ack", "Both LEDs flashing toggled OFF");
      return;
    }

    turnOffAll();

    // Health Check Both LED GPIOs
    if (!checkGPIOHealth(LEFT_LED_PIN, HIGH)) hwErrors += "[Left LED Fault] ";
    if (!checkGPIOHealth(RIGHT_LED_PIN, HIGH)) hwErrors += "[Right LED Fault] ";
    
    digitalWrite(LEFT_LED_PIN, LOW);
    digitalWrite(RIGHT_LED_PIN, LOW);

    currentState = STATE_FLASH_BOTH;
    bool oledOk = updateOLEDText("Flash Both");
    if (!oledOk) hwErrors += "[OLED Disconnected] ";

    if (hwErrors.length() == 0) {
      sendPiResponse("BOTH_LED_FLASH", "ack", "Both LEDs flashing started");
    } else {
      sendPiResponse("BOTH_LED_FLASH", "error", hwErrors);
    }

  // ==========================================
  // COMMAND: OLED_TEXT:<msg>
  // ==========================================
  } else if (cmd.startsWith("OLED_TEXT:")) {
    String message = cmd.substring(10);
    
    bool oledOk = updateOLEDText(message);
    if (oledOk) {
      sendPiResponse("OLED_TEXT", "ack", "OLED updated with: " + message);
    } else {
      sendPiResponse("OLED_TEXT", "error", "Failed to update OLED: Display disconnected");
    }

  // ==========================================
  // UNKNOWN COMMAND
  // ==========================================
  } else if (cmd.length() > 0) {
    sendPiResponse(cmd, "error", "Unknown command");
  }
}

void loop() {
  // --- 1. Read commands coming from Pi via Serial2 (RX2/TX2) ---
  if (Serial2.available() > 0) {
    String command = Serial2.readStringUntil('\n');
    Serial.print("[Debug Log] Received from Pi: ");
    Serial.println(command);
    
    processCommand(command);
  }

  // --- 2. Non-blocking Flashing Timer ---
  unsigned long currentMillis = millis();
  if (currentMillis - previousMillis >= flashInterval) {
    previousMillis = currentMillis;
    ledState = !ledState;

    switch (currentState) {
      case STATE_FLASH_LEFT:
        digitalWrite(LEFT_LED_PIN, ledState ? HIGH : LOW);
        digitalWrite(RIGHT_LED_PIN, LOW);
        break;

      case STATE_FLASH_RIGHT:
        digitalWrite(LEFT_LED_PIN, LOW);
        digitalWrite(RIGHT_LED_PIN, ledState ? HIGH : LOW);
        break;

      case STATE_FLASH_BOTH:
        digitalWrite(LEFT_LED_PIN, ledState ? HIGH : LOW);
        digitalWrite(RIGHT_LED_PIN, ledState ? HIGH : LOW);
        break;

      case STATE_OFF:
      case STATE_BUZZER:
      default:
        digitalWrite(LEFT_LED_PIN, LOW);
        digitalWrite(RIGHT_LED_PIN, LOW);
        break;
    }
  }
}