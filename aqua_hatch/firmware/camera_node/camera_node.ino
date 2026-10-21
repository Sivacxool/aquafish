// Reference firmware: requires board-specific config.h, certificates and hardware testing.
// Libraries: Arduino-ESP32 3.x (esp_camera included), PubSubClient 2.8, ArduinoJson 7.x.
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <time.h>
#include "esp_camera.h"
#include "config.h"

#if !CAMERA_PINS_CONFIRMED
#error "Fill camera GPIOs from the exact board schematic and confirm in config.h."
#endif

WiFiClientSecure mqttTls;
PubSubClient mqtt(mqttTls);
Preferences jobs;
String prefix = String("incubator/v1/") + DEVICE_ID + "/camera/";
String pendingId, pendingUrl, pendingToken;
time_t pendingDeadline = 0;
size_t pendingMaxBytes = 0;
bool cameraReady = false;
uint32_t lastHeartbeat = 0, lastConnectAttempt = 0;

bool safeId(const String &id) {
  if (id.length() == 0 || id.length() > 80) return false;
  for (size_t i = 0; i < id.length(); ++i) {
    char c = id[i];
    if (!(isalnum((unsigned char)c) || c == '-' || c == '_')) return false;
  }
  return true;
}

void availability() {
  JsonDocument doc;
  doc["camera_id"] = CAMERA_ID;
  doc["status"] = cameraReady ? "online" : "offline";
  String text;
  serializeJson(doc, text);
  mqtt.publish((prefix + "availability").c_str(), text.c_str(), true);
  lastHeartbeat = millis();
}

void result(const String &id, const char *status, const String &message) {
  JsonDocument doc;
  doc["camera_id"] = CAMERA_ID;
  doc["capture_id"] = id;
  doc["status"] = status;
  doc["message"] = message;
  String text;
  serializeJson(doc, text);
  mqtt.publish((prefix + "result").c_str(), text.c_str(), false);
}

bool seen(const String &id) {
  for (int i = 0; i < 8; ++i) {
    if (jobs.getString((String("id") + i).c_str(), "") == id) return true;
  }
  return false;
}

void remember(const String &id) {
  unsigned int slot = jobs.getUInt("next", 0) % 8;
  jobs.putString((String("id") + slot).c_str(), id);
  jobs.putUInt("next", (slot + 1) % 8);
}

void onCommand(char *topic, byte *payload, unsigned int length) {
  if (String(topic) != prefix + "command" || length > 2048) return;
  JsonDocument doc;
  if (deserializeJson(doc, payload, length)) return;
  if (doc["schema_version"].as<int>() != 1 || doc["action"].as<String>() != "capture" ||
      doc["camera_id"].as<String>() != CAMERA_ID) return;
  String id = doc["capture_id"].as<String>();
  if (!safeId(id) || seen(id) || id == pendingId) return;
  time_t deadline = doc["expires_at_unix"].as<int64_t>();
  time_t now = time(nullptr);
  if (now < 1700000000 || deadline <= now || deadline > now + 100) return;
  if (pendingId.length() || !cameraReady) {
    result(id, "failed", "Camera busy or unavailable");
    return;
  }
  String expected = String(GATEWAY_ORIGIN) + "/api/v1/devices/" + DEVICE_ID +
                    "/camera/captures/" + id + "/image";
  if (!expected.startsWith("https://") || doc["upload_url"].as<String>() != expected) return;
  size_t limit = doc["max_bytes"].as<size_t>();
  String token = doc["upload_token"].as<String>();
  if (!limit || limit > 8 * 1024 * 1024 || token.length() < 32 || token.length() > 128) return;
  pendingId = id;
  pendingUrl = expected;
  pendingToken = token;
  pendingDeadline = deadline;
  pendingMaxBytes = limit;
}

bool initCamera() {
  if (!psramFound()) return false;
  camera_config_t c = {};
  c.pin_pwdn = CAM_PIN_PWDN;
  c.pin_reset = CAM_PIN_RESET;
  c.pin_xclk = CAM_PIN_XCLK;
  c.pin_sccb_sda = CAM_PIN_SIOD;
  c.pin_sccb_scl = CAM_PIN_SIOC;
  c.pin_d0 = CAM_PIN_D0; c.pin_d1 = CAM_PIN_D1;
  c.pin_d2 = CAM_PIN_D2; c.pin_d3 = CAM_PIN_D3;
  c.pin_d4 = CAM_PIN_D4; c.pin_d5 = CAM_PIN_D5;
  c.pin_d6 = CAM_PIN_D6; c.pin_d7 = CAM_PIN_D7;
  c.pin_vsync = CAM_PIN_VSYNC;
  c.pin_href = CAM_PIN_HREF;
  c.pin_pclk = CAM_PIN_PCLK;
  c.xclk_freq_hz = 20000000;
  c.ledc_timer = LEDC_TIMER_0;
  c.ledc_channel = LEDC_CHANNEL_0;
  c.pixel_format = PIXFORMAT_JPEG;
  c.frame_size = CAMERA_FRAME_SIZE;
  c.jpeg_quality = 10;
  c.fb_count = 1;
  c.fb_location = CAMERA_FB_IN_PSRAM;
  c.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  return esp_camera_init(&c) == ESP_OK;
}

void takeAndUpload() {
  String id = pendingId;
  remember(id); // Persist before capture: replay after reboot cannot take another photo.
  // Discard queued frames so an old buffer is not used as the new capture.
  for (int i = 0; i < 2; ++i) {
    camera_fb_t *old = esp_camera_fb_get();
    if (old) esp_camera_fb_return(old);
  }
  camera_fb_t *frame = esp_camera_fb_get();
  if (!frame || frame->format != PIXFORMAT_JPEG || frame->len > pendingMaxBytes) {
    result(id, "failed", "Cannot acquire a valid JPEG frame");
  } else {
    int code = -1;
    // Retry the SAME frame if the response was lost; never recapture on retry.
    for (int attempt = 0; attempt < 2 && time(nullptr) < pendingDeadline; ++attempt) {
      WiFiClientSecure uploadTls;
      uploadTls.setCACert(HTTPS_ROOT_CA);
      HTTPClient http;
      http.setConnectTimeout(8000);
      http.setTimeout(18000);
      http.setFollowRedirects(HTTPC_DISABLE_FOLLOW_REDIRECTS);
      if (!http.begin(uploadTls, pendingUrl)) break;
      http.addHeader("Content-Type", "image/jpeg");
      http.addHeader("Authorization", "Bearer " + pendingToken);
      code = http.POST(frame->buf, frame->len);
      http.end();
      if (code == 200 || (code >= 400 && code < 500)) break;
      mqtt.loop();
    }
    if (code == 200) result(id, "captured", "JPEG uploaded");
    else result(id, "failed", "Upload failed (HTTP " + String(code) + ")");
  }
  if (frame) esp_camera_fb_return(frame);
  pendingId = ""; pendingToken = ""; pendingUrl = "";
  availability();
}

void setup() {
  Serial.begin(115200);
  jobs.begin("camera-jobs", false);
  cameraReady = initCamera();
  Serial.println(cameraReady ? "Camera initialized" : "Camera init failed; check pins and PSRAM");
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  configTime(0, 0, "pool.ntp.org", "time.google.com");
  mqttTls.setCACert(MQTT_ROOT_CA);
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setBufferSize(3072);
  mqtt.setKeepAlive(60);
  mqtt.setSocketTimeout(8);
  mqtt.setCallback(onCommand);
}

void loop() {
  if (WiFi.status() != WL_CONNECTED || time(nullptr) < 1700000000) {
    delay(50);
    return;
  }
  if (!mqtt.connected()) {
    if (millis() - lastConnectAttempt >= 5000) {
      lastConnectAttempt = millis();
      String will = String("{\"camera_id\":\"") + CAMERA_ID + "\",\"status\":\"offline\"}";
      if (mqtt.connect(CAMERA_ID, MQTT_USER, MQTT_PASSWORD, (prefix + "availability").c_str(), 1, true, will.c_str())) {
        mqtt.subscribe((prefix + "command").c_str(), 1);
        availability();
      }
    }
    delay(10);
    return;
  }
  mqtt.loop();
  if (pendingId.length()) {
    if (time(nullptr) >= pendingDeadline) {
      result(pendingId, "failed", "Capture deadline expired");
      pendingId = ""; pendingToken = ""; pendingUrl = "";
    } else takeAndUpload();
  }
  if (millis() - lastHeartbeat >= 15000) availability();
  delay(5);
}
