// Direct camera HTTPS server; optional bounded capture illumination on GPIO4.
// No pump/heater/SD GPIO control.
#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <esp_https_server.h>
#include <esp_heap_caps.h>
#include <sys/time.h>
#include "esp_camera.h"
#include <AquaIdentity.h>
AquaIdentity boardIdentity;
#define DEVICE_ID boardIdentity.deviceId().c_str()
#define DEVICE_HOSTNAME boardIdentity.hostname().c_str()
#define API_TOKEN boardIdentity.token().c_str()
#define SERVER_CERT boardIdentity.serverCertificate().c_str()
#define SERVER_KEY boardIdentity.serverKey().c_str()
#include "camera_pins.h"
#include "camera_quality.h"

static const char VERSION[]="0.14.0-camera.1";
Preferences prefs;
httpd_handle_t server=nullptr;
bool tlsReady=false,wasConnected=false,cameraReady=false,cameraActive=false;
uint32_t lastCameraProbeAt=0;
uint32_t lastWifiAttempt=0;
volatile uint16_t lastDisconnectReason=0;
String serialLine,cameraError,sensorName;
framesize_t nativeFrameSize=FRAMESIZE_QXGA;
uint16_t nativeWidth=2048,nativeHeight=1536;
bool autofocusSupported=false;
const char *nativeResolution="3mp";
bool serialOverflow=false;
camera_fb_t *photo=nullptr;
camera_fb_t storedPhoto={};
String captureId,receivedAt,photoDigest;
uint32_t capturedAt=0;
String seenIds[8]; uint8_t seenIndex=0;
AquaFocusResult lastFocus;
uint32_t lastWarmupMs=0,lastCaptureMs=0;
bool flashAttached=false,flashActive=false,lastFlashUsed=false;
uint8_t lastFlashDuty=0,lastJpegQuality=10;
void startTls();
void initCamera(framesize_t size=FRAMESIZE_INVALID,int quality=10);
void shutdownCamera();
void flashOff();
esp_err_t sendJson(httpd_req_t*,const char*,const JsonDocument&);
esp_err_t error(httpd_req_t*,const char*,const char*);
#include "wifi_setup.h"

String nowIso() {
  time_t now=time(nullptr); if(now<1735689600) return "";
  struct tm utc; gmtime_r(&now,&utc); char value[32];
  strftime(value,sizeof(value),"%Y-%m-%dT%H:%M:%SZ",&utc); return String(value);
}
void identity(JsonDocument &doc) {
  doc["backend"]="esp32-camera"; doc["protocol_version"]=1;
  doc["device_id"]=DEVICE_ID; doc["camera_id"]=DEVICE_ID; doc["firmware"]=VERSION;
  doc["server_time_unix"]=(int64_t)time(nullptr);
}
void status(JsonDocument &doc) {
  identity(doc); doc["configured"]=cameraReady; doc["online"]=cameraReady;
  doc["sensor"]=sensorName; doc["psram_bytes"]=ESP.getPsramSize();
  doc["capture_mode"]="on_demand";doc["camera_awake"]=cameraActive;
  doc["focus_status"]=lastFocus.status;
  doc["flash_active"]=flashActive;
  doc["default_flash"]=true;doc["default_capture_width"]=nativeWidth;doc["default_capture_height"]=nativeHeight;
  doc["default_capture_resolution"]=nativeResolution;doc["autofocus_supported"]=autofocusSupported;
  doc["message"]=cameraReady?"กล้องพร้อมถ่ายภาพผ่าน Wi-Fi":cameraError;
  doc["last_seen"]=nowIso(); doc["ip"]=WiFi.localIP().toString();
  doc["wifi_rssi"]=WiFi.RSSI();doc["free_heap"]=ESP.getFreeHeap();
  doc["min_free_heap"]=ESP.getMinFreeHeap();doc["disconnect_reason"]=(uint16_t)lastDisconnectReason;
  doc["uptime_ms"]=millis();doc["wifi_mode"]=(int)WiFi.getMode();
  {provisioning::Guard guard;doc["setup_ap_active"]=provisioning::apActive;}
}
esp_err_t sendJson(httpd_req_t *req,const char *code,const JsonDocument &doc) {
  String body; serializeJson(doc,body); httpd_resp_set_status(req,code);
  httpd_resp_set_type(req,"application/json; charset=utf-8"); httpd_resp_set_hdr(req,"Cache-Control","no-store");
  return httpd_resp_send(req,body.c_str(),body.length());
}
esp_err_t error(httpd_req_t *req,const char *code,const char *message) {
  JsonDocument doc; doc["detail"]=message; return sendJson(req,code,doc);
}
void releasePhoto() { if(photo) { heap_caps_free(photo->buf); photo=nullptr; storedPhoto={}; } }
void job(JsonDocument &doc) {
  identity(doc); doc["capture_id"]=captureId; doc["received_at"]=receivedAt;
  doc["sensor"]=sensorName;
  doc["status"]=photo?"captured":"expired";
  if(photo) { doc["bytes"]=photo->len; doc["width"]=photo->width; doc["height"]=photo->height; doc["sha256"]=photoDigest; }
  doc["focus_status"]=lastFocus.status;doc["focus_firmware_ready"]=lastFocus.firmwareReady;
  doc["focus_confirmed"]=lastFocus.focused;doc["focus_raw"]=lastFocus.raw;
  doc["focus_init_ms"]=lastFocus.initMs;doc["focus_search_ms"]=lastFocus.searchMs;
  doc["warmup_ms"]=lastWarmupMs;doc["flash_used"]=lastFlashUsed;doc["capture_ms"]=lastCaptureMs;
  doc["flash_duty"]=lastFlashDuty;doc["jpeg_quality"]=lastJpegQuality;
}
void flashOff() {
  if(flashAttached)ledcWrite(FLASH_GPIO_NUM,0);
  else {pinMode(FLASH_GPIO_NUM,OUTPUT);digitalWrite(FLASH_GPIO_NUM,LOW);}
  flashActive=false;
}
bool flashOn(uint8_t duty) {
  // Camera XCLK uses channel 0/timer 0. Explicitly use a different timer.
  if(!flashAttached)flashAttached=ledcAttachChannel(FLASH_GPIO_NUM,10000,8,4);
  flashActive=flashAttached&&ledcWrite(FLASH_GPIO_NUM,duty);
  return flashActive;
}
bool validId(const String &id) {
  if(id.isEmpty()||id.length()>64) return false;
  for(char c:id) if(!isalnum((unsigned char)c)&&c!='-'&&c!='_') return false;
  return true;
}
bool readBody(httpd_req_t *req,String &body) {
  if(req->content_len<1||req->content_len>2048) return false;
  int left=req->content_len;
  while(left>0) { char b[256]; int got=httpd_req_recv(req,b,min(left,(int)sizeof(b))); if(got<=0) return false; body.concat(b,got); left-=got; }
  return true;
}
esp_err_t api(httpd_req_t *req) {
  if(req->content_len>2048) return error(req,"413 Payload Too Large","ข้อมูลใหญ่เกินกำหนด");
  char auth[128]={}; String expected=String("Bearer ")+API_TOKEN;
  size_t length=httpd_req_get_hdr_value_len(req,"Authorization");
  if(length!=expected.length()||length>=sizeof(auth)||httpd_req_get_hdr_value_str(req,"Authorization",auth,sizeof(auth))!=ESP_OK)
    return error(req,"401 Unauthorized","รหัสจับคู่กล้องไม่ถูกต้อง");
  uint8_t mismatch=0; for(size_t i=0;i<expected.length();i++) mismatch|=expected[i]^auth[i];
  if(mismatch) return error(req,"401 Unauthorized","รหัสจับคู่กล้องไม่ถูกต้อง");
  char clockHeader[24]={};
  if(time(nullptr)<1735689600&&httpd_req_get_hdr_value_str(req,"X-AquaHatch-Time",clockHeader,sizeof(clockHeader))==ESP_OK) {
    char *end; long long epoch=strtoll(clockHeader,&end,10);
    if(*end==0&&epoch>=1735689600&&epoch<4102444800LL) { struct timeval value={(time_t)epoch,0}; settimeofday(&value,nullptr); }
  }
  String uri=req->uri; int query=uri.indexOf('?'); if(query>=0) uri=uri.substring(0,query);
  String base=String("/api/v1/devices/")+DEVICE_ID;
  bool handled=false; esp_err_t setupResult=provisioning::handle(req,base,uri,handled); if(handled) return setupResult;
  if(req->method==HTTP_GET&&uri==base+"/camera") {
    if(!cameraReady&&millis()-lastCameraProbeAt>15000) {initCamera();shutdownCamera();}
    JsonDocument doc; status(doc); return sendJson(req,"200 OK",doc);
  }
  if(photo&&millis()-capturedAt>120000) releasePhoto();
  String captures=base+"/camera/captures";
  if(req->method==HTTP_POST&&uri==captures) {
    String body; JsonDocument incoming;
    if(!readBody(req,body)||deserializeJson(incoming,body)) return error(req,"400 Bad Request","ข้อมูลถ่ายภาพไม่ถูกต้อง");
    const int warmup=incoming["warmup_ms"]|1800;
    if(warmup<0||warmup>3000)return error(req,"422 Unprocessable Entity","เวลาเตรียมกล้องไม่ถูกต้อง");
    const bool focus=incoming["autofocus"]|true;
    const bool flash=incoming["flash"]|true;
    const int duty=incoming["flash_duty"]|64;
    const int quality=incoming["jpeg_quality"]|10;
    if(duty<16||duty>96||quality<4||quality>16)return error(req,"422 Unprocessable Entity","ค่าคุณภาพหรือความสว่างแฟลชไม่ถูกต้อง");
    const String resolution=incoming["resolution"]|"sensor_max";
    framesize_t frameSize;
    if(resolution=="sensor_max")frameSize=nativeFrameSize;
    else if(resolution=="5mp")frameSize=FRAMESIZE_QSXGA;
    else if(resolution=="3mp")frameSize=FRAMESIZE_QXGA;
    else if(resolution=="uxga")frameSize=FRAMESIZE_UXGA;
    else if(resolution=="svga")frameSize=FRAMESIZE_SVGA;
    else return error(req,"422 Unprocessable Entity","ขนาดภาพไม่ถูกต้อง");
    String id=incoming["capture_id"]|"";
    if(!validId(id)) return error(req,"422 Unprocessable Entity","รหัสภาพไม่ถูกต้อง");
    if(id==captureId) {
      if(!photo) return error(req,"410 Gone","ภาพหมดอายุแล้ว ใช้รหัสคำขอใหม่");
      JsonDocument doc; job(doc); return sendJson(req,"202 Accepted",doc);
    }
    for(const auto &seen:seenIds) if(seen==id) return error(req,"410 Gone","คำขอนี้สิ้นสุดแล้ว");
    time_t now=time(nullptr); int64_t expires=incoming["expires_at_unix"]|(int64_t)0;
    if(now<1735689600||expires<=now||expires>now+60) return error(req,"410 Gone","คำขอถ่ายภาพหมดอายุ");
    seenIds[seenIndex]=id; seenIndex=(seenIndex+1)%8;
    releasePhoto(); captureId=id;
    const uint32_t captureStart=millis();lastFlashUsed=false;lastWarmupMs=warmup;lastCaptureMs=0;lastFlashDuty=0;lastJpegQuality=quality;
    initCamera(frameSize,quality);
    if(!cameraReady) {shutdownCamera();return error(req,"503 Service Unavailable",cameraError.c_str());}
    sensor_t *sensor=esp_camera_sensor_get();lastFocus=aquaPrepareFocus(sensor,focus&&autofocusSupported);
    if(!autofocusSupported)lastFocus.status="not_supported_sensor";
    if(flash) {
      lastFlashUsed=flashOn(duty);lastFlashDuty=lastFlashUsed?duty:0;
      if(!lastFlashUsed) {shutdownCamera();return error(req,"503 Service Unavailable","เปิดแฟลชกล้องไม่สำเร็จ");}
    }
    // Let exposure and white balance converge after each on-demand startup.
    const uint32_t warmStart=millis();
    while(millis()-warmStart<(uint32_t)warmup) {
      camera_fb_t *settle=esp_camera_fb_get();
      if(!settle)break;
      esp_camera_fb_return(settle);
    }
    aquaRunFocus(sensor,lastFocus);
    // Flush the queued frame, then acquire a frame after this request.
    camera_fb_t *old=esp_camera_fb_get(); if(old) esp_camera_fb_return(old);
    camera_fb_t *frame=esp_camera_fb_get();
    if(!frame||frame->format!=PIXFORMAT_JPEG||frame->len<4||frame->buf[0]!=0xff||frame->buf[1]!=0xd8||frame->buf[frame->len-2]!=0xff||frame->buf[frame->len-1]!=0xd9) {
      if(frame)esp_camera_fb_return(frame);
      cameraReady=false;cameraError="กล้องยังส่งภาพ JPEG ที่สมบูรณ์ไม่ได้ ตรวจสายแพและไฟเลี้ยง";
      shutdownCamera();return error(req,"503 Service Unavailable",cameraError.c_str());
    }
    // Own a copy before deinitializing the driver: its frame buffer becomes
    // invalid on deinit. Keep the sensor/DMA off during TLS and image transfer.
    uint8_t *copy=(uint8_t*)heap_caps_malloc(frame->len,MALLOC_CAP_SPIRAM|MALLOC_CAP_8BIT);
    if(!copy) {esp_camera_fb_return(frame);shutdownCamera();return error(req,"503 Service Unavailable","หน่วยความจำเก็บภาพไม่พอ");}
    memcpy(copy,frame->buf,frame->len);storedPhoto=*frame;storedPhoto.buf=copy;photo=&storedPhoto;
    esp_camera_fb_return(frame);shutdownCamera();
    unsigned char digest[32]; mbedtls_sha256(photo->buf,photo->len,digest,0);
    photoDigest=""; const char *hex="0123456789abcdef";
    for(uint8_t value:digest) { photoDigest+=hex[value>>4]; photoDigest+=hex[value&15]; }
    lastCaptureMs=millis()-captureStart;
    receivedAt=nowIso(); capturedAt=millis(); JsonDocument doc; job(doc); return sendJson(req,"202 Accepted",doc);
  }
  if(req->method==HTTP_GET&&uri.startsWith(captures+"/")) {
    String suffix=uri.substring(captures.length()+1); bool image=suffix.endsWith("/image");
    String id=image?suffix.substring(0,suffix.length()-6):suffix;
    if(!validId(id)||id!=captureId) return error(req,"404 Not Found","ไม่พบภาพของคำขอนี้");
    if(!photo) return error(req,"410 Gone","ภาพหมดอายุแล้ว");
    if(image) {
      httpd_resp_set_type(req,"image/jpeg"); httpd_resp_set_hdr(req,"Cache-Control","no-store");
      httpd_resp_set_hdr(req,"X-Capture-ID",captureId.c_str());
      return httpd_resp_send(req,(const char*)photo->buf,photo->len);
    }
    JsonDocument doc; job(doc); return sendJson(req,"200 OK",doc);
  }
  return error(req,"404 Not Found","ไม่พบเส้นทางของกล้อง");
}
void startTls() {
  if(tlsReady) return;
  httpd_ssl_config_t config=HTTPD_SSL_CONFIG_DEFAULT();
  config.httpd.uri_match_fn=httpd_uri_match_wildcard; config.httpd.max_open_sockets=2;
  config.httpd.lru_purge_enable=true; config.httpd.stack_size=12288;
  config.httpd.recv_wait_timeout=15;config.httpd.send_wait_timeout=15;
  config.servercert=(const uint8_t*)SERVER_CERT; config.servercert_len=strlen(SERVER_CERT)+1;
  config.prvtkey_pem=(const uint8_t*)SERVER_KEY; config.prvtkey_len=strlen(SERVER_KEY)+1;
  if(httpd_ssl_start(&server,&config)!=ESP_OK) { Serial.println("TLS_START_FAILED"); return; }
  httpd_uri_t route={}; route.uri="/api/v1/*"; route.method=HTTP_GET; route.handler=api; httpd_register_uri_handler(server,&route);
  route.method=HTTP_POST; httpd_register_uri_handler(server,&route); tlsReady=true;
}
void initCamera(framesize_t size,int quality) {
  lastCameraProbeAt=millis();cameraReady=false;cameraError="";
  if(!psramFound()) { cameraError="ไม่พบ PSRAM ตรวจรุ่นบอร์ดและการตั้งค่า"; return; }
  camera_config_t c={}; c.ledc_channel=LEDC_CHANNEL_0; c.ledc_timer=LEDC_TIMER_0;
  c.pin_d0=Y2_GPIO_NUM;c.pin_d1=Y3_GPIO_NUM;c.pin_d2=Y4_GPIO_NUM;c.pin_d3=Y5_GPIO_NUM;
  c.pin_d4=Y6_GPIO_NUM;c.pin_d5=Y7_GPIO_NUM;c.pin_d6=Y8_GPIO_NUM;c.pin_d7=Y9_GPIO_NUM;
  c.pin_xclk=XCLK_GPIO_NUM;c.pin_pclk=PCLK_GPIO_NUM;c.pin_vsync=VSYNC_GPIO_NUM;c.pin_href=HREF_GPIO_NUM;
  c.pin_sccb_sda=SIOD_GPIO_NUM;c.pin_sccb_scl=SIOC_GPIO_NUM;c.pin_pwdn=PWDN_GPIO_NUM;c.pin_reset=RESET_GPIO_NUM;
  // Clamp legacy 5mp requests to the detected sensor's native size. Never
  // upscale OV3660 or advertise a 5MP image from its 3MP sensor.
  c.xclk_freq_hz=20000000;c.pixel_format=PIXFORMAT_JPEG;
  c.frame_size=size==FRAMESIZE_INVALID?nativeFrameSize:(size>nativeFrameSize?nativeFrameSize:size);
  c.jpeg_quality=quality;c.fb_count=1;c.fb_location=CAMERA_FB_IN_PSRAM;c.grab_mode=CAMERA_GRAB_WHEN_EMPTY;
  esp_err_t result=esp_camera_init(&c);
  if(result!=ESP_OK) { cameraError=String("เริ่มกล้องไม่สำเร็จ รหัส ")+String(result,HEX); return; }
  cameraActive=true;
  sensor_t *sensor=esp_camera_sensor_get();
  autofocusSupported=sensor->id.PID==OV5640_PID;
  if(sensor->id.PID==OV3660_PID) {
    sensorName="OV3660";nativeFrameSize=FRAMESIZE_QXGA;nativeWidth=2048;nativeHeight=1536;nativeResolution="3mp";
    // Match Espressif's CameraWebServer OV3660 setup used in the real test.
    sensor->set_vflip(sensor,1);sensor->set_brightness(sensor,1);sensor->set_saturation(sensor,-2);
  } else if(sensor->id.PID==OV5640_PID) {
    sensorName="OV5640";nativeFrameSize=FRAMESIZE_QSXGA;nativeWidth=2560;nativeHeight=1920;nativeResolution="5mp";
  } else if(sensor->id.PID==OV2640_PID) {
    sensorName="OV2640";nativeFrameSize=FRAMESIZE_UXGA;nativeWidth=1600;nativeHeight=1200;nativeResolution="uxga";
  } else {
    cameraError="ยังไม่รองรับเซนเซอร์กล้องรุ่นนี้";return;
  }
  cameraReady=true; Serial.printf("CAMERA_READY sensor=%s pid=0x%04x psram=%u\n",sensorName.c_str(),sensor->id.PID,ESP.getPsramSize());
}
void shutdownCamera() {
  flashOff();
  if(cameraActive)esp_camera_deinit();
  cameraActive=false;pinMode(PWDN_GPIO_NUM,OUTPUT);digitalWrite(PWDN_GPIO_NUM,HIGH);
}
void serialStatus() {
  JsonDocument doc; status(doc); doc["type"]="camera_status"; doc["connected"]=WiFi.status()==WL_CONNECTED;
  doc["tls_ready"]=tlsReady; doc["ap_ssid"]=provisioning::apName; serializeJson(doc,Serial);Serial.println();
}
void serialCommand() {
  JsonDocument doc;if(deserializeJson(doc,serialLine)) return;
  String op=doc["op"]|"";
  if(op=="status") {serialStatus();return;}
  if(op=="pairing"){
    // The physically connected owner's PC supplies UTC for offline first boot.
    const int64_t epoch=doc["time_unix"]|(int64_t)0;
    if(epoch>=1735689600LL && epoch<4102444800LL){
      timeval now={(time_t)epoch,0};settimeofday(&now,nullptr);
      if(boardIdentity.needsRenewal((time_t)epoch)){
        if(tlsReady){httpd_ssl_stop(server);server=nullptr;tlsReady=false;}
        if(!boardIdentity.renew((time_t)epoch)){Serial.println("{\"type\":\"pairing_error\"}");startTls();return;}
        startTls();
      }
    }
    JsonDocument response;boardIdentity.pairing(response);serializeJson(response,Serial);Serial.println();return;
  }
  if(op=="wifi") {
    String ssid=doc["ssid"]|"",password=doc["password"]|"";
    if(ssid.isEmpty()||ssid.length()>32||!provisioning::validPassword(password)) {Serial.println("WIFI_INVALID");return;}
    if(!provisioning::saveNetwork(ssid,password)) {Serial.println("WIFI_SAVE_FAILED");return;}
    WiFi.disconnect(false,false);WiFi.begin(ssid.c_str(),password.c_str());lastWifiAttempt=millis();Serial.println("WIFI_CONNECTING");
  }
}
void setup() {
  Serial.begin(115200);delay(250);
  WiFi.persistent(false);WiFi.mode(WIFI_AP_STA);WiFi.setSleep(false);
  if(!boardIdentity.begin("camera")){Serial.println("IDENTITY_ERROR:"+boardIdentity.error());while(true)delay(1000);}
  provisioning::apName=boardIdentity.setupSsid();
  prefs.begin("aquacam",false);initCamera();shutdownCamera();
  WiFi.onEvent([](WiFiEvent_t,WiFiEventInfo_t info){lastDisconnectReason=info.wifi_sta_disconnected.reason;},ARDUINO_EVENT_WIFI_STA_DISCONNECTED);
  WiFi.persistent(false);WiFi.setHostname(boardIdentity.mdnsName().c_str());WiFi.mode(WIFI_AP_STA);WiFi.setAutoReconnect(true);WiFi.setSleep(false);
  provisioning::begin();String ssid,password;provisioning::loadSaved(ssid,password);
  if(!ssid.isEmpty()){WiFi.begin(ssid.c_str(),password.c_str());lastWifiAttempt=millis();}serialStatus();
}
void loop() {
  provisioning::tick();
  while(Serial.available()) {char c=Serial.read();if(c=='\n'){if(!serialOverflow&&serialLine.length())serialCommand();serialLine="";serialOverflow=false;}
    else if(c!='\r'&&!serialOverflow){if(serialLine.length()<1024)serialLine+=c;else{serialLine="";serialOverflow=true;}}}
  bool connected=WiFi.status()==WL_CONNECTED;
  if(connected&&!wasConnected){configTime(0,0,"pool.ntp.org","time.nist.gov");MDNS.begin(boardIdentity.mdnsName().c_str());MDNS.addService("https","tcp",443);serialStatus();}
  if(!connected&&!provisioning::busy()&&millis()-lastWifiAttempt>30000){String ssid,password;provisioning::loadSaved(ssid,password);if(!ssid.isEmpty())WiFi.begin(ssid.c_str(),password.c_str());lastWifiAttempt=millis();}
  static uint32_t lastCertificateCheck=0;
  if(millis()-lastCertificateCheck>60000 && !photo && !provisioning::busy()){
    lastCertificateCheck=millis();
    if(boardIdentity.needsRenewal(time(nullptr))){
      if(tlsReady){httpd_ssl_stop(server);server=nullptr;tlsReady=false;}
      bool renewed=boardIdentity.renew(time(nullptr));
      Serial.println(renewed?"CERTIFICATE_RENEWED":"CERTIFICATE_RENEWAL_FAILED");startTls();
    }
  }
  wasConnected=connected;delay(5);
}
