#include <math.h>
#include <DHT.h>
#include <SoftwareSerial.h>

constexpr uint8_t BUTTON_PIN = 2;
constexpr uint8_t RELAY_PIN = 7;
constexpr uint8_t BUTTON_LED_PIN = 13;
constexpr uint8_t DHT_PIN = 8;
constexpr uint8_t BLUETOOTH_RX_PIN = 10;
constexpr uint8_t BLUETOOTH_TX_PIN = 11;
constexpr uint8_t RELAY_ON_LEVEL = LOW;
constexpr uint8_t RELAY_OFF_LEVEL = HIGH;
constexpr unsigned long BUTTON_DEBOUNCE_MS = 50;
constexpr unsigned long DHT_READ_INTERVAL_MS = 2000;

SoftwareSerial bluetooth(BLUETOOTH_RX_PIN, BLUETOOTH_TX_PIN);
DHT dht(DHT_PIN, DHT11);

bool relayIsOn = false;
bool buttonIsPressed = false;
bool lastRawButtonState = false;
unsigned long lastButtonChangeAt = 0;
unsigned long lastDhtReadAt = 0;

void publishRelayState();
void publishDhtReading();
void setRelayState(bool turnOn);
void updateButton();
void processBluetoothCommands();

void publishRelayState() {
  const char state = relayIsOn ? '1' : '0';
  bluetooth.print(F("STATE:"));
  bluetooth.println(state);
  Serial.print(F("STATE:"));
  Serial.println(state);
}

// Send one complete line; ERR distinguishes a failed read from missing data.
void publishDhtReading() {
  const float humidity = dht.readHumidity();
  const float temperature = dht.readTemperature();
  if (isnan(temperature) || isnan(humidity) || temperature < 0 ||
      temperature > 50 || humidity < 0 || humidity > 100) {
    bluetooth.println(F("DHT:ERR"));
    Serial.println(F("DHT:ERR"));
    return;
  }

  bluetooth.print(F("DHT:"));
  bluetooth.print(temperature, 1);
  bluetooth.print(',');
  bluetooth.println(humidity, 1);
  Serial.print(F("DHT:"));
  Serial.print(temperature, 1);
  Serial.print(',');
  Serial.println(humidity, 1);
}

void setRelayState(bool turnOn) {
  relayIsOn = turnOn;
  digitalWrite(RELAY_PIN, relayIsOn ? RELAY_ON_LEVEL : RELAY_OFF_LEVEL);
  publishRelayState();
}

void updateButton() {
  const bool rawButtonState = digitalRead(BUTTON_PIN) == LOW;
  if (rawButtonState != lastRawButtonState) {
    lastRawButtonState = rawButtonState;
    lastButtonChangeAt = millis();
  }

  if (millis() - lastButtonChangeAt >= BUTTON_DEBOUNCE_MS &&
      rawButtonState != buttonIsPressed) {
    buttonIsPressed = rawButtonState;
    if (buttonIsPressed) {
      setRelayState(!relayIsOn);
    }
  }

  digitalWrite(BUTTON_LED_PIN, buttonIsPressed ? HIGH : LOW);
}

void processBluetoothCommands() {
  while (bluetooth.available() > 0) {
    const char command = static_cast<char>(bluetooth.read());
    Serial.print(F("Bluetooth: "));
    Serial.println(command);

    switch (command) {
      case '1':
        setRelayState(true);
        break;
      case '0':
        setRelayState(false);
        break;
      case '?':
        publishRelayState();
        break;
      case '\r':
      case '\n':
        break;
      default:
        Serial.println(F("Unbekannter Bluetooth-Befehl."));
        break;
    }
  }
}

void setup() {
  digitalWrite(RELAY_PIN, RELAY_OFF_LEVEL);
  pinMode(RELAY_PIN, OUTPUT);
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  pinMode(BUTTON_LED_PIN, OUTPUT);
  dht.begin();

  lastRawButtonState = digitalRead(BUTTON_PIN) == LOW;
  buttonIsPressed = lastRawButtonState;
  lastDhtReadAt = millis();

  bluetooth.begin(9600);
  Serial.begin(9600);
  digitalWrite(BUTTON_LED_PIN, buttonIsPressed ? HIGH : LOW);
  publishRelayState();
}

void loop() {
  updateButton();
  processBluetoothCommands();

  // millis() keeps button and Bluetooth handling responsive between samples.
  const unsigned long now = millis();
  if (now - lastDhtReadAt >= DHT_READ_INTERVAL_MS) {
    lastDhtReadAt = now;
    publishDhtReading();
  }
}
