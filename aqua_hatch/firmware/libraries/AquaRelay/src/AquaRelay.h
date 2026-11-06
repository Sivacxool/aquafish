#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <WiFiClientSecure.h>
#include <esp_https_server.h>
#include <mbedtls/sha256.h>

namespace aqua_relay {
inline bool validLabel(const String &label) {
  if (label.isEmpty() || label.length() > 63 || label.startsWith("-") || label.endsWith("-")) return false;
  for (const char c : label) {
    if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-')) return false;
  }
  return true;
}

inline bool validOrigin(const String &url) {
  if (!url.startsWith("https://") || !url.endsWith(".workers.dev") || url.length() > 147) return false;
  const String labels = url.substring(8, url.length() - 12);
  const int dot = labels.indexOf('.');
  return dot > 0 && validLabel(labels.substring(0, dot)) && validLabel(labels.substring(dot + 1));
}

inline String sha256(const String &text) {
  unsigned char digest[32];
  mbedtls_sha256(reinterpret_cast<const unsigned char *>(text.c_str()), text.length(), digest, 0);
  static constexpr char hex[] = "0123456789abcdef";
  String result;
  result.reserve(64);
  for (const uint8_t byte : digest) {
    result += hex[byte >> 4];
    result += hex[byte & 15];
  }
  return result;
}

struct Keys {
  String writer, room;
  explicit Keys(const String &token) {
    writer = sha256(String("aquahatch relay write v1:") + token);
    const String reader = sha256(String("aquahatch relay read v1:") + writer);
    room = sha256(String("aquahatch relay room v1:") + reader);
  }
};

inline String origin(Preferences &prefs) {
  const String url = prefs.getString("relay_origin", "");
  return validOrigin(url) ? url : String();
}

inline bool configure(Preferences &prefs, const String &url) {
  if (!url.isEmpty()) return validOrigin(url) && prefs.putString("relay_origin", url) == url.length();
  return !prefs.isKey("relay_origin") || prefs.remove("relay_origin");
}

inline bool readConfiguration(httpd_req_t *request, String &url) {
  char bytes[192];
  const size_t length = request->content_len;
  if (length == 0 || length >= sizeof(bytes)) return false;
  size_t received = 0;
  while (received < length) {
    const int count = httpd_req_recv(request, bytes + received, length - received);
    if (count <= 0) return false;
    received += count;
  }
  JsonDocument data;
  if (deserializeJson(data, bytes, received) || !data["url"].is<String>()) return false;
  url = data["url"].as<String>();
  return url.isEmpty() || validOrigin(url);
}

class BoundedReply : public Stream {
  String &target;
 public:
  explicit BoundedReply(String &output) : target(output) {}
  int available() override { return 0; }
  int read() override { return -1; }
  int peek() override { return -1; }
  void flush() override {}
  size_t write(uint8_t byte) override { return write(&byte, 1); }
  size_t write(const uint8_t *bytes, size_t length) override {
    if (target.length() + length > 4096) return 0;
    return target.concat(reinterpret_cast<const char *>(bytes), length) ? length : 0;
  }
};

inline int post(
    const String &url, const String &writer, const char *contentType,
    uint8_t *bytes, size_t size, String *reply = nullptr, const String &photoMetadata = "") {
  WiFiClientSecure tls;
  tls.useBuiltinCACertBundle();
  tls.setHandshakeTimeout(6);
  HTTPClient http;
  http.setConnectTimeout(3500);
  http.setTimeout(8000);
  http.setFollowRedirects(HTTPC_DISABLE_FOLLOW_REDIRECTS);
  if (!http.begin(tls, url)) return -1;
  http.addHeader("Authorization", String("Bearer ") + writer);
  http.addHeader("Content-Type", contentType);
  if (!photoMetadata.isEmpty()) http.addHeader("X-AquaHatch-Photo", photoMetadata);
  int result = http.POST(bytes, size);
  if (reply && result == HTTP_CODE_OK) {
    BoundedReply output(*reply);
    const int read = http.writeToStream(&output);
    if (read < 0) result = read;
  }
  http.end();
  return result;
}

inline int postJson(const String &url, const String &writer, const String &data, String *reply = nullptr) {
  return post(url, writer, "application/json",
              reinterpret_cast<uint8_t *>(const_cast<char *>(data.c_str())), data.length(), reply);
}
}
