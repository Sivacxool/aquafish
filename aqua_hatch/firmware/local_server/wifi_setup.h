#pragma once
#include <mbedtls/sha256.h>
#include <freertos/semphr.h>

// Called only after normal bearer authentication. Wi-Fi changes run on loop(),
// after the HTTPS acknowledgement has been sent, rather than in its handler.
namespace provisioning {
SemaphoreHandle_t mutex = nullptr;
struct Guard {
  Guard() { xSemaphoreTake(mutex, portMAX_DELAY); }
  ~Guard() { xSemaphoreGive(mutex); }
};
String phase="idle", requestId, requestHash, candidateSsid, candidatePassword, failure;
String networks="[]", scanState="idle";
bool queued=false, connecting=false, scanRequested=false, scanRunning=false, scanPaused=false;
bool apRequested=false, apActive=false;
uint32_t queuedAt=0, startedAt=0, apStartedAt=0;
uint16_t reason=0;
String apName="AquaHatch-117C";

void loadSaved(String &ssid, String &password) {
  JsonDocument doc;
  if (!deserializeJson(doc,prefs.getString("network_v2","")) && doc["ssid"].is<String>() && doc["password"].is<String>()) {
    ssid=doc["ssid"].as<String>(); password=doc["password"].as<String>();
  } else { ssid=prefs.getString("ssid",""); password=prefs.getString("wifi_pass",""); }
}
bool saveNetwork(const String &ssid, const String &password) {
  JsonDocument doc; doc["ssid"]=ssid; doc["password"]=password;
  String encoded; serializeJson(doc,encoded);
  // One NVS value commits SSID and password together. Failed candidates never
  // overwrite the previous working network.
  return prefs.putString("network_v2",encoded)==encoded.length();
}
String hash(const String &value) {
  unsigned char digest[32]; mbedtls_sha256((const unsigned char*)value.c_str(),value.length(),digest,0);
  const char *hex="0123456789abcdef"; String result; result.reserve(64);
  for (uint8_t byte : digest) { result+=hex[byte>>4]; result+=hex[byte&15]; }
  return result;
}
String apPassword() { return hash(String("AquaHatch setup v1:")+API_TOKEN).substring(0,16); }
void startAp() {
  { Guard guard; if (apActive) { apStartedAt=millis(); return; } }
  IPAddress ip(192,168,4,1);
  WiFi.softAPConfig(ip,ip,IPAddress(255,255,255,0));
  String password=apPassword();
  bool started=WiFi.softAP(apName.c_str(),password.c_str(),1,false,2);
  { Guard guard; apActive=started; apStartedAt=millis(); }
  if (started) startTls();
}
void begin() { mutex=xSemaphoreCreateMutex(); startAp(); }
bool busy() { Guard guard; return queued || connecting || scanRunning || scanRequested; }
void status(JsonDocument &doc) {
  Guard guard;
  doc["device_id"]=DEVICE_ID; doc["backend"]="esp32-local"; doc["provisioning_version"]=1;
  doc["firmware"]=VERSION; doc["connected"]=WiFi.status()==WL_CONNECTED;
  doc["ip"]=WiFi.status()==WL_CONNECTED ? WiFi.localIP().toString() : String("");
  doc["ssid"]=WiFi.status()==WL_CONNECTED ? WiFi.SSID() : String("");
  String saved,password; loadSaved(saved,password);
  doc["saved_ssid"]=saved; doc["credentials_saved"]=!saved.isEmpty();
  doc["ap_ssid"]=apName; doc["ap_ip"]="192.168.4.1"; doc["ap_active"]=apActive;
  doc["phase"]=phase; doc["request_id"]=requestId; doc["attempt_ssid"]=candidateSsid;
  doc["error"]=failure; doc["reason_code"]=reason;
  doc["scan_state"]=scanState;
  JsonDocument found; deserializeJson(found,networks); doc["networks"]=found.as<JsonArray>();
}
bool validPassword(const String &value) {
  if (value.length()>=8 && value.length()<=63) return true;
  if (value.length()!=64) return false;
  for (char c:value) if (!isxdigit((unsigned char)c)) return false;
  return true;
}
esp_err_t handle(httpd_req_t *req,const String &base,const String &uri,bool &handled) {
  handled=uri==base+"/wifi" || uri==base+"/wifi/scan" || uri==base+"/wifi/start";
  if (!handled) return ESP_OK;
  if (req->method==HTTP_GET && uri==base+"/wifi") {
    JsonDocument doc; status(doc); return sendJson(req,"200 OK",doc);
  }
  if (req->method!=HTTP_POST) return error(req,"405 Method Not Allowed","ไม่รองรับคำขอนี้");
  if (uri!=base+"/wifi") {
    int remaining=req->content_len;
    while (remaining>0) {
      char buffer[256]; int got=httpd_req_recv(req,buffer,min(remaining,(int)sizeof(buffer)));
      if (got<=0) return ESP_FAIL;
      remaining-=got;
    }
  }
  if (uri==base+"/wifi/start") {
    { Guard guard; apRequested=true; }
    JsonDocument doc; doc["accepted"]=true; return sendJson(req,"202 Accepted",doc);
  }
  if (uri==base+"/wifi/scan") {
    bool unavailable;
    { Guard guard; unavailable=queued||connecting;
      if (!unavailable && !scanRunning && !scanRequested) { scanRequested=true; scanState="scanning"; }
    }
    if (unavailable) return error(req,"409 Conflict","รอให้บอร์ดลองเชื่อม Wi-Fi เสร็จก่อน");
    JsonDocument doc; status(doc); return sendJson(req,"202 Accepted",doc);
  }
  if (req->content_len<=0) return error(req,"400 Bad Request","ไม่มีข้อมูล Wi-Fi");
  String body; body.reserve(req->content_len);
  int remaining=req->content_len;
  while (remaining>0) {
    char buffer[256]; int got=httpd_req_recv(req,buffer,min(remaining,(int)sizeof(buffer)));
    if (got<=0) return ESP_FAIL;
    body.concat(buffer,got); remaining-=got;
  }
  JsonDocument doc;
  if (deserializeJson(doc,body) || !doc["ssid"].is<String>() || !doc["request_id"].is<String>())
    return error(req,"422 Unprocessable Entity","ตรวจชื่อ Wi-Fi และรหัสงาน");
  String id=doc["request_id"].as<String>(), ssid=doc["ssid"].as<String>();
  if (id.isEmpty() || id.length()>64 || ssid.isEmpty() || ssid.length()>32)
    return error(req,"422 Unprocessable Entity","ชื่อ Wi-Fi หรือรหัสงานไม่ถูกต้อง");
  for (size_t i=0;i<ssid.length();i++) if ((unsigned char)ssid[i]<32 || ssid[i]==127)
    return error(req,"422 Unprocessable Entity","ชื่อ Wi-Fi มีอักขระที่ไม่รองรับ");
  for (char c:id) if (!isalnum((unsigned char)c) && c!='-' && c!='_')
    return error(req,"422 Unprocessable Entity","รหัสงานไม่ถูกต้อง");
  String password;
  if (doc["reuse_password"]==true) {
    String saved; loadSaved(saved,password);
    if (saved.isEmpty() || saved!=ssid) return error(req,"422 Unprocessable Entity","ใช้รหัสเดิมได้เฉพาะ Wi-Fi ที่บอร์ดบันทึกไว้");
  } else {
    if (!doc["password"].is<String>()) return error(req,"422 Unprocessable Entity","กรอกรหัส Wi-Fi");
    password=doc["password"].as<String>();
  }
  if (!validPassword(password) && !(password.isEmpty() && doc["allow_open"]==true))
    return error(req,"422 Unprocessable Entity","รหัส Wi-Fi ต้องมี 8–63 ตัวอักษร หรือ 64 ตัวเลขฐานสิบหก");
  String digest=hash(body); bool conflict=false;
  {
    Guard guard;
    if (id==requestId) conflict=digest!=requestHash;
    else if (queued||connecting||scanRunning||scanRequested) conflict=true;
    else {
      requestId=id; requestHash=digest; candidateSsid=ssid; candidatePassword=password;
      phase="queued"; failure=""; reason=0; queued=true; queuedAt=millis();
    }
  }
  if (conflict) return error(req,"409 Conflict","มีงานอื่นกำลังทำอยู่ หรือรหัสงานซ้ำแต่ข้อมูลต่างกัน");
  JsonDocument response; status(response); return sendJson(req,"202 Accepted",response);
}
void tick() {
  bool startScan=false,startConnect=false,reopen=false;
  String target,password;
  {
    Guard guard;
    if (apRequested) { apRequested=false; reopen=true; }
    if (scanRequested && !queued && !connecting) { scanRequested=false; scanRunning=true; startScan=true; }
    if (queued && millis()-queuedAt>750) {
      queued=false; connecting=true; phase="connecting"; startedAt=millis();
      target=candidateSsid; password=candidatePassword; startConnect=true;
    }
  }
  if (reopen) startAp();
  if (startScan) {
    WiFi.scanDelete(); scanPaused=WiFi.status()!=WL_CONNECTED;
    if (scanPaused) { WiFi.setAutoReconnect(false); WiFi.disconnect(false,false); delay(100); }
    WiFi.scanNetworks(true,false,false,120);
  }
  if (scanRunning) {
    int count=WiFi.scanComplete();
    if (count>=0 || count==WIFI_SCAN_FAILED) {
      JsonDocument doc; JsonArray list=doc.to<JsonArray>();
      for (int i=0;i<count && list.size()<32;i++) {
        String ssid=WiFi.SSID(i); if (ssid.isEmpty() || ssid==apName) continue;
        JsonObject row=list.add<JsonObject>(); row["ssid"]=ssid; row["rssi"]=WiFi.RSSI(i);
        row["auth"]=int(WiFi.encryptionType(i)); row["channel"]=WiFi.channel(i);
      }
      String encoded; serializeJson(doc,encoded); WiFi.scanDelete();
      { Guard guard; networks=encoded; scanState=count>=0?"ready":"failed"; scanRunning=false; }
      if (scanPaused) {
        scanPaused=false; String saved,old; loadSaved(saved,old); WiFi.setAutoReconnect(true);
        if (!saved.isEmpty()) { WiFi.begin(saved.c_str(),old.c_str()); lastWifiAttempt=millis(); }
      }
    }
  }
  if (startConnect) {
    startAp(); WiFi.setAutoReconnect(false); WiFi.disconnect(false,false);
    lastDisconnectReason=0; WiFi.begin(target.c_str(),password.c_str()); lastWifiAttempt=millis();
  }
  bool done=false,failed=false; String ssid,secret;
  {
    Guard guard;
    if (connecting) {
      ssid=candidateSsid; secret=candidatePassword;
      done=WiFi.status()==WL_CONNECTED && WiFi.SSID()==ssid && WiFi.localIP()!=IPAddress(0,0,0,0);
      failed=!done && millis()-startedAt>30000;
    }
  }
  if (done || failed) {
    bool saved=done && saveNetwork(ssid,secret);
    {
      Guard guard; connecting=false; candidatePassword=""; reason=lastDisconnectReason;
      phase=saved?"connected":"failed";
      failure=saved?"":done?"บอร์ดบันทึก Wi-Fi ไม่สำเร็จ":"เชื่อม Wi-Fi ไม่สำเร็จ ตรวจชื่อ รหัส และสัญญาณ แล้วลองใหม่";
    }
    WiFi.setAutoReconnect(true);
    if (!saved) {
      String previous,old; loadSaved(previous,old); WiFi.disconnect(false,false);
      if (!previous.isEmpty()) WiFi.begin(previous.c_str(),old.c_str());
      lastWifiAttempt=millis();
    }
  }
  if (!apActive && WiFi.status()!=WL_CONNECTED && millis()-lastWifiAttempt>25000) startAp();
  // Keep setup available while a phone is connected. With no phone attached,
  // close the AP after ten minutes on a working home network. Power-cycle to reopen.
  if (apActive && WiFi.status()==WL_CONNECTED && !busy() && millis()-apStartedAt>600000 && WiFi.softAPgetStationNum()==0) {
    WiFi.softAPdisconnect(true); Guard guard; apActive=false;
  }
}
}
