#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <time.h>

class AquaIdentity {
public:
  // Call after Wi-Fi is enabled, before starting TLS or sensor/camera tasks.
  bool begin(const char *kind);
  const String &deviceId() const {return id_;}
  const String &hostname() const {return host_;}
  String mdnsName() const {return host_.substring(0,host_.length()-6);}
  const String &token() const {return token_;}
  const String &serverCertificate() const {return serverCert_;}
  const String &serverKey() const {return serverKey_;}
  const String &setupSsid() const {return ssid_;}
  const String &error() const {return error_;}
  bool needsRenewal(time_t now) const;
  // Stop TLS first. On failure the previous committed certificate is retained.
  bool renew(time_t now);
  void pairing(JsonDocument &response) const; // Private USB command only.
private:
  Preferences storage_;
  String kind_,mac_,id_,host_,ssid_,token_,caCert_,caKey_,serverCert_,serverKey_,error_;
  time_t from_=0,until_=0;
  bool save(const String &certificate,time_t from,time_t until);
  bool load(const String &record);
  bool generate();
};
