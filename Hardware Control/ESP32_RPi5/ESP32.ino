#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// --- OLED Configuration ---
#define SCREEN_WIDTH 128 
#define SCREEN_HEIGHT 64 
#define I2C_SDA 21
#define I2C_SCL 18
#define OLED_RESET -1 
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// --- Pin Definitions ---
#define LEFT_LED_PIN   4
#define RIGHT_LED_PIN  15
#define BUZZER_PIN     5

// --- Flashing Mode Enums ---
enum FlashMode {
  FLASH_OFF,
  FLASH_LEFT,
  FLASH_RIGHT,
  FLASH_BOTH
};

FlashMode currentFlashMode = FLASH_OFF;

// --- Timing Variables for Non-blocking LED Flashing ---
unsigned long previousMillis = 0;
const long flashInterval = 500; // 500ms ON, 500ms OFF
bool ledState = false;

// --- Helper: Send Structured ACK over Serial ---
void sendAck(String commandName, String noteMessage) {
  // Serial output formatted to match Python JSON ACK responder
  String ackJson = "{\"cmd\":\"" + commandName + 
                   "\",\"target\":\"esp32\",\"status\":\"ack\",\"note\":\"" + 
                   noteMessage + "\"}";
  Serial.println(ackJson);
}

// --- Helper: Update OLED Display Text ---
void updateOLEDText(String msg) {
  display.clearDisplay();
  display.setTextSize(2);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  
  // Wrap text cleanly if long or handle multiple lines
  if (msg.length() > 10) {
    display.setTextSize(1);
  }
  display.println(msg);
  display.display();
}

void setup() {
  // Initialize Serial (UART)
  Serial.begin(115200);

  // Initialize GPIO Pins
  pinMode(LEFT_LED_PIN, OUTPUT);
  pinMode(RIGHT_LED_PIN, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);

  digitalWrite(LEFT_LED_PIN, LOW);
  digitalWrite(RIGHT_LED_PIN, LOW);
  digitalWrite(BUZZER_PIN, LOW);

  // Initialize I2C Bus with Custom Pins
  Wire.begin(I2C_SDA, I2C_SCL);

  // Initialize SSD1306 Display
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) { 
    Serial.println(F("{\"error\":\"SSD1306 OLED initialization failed\"}"));
    for(;;); // Freeze on display error
  }
  
  updateOLEDText("ESP32\nReady...");
  delay(1000);
}

void processCommand(String cmd) {
  cmd.trim(); // Clean trailing newlines/spaces

  if (cmd == "BUZZER_ON") {
    currentFlashMode = FLASH_OFF;
    digitalWrite(LEFT_LED_PIN, LOW);
    digitalWrite(RIGHT_LED_PIN, LOW);

    // Beep buzzer
    digitalWrite(BUZZER_PIN, HIGH);
    delay(200); // Short pulse
    digitalWrite(BUZZER_PIN, LOW);

    updateOLEDText("Buzzer: ON");
    sendAck("BUZZER_ON", "Buzzer activated short beep");

  } else if (cmd == "LEFT_LED_FLASH") {
    currentFlashMode = FLASH_LEFT;
    digitalWrite(RIGHT_LED_PIN, LOW);
    
    updateOLEDText("Flashing\nLeft LED");
    sendAck("LEFT_LED_FLASH", "Left LED flashing started");

  } else if (cmd == "RIGHT_LED_FLASH") {
    currentFlashMode = FLASH_RIGHT;
    digitalWrite(LEFT_LED_PIN, LOW);
    
    updateOLEDText("Flashing\nRight LED");
    sendAck("RIGHT_LED_FLASH", "Right LED flashing started");

  } else if (cmd == "BOTH_LED_FLASH") {
    currentFlashMode = FLASH_BOTH;
    
    updateOLEDText("Flashing\nBoth LEDs");
    sendAck("BOTH_LED_FLASH", "Both LEDs flashing started");

  } else if (cmd.startsWith("OLED_TEXT:")) {
    // Extract text after prefix
    String message = cmd.substring(10);
    
    updateOLEDText(message);
    sendAck("OLED_TEXT", "OLED updated with text: " + message);

  } else if (cmd.length() > 0) {
    // Unrecognized Command
    String errJson = "{\"cmd\":\"" + cmd + "\",\"status\":\"error\",\"note\":\"Unknown command\"}";
    Serial.println(errJson);
  }
}

void loop() {
  // 1. Process Incoming Commands via UART (Serial)
  if (Serial.available() > 0) {
    String incomingCommand = Serial.readStringUntil('\n');
    processCommand(incomingCommand);
  }

  // 2. Non-blocking LED Flashing Handler
  unsigned long currentMillis = millis();
  if (currentMillis - previousMillis >= flashInterval) {
    previousMillis = currentMillis;
    ledState = !ledState; // Toggle LED state

    switch (currentFlashMode) {
      case FLASH_LEFT:
        digitalWrite(LEFT_LED_PIN, ledState ? HIGH : LOW);
        digitalWrite(RIGHT_LED_PIN, LOW);
        break;

      case FLASH_RIGHT:
        digitalWrite(LEFT_LED_PIN, LOW);
        digitalWrite(RIGHT_LED_PIN, ledState ? HIGH : LOW);
        break;

      case FLASH_BOTH:
        digitalWrite(LEFT_LED_PIN, ledState ? HIGH : LOW);
        digitalWrite(RIGHT_LED_PIN, ledState ? HIGH : LOW);
        break;

      case FLASH_OFF:
      default:
        break;
    }
  }
}