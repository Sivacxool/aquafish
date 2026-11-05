#include "sensor_ph.h"
#include "sensor_config.h"
#include "ph_calibration.h"
#include <Wire.h>
#include <Preferences.h>
#include <time.h>
#include <freertos/semphr.h>

namespace ph_sensor {
namespace {
// ADS1115: A0 single ended, +/-4.096V PGA, single shot, 128 SPS,
// comparator disabled. PGA range does NOT permit input above ADC VDD.
constexpr uint16_t ADC_CONFIG=0xC383;
constexpr uint32_t SAMPLE_MS=100,RESCAN_MS=2000,STALE_MS=5000;
constexpr uint8_t WINDOW=20;
SemaphoreHandle_t mutex=nullptr;
struct Guard { Guard(){xSemaphoreTake(mutex,portMAX_DELAY);} ~Guard(){xSemaphoreGive(mutex);} };
Preferences storage;
bool storageReady=false,wireReady=false,found=false,converting=false;
uint32_t lastAttempt=0,lastProbe=0,started=0;
float window[WINDOW]={};uint8_t windowCount=0,windowIndex=0;
struct Sample {
  float voltage=NAN;
  uint32_t atMs=0;time_t atUnix=0;
  bool stable=false,detected=false;
  const char *status="adc_not_found";
} sample;
ph_math::Calibration calibration;
time_t calibratedAt=0;

bool writeRegister(uint8_t reg,uint16_t value) {
  Wire.beginTransmission(PH_ADS_ADDRESS);Wire.write(reg);
  Wire.write((uint8_t)(value>>8));Wire.write((uint8_t)value);
  return Wire.endTransmission()==0;
}
bool readRegister(uint8_t reg,uint16_t &value) {
  Wire.beginTransmission(PH_ADS_ADDRESS);Wire.write(reg);
  if(Wire.endTransmission(false)!=0)return false;
  if(Wire.requestFrom(PH_ADS_ADDRESS,(uint8_t)2)!=(size_t)2)return false;
  value=((uint16_t)Wire.read()<<8)|(uint8_t)Wire.read();return true;
}
void fail(const char *status,bool detected=false) {
  windowCount=0;windowIndex=0;
  Guard lock;sample.voltage=NAN;sample.stable=false;
  sample.status=status;sample.detected=detected;
}
void timestamp(JsonObject t,const char *key,time_t value) {
  t[key]=nullptr;
  if(value>=1735689600) {
    struct tm utc;gmtime_r(&value,&utc);char text[32];
    strftime(text,sizeof(text),"%Y-%m-%dT%H:%M:%SZ",&utc);t[key]=text;
  }
}
bool save(const ph_math::Calibration &next,time_t at) {
  if(!storageReady)return false;
  JsonDocument doc;
  if(isfinite(next.neutralVoltage))doc["neutral_voltage"]=next.neutralVoltage;
  if(isfinite(next.acidVoltage))doc["acid_voltage"]=next.acidVoltage;
  doc["neutral_ph"]=next.neutralPh;doc["acid_ph"]=next.acidPh;doc["at"]=(int64_t)at;
  String encoded;serializeJson(doc,encoded);
  return storage.putString("calibration_v1",encoded)==encoded.length();
}
}

void begin() {
  mutex=xSemaphoreCreateMutex();
  storageReady=storage.begin("aqua_ph",false);
  if(storageReady) {
    JsonDocument doc;
    if(!deserializeJson(doc,storage.getString("calibration_v1",""))) {
      if(doc["neutral_voltage"].is<float>())calibration.neutralVoltage=doc["neutral_voltage"];
      if(doc["acid_voltage"].is<float>())calibration.acidVoltage=doc["acid_voltage"];
      calibration.neutralPh=doc["neutral_ph"]|7.00f;calibration.acidPh=doc["acid_ph"]|4.00f;
      calibratedAt=doc["at"]|(int64_t)0;
    }
  }
  wireReady=Wire.begin(PH_SDA_PIN,PH_SCL_PIN,100000);
  Wire.setTimeOut(20);
}

void tick() {
  const uint32_t now=millis();
  if(!wireReady)return;
  if(!found) {
    if(now-lastProbe<RESCAN_MS)return;
    lastProbe=now;Wire.beginTransmission(PH_ADS_ADDRESS);
    found=Wire.endTransmission()==0;
    if(!found){fail("adc_not_found");return;}
  }
  if(converting) {
    if(now-started<10)return;
    uint16_t config=0;
    if(!readRegister(1,config)){converting=false;found=false;fail("read_error");return;}
    if((config&0x7fff)!=(ADC_CONFIG&0x7fff)){converting=false;found=false;fail("config_mismatch");return;}
    if(!(config&0x8000)) {
      if(now-started>100){converting=false;found=false;fail("conversion_timeout");}
      return;
    }
    converting=false;
    uint16_t raw=0;
    if(!readRegister(0,raw)){found=false;fail("read_error");return;}
    const float voltage=(int16_t)raw*0.000125f;
    if(!ph_math::inputValid(voltage)){fail("input_out_of_range",true);return;}
    window[windowIndex]=voltage;windowIndex=(windowIndex+1)%WINDOW;
    if(windowCount<WINDOW)windowCount++;
    float sum=0,low=window[0],high=window[0];
    for(uint8_t i=0;i<windowCount;i++){sum+=window[i];low=fminf(low,window[i]);high=fmaxf(high,window[i]);}
    Guard lock;sample.voltage=sum/windowCount;sample.atMs=now;sample.atUnix=time(nullptr);
    sample.stable=windowCount==WINDOW && high-low<=0.010f;
    sample.status=windowCount==WINDOW?"ready":"warming_up";sample.detected=true;
  }
  if(!converting && now-lastAttempt>=SAMPLE_MS) {
    lastAttempt=now;
    if(!writeRegister(1,ADC_CONFIG)){found=false;fail("adc_not_found");return;}
    started=now;converting=true;
  }
}

bool calibrate(float bufferPh,bool startNew,String &message) {
  Guard lock;
  if(!sample.detected || !isfinite(sample.voltage) || millis()-sample.atMs>STALE_MS) {
    message="ยังอ่าน ADS1115 ไม่ได้ ตรวจสาย SDA GPIO8 / SCL GPIO9 และ A0";return false;
  }
  if(!sample.stable){message="แรงดันยังไม่นิ่ง รอหัววัดในน้ำยามาตรฐานแล้วลองอีกครั้ง";return false;}
  ph_math::Calibration next=calibration;
  if(ph_math::neutralReference(bufferPh)) {
    if(!startNew){message="เริ่มรอบสอบเทียบใหม่ที่น้ำยา pH 7.00 หรือ 6.86 ก่อน";return false;}
    next=ph_math::Calibration();next.neutralPh=bufferPh;next.neutralVoltage=sample.voltage;
  } else if(ph_math::acidReference(bufferPh)) {
    if(startNew || !ph_math::inputValid(next.neutralVoltage)){message="บันทึกจุด pH 7.00 / 6.86 ก่อน";return false;}
    next.acidPh=bufferPh;next.acidVoltage=sample.voltage;
    if(!next.valid()){message="แรงดันสองจุดใกล้กันเกินไป ตรวจน้ำยามาตรฐานและหัววัด";return false;}
  } else {message="เลือกน้ำยา 7.00 / 6.86 และ 4.00 / 4.01 ตามฉลาก";return false;}
  const time_t at=next.valid()?time(nullptr):0;
  if(!save(next,at)){message="บันทึกการสอบเทียบบน S3 ไม่สำเร็จ";return false;}
  calibration=next;calibratedAt=at;
  message=next.valid()?"บันทึกสอบเทียบ pH สองจุดแล้ว":"บันทึกจุดแรกแล้ว ล้างหัววัดและย้ายไปน้ำยา pH 4";
  return true;
}

void append(JsonObject t) {
  Sample current;ph_math::Calibration cal;time_t at;
  {Guard lock;current=sample;cal=calibration;at=calibratedAt;}
  const bool stale=isfinite(current.voltage) && millis()-current.atMs>STALE_MS;
  const bool ready=!stale && strcmp(current.status,"ready")==0;
  float ph=ready?cal.value(current.voltage):NAN;
  const char *status=stale?"stale":current.status;
  if(ready)status=!cal.valid()?"not_calibrated":isfinite(ph)?"ok":"ph_out_of_range";
  t["ph"]=nullptr;if(isfinite(ph))t["ph"]=ph;
  t["ph_status"]=status;t["ph_calibrated"]=cal.valid();timestamp(t,"ph_calibrated_at",at);
  t["ph_adc_voltage"]=nullptr;if(!stale&&isfinite(current.voltage))t["ph_adc_voltage"]=current.voltage;
  t["ph_stable"]=!stale&&current.stable;timestamp(t,"ph_sampled_at",current.atUnix);
  JsonObject c=t["ph_calibration"].to<JsonObject>();
  c["neutral_ph"]=cal.neutralPh;c["acid_ph"]=cal.acidPh;
  if(isfinite(cal.neutralVoltage))c["neutral_voltage"]=cal.neutralVoltage;
  if(isfinite(cal.acidVoltage))c["acid_voltage"]=cal.acidVoltage;
  JsonObject sensor=t["sensors"]["ph"].to<JsonObject>();
  sensor["probe"]="E-201-C";sensor["frontend"]="PH-4502C";sensor["adc"]="ADS1115";
  sensor["sda_gpio"]=PH_SDA_PIN;sensor["scl_gpio"]=PH_SCL_PIN;sensor["address"]=PH_ADS_ADDRESS;
  sensor["channel"]="A0";sensor["adc_detected"]=current.detected;sensor["divider_ratio"]=0.5;
}
}
