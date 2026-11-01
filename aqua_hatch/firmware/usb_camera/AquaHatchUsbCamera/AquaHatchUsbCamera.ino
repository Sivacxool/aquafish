// USB-UART JPEG transport for classic ESP32-CAM. No Wi-Fi credentials needed.
#include <Arduino.h>
#include <WiFi.h>
#include "esp_camera.h"
#include "camera_pins.h"
#if !CONFIG_IDF_TARGET_ESP32
#error "Select AI Thinker ESP32-CAM; this is not the separate ESP32-S3 controller."
#endif

static const uint32_t BAUD=921600;
static const uint8_t MAGIC[8]={'A','Q','C','A','M','0','1','!'};
static bool cameraReady=false;
static esp_err_t cameraError=ESP_OK;
static uint32_t sequence=0;
static uint16_t sensorPid=0;
static char command[48];
static size_t commandSize=0;

uint32_t crc32(const uint8_t *data,size_t size) {
  uint32_t crc=0xffffffff;
  while(size--) {
    crc^=*data++;
    for(uint8_t bit=0;bit<8;bit++)crc=(crc>>1)^(0xedb88320u & (0u-(crc&1)));
  }
  return crc^0xffffffff;
}
void put16(uint8_t *out,uint16_t value) {out[0]=value;out[1]=value>>8;}
void put32(uint8_t *out,uint32_t value) {for(uint8_t i=0;i<4;i++)out[i]=value>>(8*i);}
void sendPacket(uint8_t kind,uint32_t request,const uint8_t *payload,size_t size,uint16_t width=0,uint16_t height=0) {
  uint8_t header[32]={};memcpy(header,MAGIC,sizeof(MAGIC));
  header[8]=1;header[9]=kind;put16(header+10,sizeof(header));
  put32(header+12,request);put32(header+16,size);put32(header+20,sequence);
  put16(header+24,width);put16(header+26,height);put32(header+28,crc32(payload,size));
  Serial.write(header,sizeof(header));Serial.write(payload,size);Serial.flush();
}
void sendInfo(uint32_t request) {
  char info[320];
  const int size=snprintf(info,sizeof(info),
    "{\"firmware\":\"0.1.0-usb\",\"transport\":\"usb-uart\",\"baud\":%u,\"camera_ready\":%s,\"sensor_pid\":%u,\"psram_bytes\":%u,\"wifi_mode\":%d,\"camera_error\":%d,\"crc_self_test\":%s}",
    BAUD,cameraReady?"true":"false",sensorPid,ESP.getPsramSize(),(int)WiFi.getMode(),(int)cameraError,
    crc32((const uint8_t*)"123456789",9)==0xcbf43926u?"true":"false");
  sendPacket(1,request,(const uint8_t*)info,size);
}
void sendError(uint32_t request,const char *message) {sendPacket(3,request,(const uint8_t*)message,strlen(message));}
void capture(uint32_t request) {
  if(!cameraReady) {sendError(request,"Camera initialization failed; inspect camera connector and pin profile.");return;}
  camera_fb_t *frame=esp_camera_fb_get();
  if(!frame) {sendError(request,"Camera did not return a frame.");return;}
  if(frame->format!=PIXFORMAT_JPEG||frame->len<4||frame->len>512*1024||frame->buf[0]!=0xff||frame->buf[1]!=0xd8||frame->buf[frame->len-2]!=0xff||frame->buf[frame->len-1]!=0xd9) {
    esp_camera_fb_return(frame);sendError(request,"Invalid JPEG frame.");return;
  }
  sequence++;sendPacket(2,request,frame->buf,frame->len,frame->width,frame->height);
  esp_camera_fb_return(frame);
}
void processCommand() {
  char op[12]={};unsigned long request=0;
  if(sscanf(command,"%11s %lu",op,&request)!=2||!request)return;
  if(strcmp(op,"HELLO")==0)sendInfo(request);
  else if(strcmp(op,"CAP")==0)capture(request);
  else sendError(request,"Unknown command.");
}
void setup() {
  Serial.setTxBufferSize(4096);Serial.begin(BAUD);Serial.setDebugOutput(false);
  pinMode(4,OUTPUT);digitalWrite(4,LOW);
  WiFi.mode(WIFI_OFF);
  camera_config_t c={};c.ledc_channel=LEDC_CHANNEL_0;c.ledc_timer=LEDC_TIMER_0;
  c.pin_d0=Y2_GPIO_NUM;c.pin_d1=Y3_GPIO_NUM;c.pin_d2=Y4_GPIO_NUM;c.pin_d3=Y5_GPIO_NUM;
  c.pin_d4=Y6_GPIO_NUM;c.pin_d5=Y7_GPIO_NUM;c.pin_d6=Y8_GPIO_NUM;c.pin_d7=Y9_GPIO_NUM;
  c.pin_xclk=XCLK_GPIO_NUM;c.pin_pclk=PCLK_GPIO_NUM;c.pin_vsync=VSYNC_GPIO_NUM;c.pin_href=HREF_GPIO_NUM;
  c.pin_sccb_sda=SIOD_GPIO_NUM;c.pin_sccb_scl=SIOC_GPIO_NUM;c.pin_pwdn=PWDN_GPIO_NUM;c.pin_reset=RESET_GPIO_NUM;
  c.xclk_freq_hz=20000000;c.pixel_format=PIXFORMAT_JPEG;c.frame_size=FRAMESIZE_QVGA;
  c.jpeg_quality=12;c.fb_count=psramFound()?2:1;
  c.fb_location=psramFound()?CAMERA_FB_IN_PSRAM:CAMERA_FB_IN_DRAM;
  c.grab_mode=psramFound()?CAMERA_GRAB_LATEST:CAMERA_GRAB_WHEN_EMPTY;
  cameraError=esp_camera_init(&c);cameraReady=cameraError==ESP_OK;
  if(cameraReady) {
    sensor_t *sensor=esp_camera_sensor_get();sensorPid=sensor?sensor->id.PID:0;
    const uint32_t start=millis();
    while(millis()-start<500) {camera_fb_t *frame=esp_camera_fb_get();if(!frame)break;esp_camera_fb_return(frame);}
  }
  // No ASCII logs on the image channel. HELLO reports structured diagnostics.
}
void loop() {
  while(Serial.available()) {
    const char ch=Serial.read();
    if(ch=='\n') {command[commandSize]=0;processCommand();commandSize=0;}
    else if(ch!='\r') {
      if(commandSize<sizeof(command)-1)command[commandSize++]=ch;
      else commandSize=0;
    }
  }
  delay(1);
}
