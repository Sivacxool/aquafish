#include "AquaIdentity.h"
#include <esp_mac.h>
#include <mbedtls/ctr_drbg.h>
#include <mbedtls/entropy.h>
#include <cassert>
#include <iostream>
#include <ctime>
#include <fstream>
#include <filesystem>
mbedtls_ctr_drbg_context hostRandom;
void esp_fill_random(void *buffer,size_t length){assert(mbedtls_ctr_drbg_random(&hostRandom,(unsigned char*)buffer,length)==0);}
int main(int argc,char **argv){
  mbedtls_entropy_context entropy;mbedtls_entropy_init(&entropy);mbedtls_ctr_drbg_init(&hostRandom);
  assert(mbedtls_ctr_drbg_seed(&hostRandom,mbedtls_entropy_func,&entropy,(const unsigned char*)"first boot",10)==0);
  AquaIdentity first;assert(first.begin("s3"));assert(mockWriteCount==1);
  const String token=first.token(),root=mockNvs["aqua_ident:record_v1"],host=first.hostname();
  assert(token.length()==64&&first.deviceId()=="s3-aabbccddee01");
  assert(first.setupSsid()=="AquaHatch-S3-DDEE01");
  AquaIdentity restarted;assert(restarted.begin("s3"));assert(restarted.token()==token&&restarted.hostname()==host&&mockWriteCount==1);
  JsonDocument publicCard;restarted.pairing(publicCard);assert(publicCard["type"]=="pairing");
  assert(publicCard["payload"]["token"]==token);assert(publicCard["payload"]["ca"].is<String>());
  assert(!publicCard["payload"]["ca_key"].is<String>()&&!publicCard["payload"]["server_key"].is<String>());
  if(argc==2){
    const std::filesystem::path output=argv[1];std::filesystem::create_directories(output);
    JsonDocument stored;assert(!deserializeJson(stored,mockNvs["aqua_ident:record_v1"]));
    std::ofstream(output/"ca.pem")<<stored["ca_cert"].as<const char*>();
    std::ofstream(output/"server.pem")<<first.serverCertificate().c_str();
    std::ofstream(output/"server-key.pem")<<first.serverKey().c_str();
    std::ofstream payloadFile(output/"pairing.json");serializeJson(publicCard["payload"],payloadFile);
  }
  const String oldCertificate=restarted.serverCertificate();mockFailWrites=true;
  assert(!restarted.renew(std::time(nullptr)+700LL*86400));assert(restarted.serverCertificate()==oldCertificate);
  assert(mockNvs["aqua_ident:record_v1"]==std::string(root.c_str()));mockFailWrites=false;
  assert(restarted.renew(std::time(nullptr)+700LL*86400));assert(restarted.token()==token);
  JsonDocument renewed;restarted.pairing(renewed);assert(renewed["payload"]["ca"]==publicCard["payload"]["ca"]);
  mockNvs["aqua_ident:record_v1"]="corrupted";const auto writes=mockWriteCount;
  AquaIdentity corrupt;assert(!corrupt.begin("s3"));assert(mockWriteCount==writes);
  mockNvs.clear();mockMac[5]=2;AquaIdentity other;assert(other.begin("s3"));assert(other.token()!=token&&other.deviceId()=="s3-aabbccddee02");
  JsonDocument otherCard;other.pairing(otherCard);assert(otherCard["payload"]["ca"]!=publicCard["payload"]["ca"]);
  mockNvs.clear();mockMac[5]=3;AquaIdentity camera;assert(camera.begin("camera"));assert(camera.deviceId()=="cam-aabbccddee03");assert(camera.setupSsid()=="AquaHatch-CAM-DDEE03");
  mockNvs.clear();mockFailWrites=true;AquaIdentity failure;assert(!failure.begin("s3"));assert(mockNvs.empty());
  mbedtls_ctr_drbg_free(&hostRandom);mbedtls_entropy_free(&entropy);
  std::cout<<"PASS actual identity source with simulated NVS/hardware: first boot, distinct boards, restart persistence, atomic failure, corruption, renewal\n";
}
