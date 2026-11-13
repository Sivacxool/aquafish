#include "AquaIdentity.h"
#include "AquaCertificates.h"
#include <esp_random.h>
#include <esp_mac.h>
#include <mbedtls/base64.h>
#include <cstring>

namespace {
int randomBytes(void*,unsigned char *output,size_t length){esp_fill_random(output,length);return 0;}
String hex(const unsigned char *data,size_t size){const char *digits="0123456789abcdef";String result;result.reserve(size*2);for(size_t i=0;i<size;i++){result+=digits[data[i]>>4];result+=digits[data[i]&15];}return result;}
String base64Url(const std::string &data){size_t length=0;mbedtls_base64_encode(nullptr,0,&length,(const unsigned char*)data.data(),data.size());std::string result(length+1,'\0');if(mbedtls_base64_encode((unsigned char*)&result[0],result.size(),&length,(const unsigned char*)data.data(),data.size())!=0)return "";String text(result.substr(0,length).c_str());text.replace("+","-");text.replace("/","_");text.replace("=","");return text;}
void dateText(time_t value,char output[16]){struct tm utc;gmtime_r(&value,&utc);strftime(output,16,"%Y%m%d%H%M%S",&utc);}
time_t buildTime(){struct tm t={};char month[4]={};int day=0,year=0;sscanf(__DATE__,"%3s %d %d",month,&day,&year);const char *months="JanFebMarAprMayJunJulAugSepOctNovDec";const char *found=strstr(months,month);t.tm_mon=found?(found-months)/3:0;t.tm_mday=day;t.tm_year=year-1900;t.tm_isdst=0;setenv("TZ","UTC0",1);tzset();return mktime(&t);}
}
bool AquaIdentity::begin(const char *kind){
  if(strcmp(kind,"s3")&&strcmp(kind,"camera")){error_="invalid_kind";return false;}
  kind_=kind;unsigned char mac[6];if(esp_read_mac(mac,ESP_MAC_WIFI_STA)!=ESP_OK){error_="mac_read_failed";return false;}
  mac_=hex(mac,sizeof(mac));id_=(kind_=="s3"?"s3-":"cam-")+mac_;
  host_="aquahatch-"+id_+".local";
  String tail=mac_.substring(6);tail.toUpperCase();
  ssid_=(kind_=="s3"?"Smart Catfish System-B-":"Smart Catfish System-C-")+tail;
  if(!storage_.begin("aqua_ident",false)){error_="identity_storage_unavailable";return false;}
  if(storage_.isKey("record_v1")){
    String record=storage_.getString("record_v1","");
    if(!load(record)){error_="identity_record_invalid_recovery_required";return false;}
  }else if(!generate()){if(error_.isEmpty())error_="identity_generation_failed";return false;}
  const time_t now=buildTime();if(needsRenewal(now)&&!renew(now)){error_="identity_certificate_renewal_failed";return false;}
  return true;
}
bool AquaIdentity::load(const String &record){
  JsonDocument doc;if(deserializeJson(doc,record)||doc["version"]!=1||doc["kind"]!=kind_||doc["mac"]!=mac_)return false;
  token_=doc["token"]|"";caCert_=doc["ca_cert"]|"";caKey_=doc["ca_key"]|"";serverCert_=doc["server_cert"]|"";serverKey_=doc["server_key"]|"";
  from_=doc["from"]|(int64_t)0;until_=doc["until"]|(int64_t)0;
  if(token_.length()!=64||from_<1735689600||until_-from_!=730L*86400L)return false;
  for(char c:token_)if(!isxdigit((unsigned char)c))return false;
  return aqua_cert::matchingKey(caCert_.c_str(),caKey_.c_str(),randomBytes,nullptr)&&aqua_cert::matchingKey(serverCert_.c_str(),serverKey_.c_str(),randomBytes,nullptr);
}
bool AquaIdentity::save(const String &certificate,time_t from,time_t until){
  JsonDocument doc;doc["version"]=1;doc["kind"]=kind_;doc["mac"]=mac_;doc["token"]=token_;
  doc["ca_cert"]=caCert_;doc["ca_key"]=caKey_;doc["server_cert"]=certificate;doc["server_key"]=serverKey_;
  doc["from"]=(int64_t)from;doc["until"]=(int64_t)until;String encoded;serializeJson(doc,encoded);
  if(storage_.putString("record_v1",encoded)!=encoded.length()){error_="identity_commit_failed";return false;}
  if(storage_.getString("record_v1","")!=encoded){error_="identity_readback_failed";return false;}
  serverCert_=certificate;from_=from;until_=until;return true;
}
bool AquaIdentity::generate(){
  unsigned char secret[32];esp_fill_random(secret,sizeof(secret));token_=hex(secret,sizeof(secret));memset(secret,0,sizeof(secret));
  std::string caKey,leafKey,ca;
  if(!aqua_cert::generateKey(randomBytes,nullptr,caKey)||!aqua_cert::generateKey(randomBytes,nullptr,leafKey))return false;
  const std::string subject="O=AquaHatch,CN=AquaHatch CA "+std::string(id_.c_str());
  if(!aqua_cert::issue(caKey,caKey,subject,subject,"",true,"20000101000000","20990101000000",randomBytes,nullptr,ca))return false;
  caKey_=caKey.c_str();serverKey_=leafKey.c_str();caCert_=ca.c_str();return renew(buildTime());
}
bool AquaIdentity::needsRenewal(time_t now)const{return now>=1735689600&&(now<from_||now>=until_-30L*86400L);}
bool AquaIdentity::renew(time_t now){
  if(now<1735689600)return false;
  const time_t from=now-86400,until=from+730L*86400L;char first[16],last[16];dateText(from,first);dateText(until,last);
  const std::string subject="O=AquaHatch,CN="+std::string(host_.c_str());
  const std::string issuer="O=AquaHatch,CN=AquaHatch CA "+std::string(id_.c_str());std::string certificate;
  if(!aqua_cert::issue(serverKey_.c_str(),caKey_.c_str(),subject,issuer,host_.c_str(),false,first,last,randomBytes,nullptr,certificate))return false;
  return save(certificate.c_str(),from,until);
}
void AquaIdentity::pairing(JsonDocument &response)const{
  std::string der;if(!aqua_cert::publicDer(caCert_.c_str(),der)){response["type"]="pairing_error";return;}
  response["type"]="pairing";JsonObject p=response["payload"].to<JsonObject>();
  p["format"]="aquahatch-pairing";p["version"]=1;p["kind"]=kind_;p["id"]=id_;p["host"]=host_;p["ssid"]=ssid_;p["token"]=token_;p["ca"]=base64Url(der);
}
