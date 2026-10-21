// AquaHatch local HTTPS server. No peripheral GPIO is driven in this revision.
// Arduino-ESP32 3.3.12, ArduinoJson 7.4.3, ESP32-S3 16 MB / OPI PSRAM 8 MB.
#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <esp_https_server.h>
#include <sys/time.h>
#include <math.h>
#include "device_private.h"

static const char VERSION[] = "0.6.0-local";
Preferences prefs;
httpd_handle_t httpsServer = nullptr;
bool tlsReady = false, wasConnected = false;
uint32_t lastWifiAttempt = 0, commandCount = 0;
volatile uint16_t lastDisconnectReason = 0;
volatile uint32_t disconnectCount = 0;
uint16_t firstDisconnectReasons[12] = {};
volatile uint8_t firstReasonCount = 0;
String serialLine;
bool serialOverflow = false;
float temperatureTarget = 28, phMinimum = 6.5, phMaximum = 8.5, flowTarget = 2.4;
struct CachedCommand { String id, body, reply; } cache[8];
uint8_t cacheIndex = 0;
void startTls();
esp_err_t sendJson(httpd_req_t *req, const char *status, const JsonDocument &doc);
esp_err_t error(httpd_req_t *req, const char *status, const char *message);
#include "wifi_setup.h"

String nowIso() {
  time_t now = time(nullptr);
  if (now < 1735689600) return "";
  struct tm utc; gmtime_r(&now, &utc);
  char text[32]; strftime(text, sizeof(text), "%Y-%m-%dT%H:%M:%SZ", &utc);
  return String(text);
}
void configJson(JsonObject obj) {
  obj["temperature_target"] = temperatureTarget;
  obj["ph_minimum"] = phMinimum; obj["ph_maximum"] = phMaximum;
  obj["flow_target"] = flowTarget;
}
void snapshot(JsonDocument &doc) {
  doc["device_id"] = DEVICE_ID;
  doc["backend"] = "esp32-local"; doc["protocol_version"] = 1;
  doc["uptime_ms"] = millis(); doc["command_count"] = commandCount;
  doc["capabilities"]["hardware_control"] = false;
  doc["capabilities"]["camera"] = false;
  doc["capabilities"]["ai"] = false;
  configJson(doc["config"].to<JsonObject>());
  JsonObject t = doc["telemetry"].to<JsonObject>();
  t["timestamp"] = nowIso(); t["firmware_version"] = VERSION;
  t["temperature_c"] = nullptr; t["ph"] = nullptr;
  t["flow_l_min"] = nullptr; t["water_level_ok"] = nullptr;
  t["ph_calibrated"] = false; t["simulated"] = false;
  t["device_online"] = true; t["hardware_ready"] = false;
  t["hardware_message"] = "บอร์ดเชื่อมต่อแล้ว ยังไม่ได้ติดตั้งเซนเซอร์และตั้งค่าขาควบคุม";
  t["wifi_rssi"] = WiFi.RSSI(); t["mode"] = "setup";
  t["outputs"].to<JsonObject>();
}
void serialStatus(const char *type = "status") {
  JsonDocument doc;
  doc["type"] = type; doc["device_id"] = DEVICE_ID;
  doc["firmware"] = VERSION; doc["chip"] = ESP.getChipModel();
  doc["flash_bytes"] = ESP.getFlashChipSize(); doc["psram_bytes"] = ESP.getPsramSize();
  doc["connected"] = WiFi.status() == WL_CONNECTED;
  doc["ssid"] = WiFi.SSID(); doc["ip"] = WiFi.localIP().toString();
  doc["tls_ready"] = tlsReady; doc["uptime_ms"] = millis();
  doc["free_heap"] = ESP.getFreeHeap(); doc["command_count"] = commandCount;
  doc["wifi_status"] = (int)WiFi.status();
  doc["disconnect_reason"] = (int)lastDisconnectReason;
  doc["disconnect_count"] = (uint32_t)disconnectCount;
  JsonArray reasons = doc["first_disconnect_reasons"].to<JsonArray>();
  for (uint8_t i=0; i<firstReasonCount; i++) reasons.add(firstDisconnectReasons[i]);
  String saved,password; provisioning::loadSaved(saved,password);
  doc["credentials_saved"] = !saved.isEmpty();
  doc["ap_ssid"] = provisioning::apName; doc["ap_active"] = provisioning::apActive;
  serializeJson(doc, Serial); Serial.println();
}
void wifiDiagnostics() {
  String target,password; provisioning::loadSaved(target,password);
  String trimmed = target; trimmed.trim();
  JsonDocument doc; doc["type"] = "wifi_diagnostics";
  doc["credentials_saved"] = target.length() > 0;
  doc["saved_ssid_bytes"] = target.length();
  doc["configured_ssid"] = target;
  doc["wifi_status"] = (int)WiFi.status();
  doc["disconnect_reason"] = (int)lastDisconnectReason;
  doc["target_seen"] = false; doc["trimmed_target_seen"] = false;
  doc["case_mismatch_seen"] = false;
  bool alreadyConnected = WiFi.status() == WL_CONNECTED;
  if (!alreadyConnected) {
    WiFi.setAutoReconnect(false);
    WiFi.disconnect(false,false);
    delay(500);
  }
  int found = WiFi.scanNetworks(false,true);
  doc["scan_count"] = found;
  JsonArray networks = doc["networks"].to<JsonArray>();
  for (int i=0; i<found; i++) {
    String seen = WiFi.SSID(i);
    if (!seen.isEmpty() && networks.size() < 24) {
      JsonObject item = networks.add<JsonObject>();
      item["ssid"] = seen; item["rssi"] = WiFi.RSSI(i);
      item["channel"] = WiFi.channel(i); item["auth"] = (int)WiFi.encryptionType(i);
    }
    if (!target.isEmpty() && seen == target) {
      doc["target_seen"] = true; doc["target_rssi"] = WiFi.RSSI(i);
      doc["target_channel"] = WiFi.channel(i); doc["target_auth"] = (int)WiFi.encryptionType(i);
    }
    if (!target.isEmpty() && seen == trimmed && target != trimmed) doc["trimmed_target_seen"] = true;
    if (!target.isEmpty() && seen.equalsIgnoreCase(target) && seen != target) doc["case_mismatch_seen"] = true;
  }
  WiFi.scanDelete();
  serializeJson(doc,Serial); Serial.println();
  if (!alreadyConnected && !target.isEmpty()) {
    WiFi.setAutoReconnect(true);
    WiFi.begin(target.c_str(),password.c_str());
    lastWifiAttempt = millis();
  }
}
bool tokenMatches(const String &supplied) {
  String expected = String("Bearer ") + API_TOKEN;
  if (supplied.length() != expected.length()) return false;
  uint8_t mismatch = 0;
  for (size_t i=0; i<expected.length(); i++) mismatch |= supplied[i] ^ expected[i];
  return mismatch == 0;
}
esp_err_t sendJson(httpd_req_t *req, const char *status, const JsonDocument &doc) {
  String body; serializeJson(doc, body);
  httpd_resp_set_status(req, status);
  httpd_resp_set_type(req, "application/json; charset=utf-8");
  httpd_resp_set_hdr(req, "Cache-Control", "no-store");
  return httpd_resp_send(req, body.c_str(), body.length());
}
esp_err_t error(httpd_req_t *req, const char *status, const char *message) {
  JsonDocument doc; doc["detail"] = message;
  return sendJson(req, status, doc);
}
esp_err_t api(httpd_req_t *req) {
  if (req->content_len > 2048) return error(req, "413 Payload Too Large", "คำสั่งใหญ่เกินกำหนด");
  size_t authLength = httpd_req_get_hdr_value_len(req, "Authorization");
  char auth[128] = {};
  if (authLength == 0 || authLength >= sizeof(auth) ||
      httpd_req_get_hdr_value_str(req,"Authorization",auth,sizeof(auth)) != ESP_OK ||
      !tokenMatches(String(auth))) return error(req, "401 Unauthorized", "รหัสเข้าถึงบอร์ดไม่ถูกต้อง");
  char clockHeader[24] = {};
  if (time(nullptr) < 1735689600 && httpd_req_get_hdr_value_str(req,"X-AquaHatch-Time",clockHeader,sizeof(clockHeader)) == ESP_OK) {
    char *end; long long seconds = strtoll(clockHeader, &end, 10);
    if (*end == 0 && seconds >= 1735689600 && seconds < 4102444800LL) {
      struct timeval value = { (time_t)seconds, 0 }; settimeofday(&value, nullptr);
    }
  }
  String uri(req->uri); int query = uri.indexOf('?'); if (query >= 0) uri = uri.substring(0, query);
  String base = String("/api/v1/devices/") + DEVICE_ID;
  bool handled=false;
  esp_err_t setupResult=provisioning::handle(req,base,uri,handled);
  if (handled) return setupResult;
  if (req->method == HTTP_GET && uri == base) {
    if (nowIso().isEmpty()) return error(req,"503 Service Unavailable","บอร์ดกำลังตั้งเวลา กรุณาลองเชื่อมต่อใหม่");
    JsonDocument doc; snapshot(doc); return sendJson(req,"200 OK",doc);
  }
  if (req->method == HTTP_GET && uri == base + "/camera") {
    JsonDocument doc; doc["configured"] = false; doc["online"] = false;
    doc["message"] = "ยังไม่ตั้งค่าบอร์ดและขากล้อง OV5640";
    return sendJson(req,"200 OK",doc);
  }
  if (req->method == HTTP_GET && uri == base + "/history") {
    JsonDocument doc; doc["items"].to<JsonArray>(); return sendJson(req,"200 OK",doc);
  }
  if (req->method == HTTP_POST && uri == base + "/commands") {
    if (req->content_len <= 0) return error(req,"400 Bad Request","ไม่มีคำสั่ง");
    String body; body.reserve(req->content_len);
    int remaining = req->content_len;
    while (remaining > 0) {
      char block[256]; int got = httpd_req_recv(req, block, min(remaining, (int)sizeof(block)));
      if (got <= 0) return ESP_FAIL;
      body.concat(block, got); remaining -= got;
    }
    JsonDocument incoming;
    if (deserializeJson(incoming,body) || !incoming["payload"].is<JsonObject>())
      return error(req,"400 Bad Request","รูปแบบคำสั่งไม่ถูกต้อง");
    String id = incoming["command_id"] | "";
    if (id.isEmpty() || id.length()>64) return error(req,"422 Unprocessable Entity","รหัสคำสั่งไม่ถูกต้อง");
    for (size_t i=0; i<id.length();i++) if (!isalnum((unsigned char)id[i]) && id[i]!='-' && id[i]!='_')
      return error(req,"422 Unprocessable Entity","รหัสคำสั่งไม่ถูกต้อง");
    for (auto &entry : cache) if (entry.id == id) {
      if (entry.body != body) return error(req,"409 Conflict","รหัสคำสั่งซ้ำแต่เนื้อหาต่างกัน");
      httpd_resp_set_type(req,"application/json; charset=utf-8");
      httpd_resp_set_hdr(req,"Cache-Control","no-store");
      return httpd_resp_send(req,entry.reply.c_str(),entry.reply.length());
    }
    time_t now = time(nullptr); int64_t expires = incoming["expires_at_unix"] | (int64_t)0;
    if (now < 1735689600 || expires <= now || expires > now + 30)
      return error(req,"410 Gone","คำสั่งหมดอายุหรือนาฬิกายังไม่พร้อม");
    String action = incoming["action"] | "";
    if (action == "set_mode" || action == "set_output")
      return error(req,"409 Conflict","ยังไม่กำหนดวงจรและ GPIO จึงยังเปิดอุปกรณ์จริงไม่ได้");
    if (action != "ping" && action != "set_config")
      return error(req,"422 Unprocessable Entity","บอร์ดยังไม่รองรับคำสั่งนี้");
    if (action == "set_config") {
      JsonObject p = incoming["payload"];
      if (!p["temperature_target"].is<double>() || !p["ph_minimum"].is<double>() ||
          !p["ph_maximum"].is<double>() || !p["flow_target"].is<double>())
        return error(req,"422 Unprocessable Entity","ค่าตั้งต้องเป็นตัวเลขครบทุกค่า");
      float t=p["temperature_target"], low=p["ph_minimum"], high=p["ph_maximum"], flow=p["flow_target"];
      if (!isfinite(t)||!isfinite(low)||!isfinite(high)||!isfinite(flow)||t<20||t>35||low<0||high>14||low>=high||flow<=0||flow>50)
        return error(req,"422 Unprocessable Entity","ค่าตั้งอยู่นอกช่วงที่รองรับ");
      String stored; serializeJson(p, stored);
      if (prefs.putString("config",stored) != stored.length())
        return error(req,"500 Internal Server Error","บันทึกค่าบนบอร์ดไม่สำเร็จ");
      temperatureTarget=t; phMinimum=low; phMaximum=high; flowTarget=flow;
    }
    commandCount++;
    JsonDocument response; response["command_id"]=id; response["status"]="applied";
    response["message"]=action == "ping" ? "ESP32-S3 ตอบรับคำสั่งจริงแล้ว" : "บอร์ดบันทึกค่าตั้งแล้ว ยังไม่เปิดอุปกรณ์";
    response["uptime_ms"]=millis(); response["command_count"]=commandCount;
    String reply; serializeJson(response,reply);
    cache[cacheIndex] = {id,body,reply}; cacheIndex=(cacheIndex+1)%8;
    return sendJson(req,"200 OK",response);
  }
  if (uri.startsWith(base + "/camera/captures")) return error(req,"503 Service Unavailable","ยังไม่ติดตั้งและยืนยันขากล้อง");
  if (uri == base + "/counts/analyze") return error(req,"501 Not Implemented","การวิเคราะห์ AI ต้องใช้ Gateway ที่ติดตั้งโมเดลลูกปลา");
  return error(req,"404 Not Found","ไม่พบเส้นทางหรือรหัสเครื่องนี้");
}
void startTls() {
  if (tlsReady) return;
  httpd_ssl_config_t config=HTTPD_SSL_CONFIG_DEFAULT();
  config.httpd.uri_match_fn=httpd_uri_match_wildcard;
  config.httpd.max_open_sockets=3; config.httpd.lru_purge_enable=true;
  config.httpd.recv_wait_timeout=3; config.httpd.send_wait_timeout=3;
  config.servercert=(const uint8_t*)SERVER_CERT; config.servercert_len=sizeof(SERVER_CERT);
  config.prvtkey_pem=(const uint8_t*)SERVER_KEY; config.prvtkey_len=sizeof(SERVER_KEY);
  if (httpd_ssl_start(&httpsServer,&config)!=ESP_OK) { Serial.println("{\"type\":\"tls_error\"}"); return; }
  for (httpd_method_t method : {HTTP_GET,HTTP_POST}) {
    httpd_uri_t route={}; route.uri="/*"; route.method=method; route.handler=api;
    if (httpd_register_uri_handler(httpsServer,&route)!=ESP_OK) return;
  }
  tlsReady=true;
}
void serialCommand() {
  JsonDocument doc;
  if (deserializeJson(doc, serialLine)) { Serial.println("{\"type\":\"invalid_command\"}"); return; }
  String op=doc["op"] | "";
  if (op=="status") { serialStatus(); return; }
  if (op=="diagnose") { wifiDiagnostics(); return; }
  if (op=="wifi") {
    String ssid=doc["ssid"] | "";
    String saved,password; provisioning::loadSaved(saved,password);
    if (doc["reuse_password"] != true) password=String(doc["password"] | "");
    if (ssid.length()<1 || ssid.length()>32 || password.length()<8 || password.length()>64) {
      Serial.println("{\"type\":\"wifi_error\",\"reason\":\"invalid_length\"}"); return;
    }
    if (!provisioning::saveNetwork(ssid,password)) {
      Serial.println("{\"type\":\"wifi_error\",\"reason\":\"save_failed\"}"); return;
    }
    WiFi.disconnect(false,false); WiFi.begin(ssid.c_str(),password.c_str());
    lastWifiAttempt=millis(); Serial.println("{\"type\":\"wifi_connecting\"}"); return;
  }
  Serial.println("{\"type\":\"unknown_command\"}");
}
void setup() {
  Serial.begin(115200); delay(200);
  prefs.begin("aquahatch",false);
  WiFi.onEvent([](WiFiEvent_t event, WiFiEventInfo_t info) {
    lastDisconnectReason = info.wifi_sta_disconnected.reason; disconnectCount++;
    if (firstReasonCount < 12) {
      firstDisconnectReasons[firstReasonCount] = info.wifi_sta_disconnected.reason;
      firstReasonCount++;
    }
  }, ARDUINO_EVENT_WIFI_STA_DISCONNECTED);
  JsonDocument stored;
  if (!deserializeJson(stored,prefs.getString("config","{}"))) {
    temperatureTarget=stored["temperature_target"] | 28.0f;
    phMinimum=stored["ph_minimum"] | 6.5f; phMaximum=stored["ph_maximum"] | 8.5f;
    flowTarget=stored["flow_target"] | 2.4f;
  }
  WiFi.persistent(false); WiFi.setHostname("aquahatch-117c"); WiFi.mode(WIFI_AP_STA);
  WiFi.setAutoReconnect(true); provisioning::begin();
  String ssid,password; provisioning::loadSaved(ssid,password);
  if (!ssid.isEmpty()) { WiFi.begin(ssid.c_str(),password.c_str()); lastWifiAttempt=millis(); }
  serialStatus("boot");
}
void loop() {
  provisioning::tick();
  while (Serial.available()) {
    char c=Serial.read();
    if (c=='\n') {
      if (!serialOverflow && serialLine.length()) serialCommand();
      serialLine=""; serialOverflow=false;
    } else if (c!='\r' && !serialOverflow) {
      if (serialLine.length()<1024) serialLine+=c;
      else { serialLine=""; serialOverflow=true; }
    }
  }
  bool connected=WiFi.status()==WL_CONNECTED;
  if (connected && !wasConnected) {
    configTime(0,0,"pool.ntp.org","time.nist.gov");
    MDNS.end(); MDNS.begin("aquahatch-117c"); MDNS.addService("https","tcp",443);
    startTls(); serialStatus("wifi_connected");
  }
  if (!connected && wasConnected) serialStatus("wifi_disconnected");
  if (!connected && !provisioning::busy() && millis()-lastWifiAttempt>30000) {
    String ssid,password; provisioning::loadSaved(ssid,password);
    if (!ssid.isEmpty()) WiFi.begin(ssid.c_str(),password.c_str());
    lastWifiAttempt=millis();
  }
  wasConnected=connected; delay(5);
}
