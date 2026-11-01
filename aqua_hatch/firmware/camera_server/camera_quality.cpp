// Sensor AF implementation from Espressif, Apache-2.0. See third_party/.
// Build this optional helper locally because the installed Arduino camera
// library has AF disabled. Only public sensor register access is used.
#include <Arduino.h>
#include "camera_quality.h"
#undef CONFIG_CAMERA_AF_SUPPORT
#define CONFIG_CAMERA_AF_SUPPORT 1
#define ov5640_af_is_supported aqua_ov5640_af_is_supported
#define ov5640_af_init aqua_ov5640_af_init
#define ov5640_af_set_mode aqua_ov5640_af_set_mode
#define ov5640_af_trigger aqua_ov5640_af_trigger
#define ov5640_af_get_status aqua_ov5640_af_get_status
#define ov5640_af_set_manual_position aqua_ov5640_af_set_manual_position
#include "third_party/esp32_camera_af/ov5640_af.c"
#undef CONFIG_CAMERA_AF_SUPPORT

AquaFocusResult aquaPrepareFocus(sensor_t *sensor, bool requested) {
  AquaFocusResult result;result.requested=requested;
  if(!requested)return result;
  if(!sensor||sensor->id.PID!=OV5640_PID) {result.status="not_supported_sensor";return result;}
  const uint32_t start=millis();
  result.firmwareReady=aqua_ov5640_af_init(sensor,2000)==0;
  result.initMs=millis()-start;
  result.status=result.firmwareReady?"ready":"af_init_failed";
  return result;
}
void aquaRunFocus(sensor_t *sensor, AquaFocusResult &result) {
  if(!result.firmwareReady)return;
  const uint32_t start=millis();
  if(aqua_ov5640_af_trigger(sensor)!=0) {result.status="af_trigger_failed";result.searchMs=millis()-start;return;}
  while(millis()-start<3000) {
    bool busy=false,focused=false;uint8_t raw=0;
    if(aqua_ov5640_af_get_status(sensor,&raw,&focused,&busy)!=0) {result.status="af_status_read_failed";break;}
    result.raw=raw;
    if(focused) {result.focused=true;result.status="focused";break;}
    result.status="not_focused";delay(20);
  }
  result.searchMs=millis()-start;
}
