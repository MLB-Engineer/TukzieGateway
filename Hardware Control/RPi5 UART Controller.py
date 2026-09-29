import json
import logging
import time
import serial

# Configure Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("PiUARTController")


class ESP32Controller:
    def __init__(self, port="/dev/ttyUSB0", baudrate=115200, timeout=2.0):
        """Initialize the Serial Connection to the ESP32."""
        self.port = port
        self.baudrate = baudrate
        self.timeout = timeout
        self.ser = None

    def connect(self):
        """Open the UART serial connection."""
        try:
            self.ser = serial.Serial(self.port, self.baudrate, timeout=self.timeout)
            # Give ESP32 time to reboot/reset if connected via DTR line
            time.sleep(2)
            self.ser.reset_input_buffer()
            logger.info(f"Connected to ESP32 on {self.port} at {self.baudrate} baud.")
        except serial.SerialException as e:
            logger.error(f"Failed to open serial port {self.port}: {e}")
            raise

    def send_command(self, command: str) -> dict | None:
        """
        Sends a command string to the ESP32 over UART and waits for a JSON ACK response.
        """
        if not self.ser or not self.ser.is_open:
            logger.error("Serial connection is not active.")
            return None

        # Clean command and attach newline expected by ESP32 (readStringUntil('\n'))
        formatted_cmd = f"{command.strip()}\n"
        
        try:
            # Clear stale bytes before sending
            self.ser.reset_input_buffer()
            
            # Send command
            logger.info(f"Sending Command -> '{command}'")
            self.ser.write(formatted_cmd.encode("utf-8"))
            self.ser.flush()

            # Read response line
            raw_response = self.ser.readline().decode("utf-8", errors="replace").strip()

            if not raw_response:
                logger.warning("No response received from ESP32 (Timeout).")
                return None

            # Parse JSON ACK from ESP32
            try:
                response_json = json.loads(raw_response)
                logger.info(f"Received ACK <- {json.dumps(response_json, indent=2)}")
                return response_json
            except json.JSONDecodeError:
                logger.warning(f"Received raw non-JSON text: {raw_response}")
                return {"status": "raw", "data": raw_response}

        except serial.SerialException as e:
            logger.error(f"UART Communication error: {e}")
            return None

    def close(self):
        """Close the serial port cleanly."""
        if self.ser and self.ser.is_open:
            self.ser.close()
            logger.info("Serial connection closed.")


def main():
    # Update port as needed ('/dev/ttyUSB0', '/dev/ttyACM0', or '/dev/serial0')
    PORT = "/dev/ttyUSB0"
    BAUD = 115200

    controller = ESP32Controller(port=PORT, baudrate=BAUD)

    try:
        controller.connect()
    except Exception:
        print("\nExiting: Could not establish serial connection.")
        return

    print("\n" + "=" * 50)
    print("      ESP32 UART COMMAND TERMINAL READY")
    print("=" * 50)
    print("Available Preset Commands:")
    print("  1. BUZZER_ON")
    print("  2. LEFT_LED_FLASH")
    print("  3. RIGHT_LED_FLASH")
    print("  4. BOTH_LED_FLASH")
    print("  5. OLED_TEXT:<your message>")
    print("Type 'exit' or 'quit' to close.")
    print("=" * 50 + "\n")

    try:
        while True:
            cmd = input("\nEnter Command > ").strip()

            if cmd.lower() in ["exit", "quit"]:
                print("Exiting application...")
                break

            if not cmd:
                continue

            # Route interactive numbers to corresponding command strings
            if cmd == "1":
                cmd = "BUZZER_ON"
            elif cmd == "2":
                cmd = "LEFT_LED_FLASH"
            elif cmd == "3":
                cmd = "RIGHT_LED_FLASH"
            elif cmd == "4":
                cmd = "BOTH_LED_FLASH"
            elif cmd == "5":
                msg = input("Enter OLED text message: ")
                cmd = f"OLED_TEXT:{msg}"

            controller.send_command(cmd)

    except KeyboardInterrupt:
        print("\nProgram interrupted by user.")
    finally:
        controller.close()


if __name__ == "__main__":
    main()