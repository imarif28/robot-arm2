/*
 * ============================================
 *  Robot Arm Controller — ESP32 + MQTT
 * ============================================
 *  Board   : ESP32
 *  Libraries: ESP32Servo, PubSubClient, WiFiManager, Preferences
 *
 *  Servo mapping:
 *    Index 0 → Base     → Pin 27 → 360° → initial 90
 *    Index 1 → Shoulder → Pin 26 → 180° → initial 90
 *    Index 2 → Elbow    → Pin 25 → 180° → initial 90
 *    Index 3 → Gripper  → Pin 33 → 180° → initial 90
 *
 *  MQTT topic : robot/arm/control
 *  Payload    : "nama_servo:angle"  (e.g. "base:90")
 * ============================================
 */

#include <WiFi.h>
#include <WiFiManager.h>
#include <PubSubClient.h>
#include <ESP32Servo.h>
#include <Preferences.h>

// ─── Servo Configuration ───────────────────────────────────
struct ServoConfig {
  Servo servo;
  int pin;
  String name;
  int initialPosition;
  int maxAngle;  // 360 for base, 180 for others
};

ServoConfig servos[] = {
  { Servo(), 27, "base",     90, 360 },
  { Servo(), 26, "shoulder", 90, 180 },
  { Servo(), 25, "elbow",    90, 180 },
  { Servo(), 33, "gripper",  90, 180 },
};
const int SERVO_COUNT = sizeof(servos) / sizeof(servos[0]);

// ─── MQTT Configuration ────────────────────────────────────
#define MQTT_TOPIC        "robot/arm/control"
#define MQTT_STATUS_TOPIC "robot/arm/status"

char mqttBrokerIP[40]   = "10.101.243.137";  // default broker IP
char mqttPort[6]        = "1883";            // default port

WiFiClient   espClient;
PubSubClient mqttClient(espClient);
Preferences  preferences;

// WiFiManager custom parameters
WiFiManagerParameter customMqttIP("mqtt_ip", "MQTT Broker IP", mqttBrokerIP, 40);
WiFiManagerParameter customMqttPort("mqtt_port", "MQTT Port", mqttPort, 6);

// ─── Reconnect timing ──────────────────────────────────────
unsigned long lastReconnectAttempt = 0;
const unsigned long RECONNECT_INTERVAL = 5000;  // 5 seconds

// Flag to save config when WiFiManager sets new params
bool shouldSaveConfig = false;

// ════════════════════════════════════════════════════════════
//  MQTT CALLBACK — parse payload "servo_name:angle"
// ════════════════════════════════════════════════════════════
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  // Build string from payload
  String message = "";
  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }

  Serial.print("[MQTT] Received on ");
  Serial.print(topic);
  Serial.print(": ");
  Serial.println(message);

  // Parse "nama_servo:angle"
  int separatorIndex = message.indexOf(':');
  if (separatorIndex == -1) {
    Serial.println("[MQTT] ERROR: Invalid format. Expected 'name:angle'");
    return;
  }

  String servoName = message.substring(0, separatorIndex);
  int angle = message.substring(separatorIndex + 1).toInt();

  servoName.trim();
  servoName.toLowerCase();

  // Find matching servo and write angle
  bool found = false;
  for (int i = 0; i < SERVO_COUNT; i++) {
    if (servoName == servos[i].name) {
      found = true;

      // Validate angle range
      if (angle < 0 || angle > servos[i].maxAngle) {
        Serial.print("[MQTT] ERROR: Angle ");
        Serial.print(angle);
        Serial.print(" out of range for ");
        Serial.print(servos[i].name);
        Serial.print(" (0-");
        Serial.print(servos[i].maxAngle);
        Serial.println(")");
        return;
      }

      servos[i].servo.write(angle);
      Serial.print("[SERVO] ");
      Serial.print(servos[i].name);
      Serial.print(" → ");
      Serial.println(angle);
      break;
    }
  }

  if (!found) {
    Serial.print("[MQTT] ERROR: Unknown servo name '");
    Serial.print(servoName);
    Serial.println("'");
  }
}

// ════════════════════════════════════════════════════════════
//  MQTT CONNECT / RECONNECT
// ════════════════════════════════════════════════════════════

/// Attempt to connect to the MQTT broker. Returns true on success.
bool mqttConnect() {
  Serial.print("[MQTT] Connecting to ");
  Serial.print(mqttBrokerIP);
  Serial.print(":");
  Serial.print(mqttPort);
  Serial.println("...");

  // Generate a unique client ID
  String clientId = "ESP32Arm-" + String(random(0xffff), HEX);

  // Connect with LWT: publish "offline" to status topic when disconnected unexpectedly
  if (mqttClient.connect(clientId.c_str(), MQTT_STATUS_TOPIC, 1, true, "offline")) {
    Serial.println("[MQTT] Connected!");

    // Publish "online" status (retained) so Flutter app knows ESP32 is alive
    mqttClient.publish(MQTT_STATUS_TOPIC, "online", true);
    Serial.println("[MQTT] Published 'online' to status topic");

    mqttClient.subscribe(MQTT_TOPIC);
    Serial.print("[MQTT] Subscribed to topic: ");
    Serial.println(MQTT_TOPIC);
    return true;
  } else {
    Serial.print("[MQTT] Failed, rc=");
    Serial.print(mqttClient.state());
    Serial.println(" — will retry in 5s");
    return false;
  }
}

// ════════════════════════════════════════════════════════════
//  PREFERENCES — Save / Load MQTT config from NVS
// ════════════════════════════════════════════════════════════

/// Load MQTT broker IP and port from NVS (Preferences)
void loadMqttConfig() {
  preferences.begin("mqtt", true);  // read-only
  String savedIP   = preferences.getString("broker_ip", mqttBrokerIP);
  String savedPort = preferences.getString("broker_port", mqttPort);
  preferences.end();

  savedIP.toCharArray(mqttBrokerIP, sizeof(mqttBrokerIP));
  savedPort.toCharArray(mqttPort, sizeof(mqttPort));

  Serial.print("[CONFIG] Loaded MQTT Broker: ");
  Serial.print(mqttBrokerIP);
  Serial.print(":");
  Serial.println(mqttPort);
}

/// Save MQTT broker IP and port to NVS (Preferences)
void saveMqttConfig() {
  preferences.begin("mqtt", false);  // read-write
  preferences.putString("broker_ip", mqttBrokerIP);
  preferences.putString("broker_port", mqttPort);
  preferences.end();

  Serial.print("[CONFIG] Saved MQTT Broker: ");
  Serial.print(mqttBrokerIP);
  Serial.print(":");
  Serial.println(mqttPort);
}

// ════════════════════════════════════════════════════════════
//  WiFiManager save-config callback
// ════════════════════════════════════════════════════════════
void saveConfigCallback() {
  Serial.println("[WIFI] Config save requested");
  shouldSaveConfig = true;
}

// ════════════════════════════════════════════════════════════
//  SERVO SETUP
// ════════════════════════════════════════════════════════════

/// Attach all servos to their pins and write initial positions
void setupServos() {
  for (int i = 0; i < SERVO_COUNT; i++) {
    servos[i].servo.attach(servos[i].pin);
    servos[i].servo.write(servos[i].initialPosition);
    Serial.print("[SERVO] ");
    Serial.print(servos[i].name);
    Serial.print(" attached to pin ");
    Serial.print(servos[i].pin);
    Serial.print(" → initial ");
    Serial.println(servos[i].initialPosition);
  }
}

// ════════════════════════════════════════════════════════════
//  WiFi SETUP via WiFiManager
// ════════════════════════════════════════════════════════════

/// Initialize WiFi using WiFiManager (auto AP mode if no saved credentials)
void setupWiFi() {
  WiFiManager wm;

  // Set callback for when config is saved
  wm.setSaveConfigCallback(saveConfigCallback);

  // Add custom MQTT parameters to the WiFiManager portal
  wm.addParameter(&customMqttIP);
  wm.addParameter(&customMqttPort);

  // Set timeout for AP portal (5 minutes)
  wm.setConfigPortalTimeout(300);

  Serial.println("[WIFI] Starting WiFiManager...");
  Serial.println("[WIFI] If no saved credentials, connect to AP 'RobotArm-Setup'");

  // autoConnect will:
  //  - Try saved credentials first
  //  - If fail, open an AP named "RobotArm-Setup" with captive portal
  bool connected = wm.autoConnect("RobotArm-Setup");

  if (!connected) {
    Serial.println("[WIFI] Failed to connect! Restarting...");
    delay(3000);
    ESP.restart();
  }

  Serial.println("[WIFI] Connected!");
  Serial.print("[WIFI] IP Address: ");
  Serial.println(WiFi.localIP());

  // If user entered new MQTT config via the portal, save it
  if (shouldSaveConfig) {
    strncpy(mqttBrokerIP, customMqttIP.getValue(), sizeof(mqttBrokerIP) - 1);
    strncpy(mqttPort, customMqttPort.getValue(), sizeof(mqttPort) - 1);
    saveMqttConfig();
  }
}

// ════════════════════════════════════════════════════════════
//  SETUP
// ════════════════════════════════════════════════════════════
void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println();
  Serial.println("========================================");
  Serial.println("  Robot Arm Controller — ESP32 + MQTT");
  Serial.println("========================================");

  // 1. Setup servos
  setupServos();

  // 2. Load saved MQTT config from NVS
  loadMqttConfig();

  // 3. Connect WiFi via WiFiManager
  setupWiFi();

  // 4. Configure MQTT client
  int port = atoi(mqttPort);
  mqttClient.setServer(mqttBrokerIP, port);
  mqttClient.setCallback(mqttCallback);

  // 5. Initial MQTT connection attempt
  mqttConnect();
}

// ════════════════════════════════════════════════════════════
//  LOOP — maintain MQTT connection
// ════════════════════════════════════════════════════════════
void loop() {
  // If MQTT disconnected, try to reconnect periodically
  if (!mqttClient.connected()) {
    unsigned long now = millis();
    if (now - lastReconnectAttempt > RECONNECT_INTERVAL) {
      lastReconnectAttempt = now;
      Serial.println("[MQTT] Connection lost. Reconnecting...");
      mqttConnect();
    }
  } else {
    // Process incoming MQTT messages
    mqttClient.loop();
  }
}