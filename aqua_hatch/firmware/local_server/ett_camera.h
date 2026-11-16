#pragma once
#include <LittleFS.h>
#include <esp_partition.h>
#include <freertos/semphr.h>
#include "arducam_b0434.h"

namespace ett_camera {
constexpr char PhotoPath[] = "/b0434.jpg";
constexpr size_t PhotoLimit = 1500000;
constexpr uint32_t PhotoTtl = 90000;

enum class Stage { idle, queued, capturing, captured, failed, expired };
struct Photo {
  size_t start = 0, length = 0;
  String sha, receivedAt;
};
struct Job {
  String id;
  arducam_b0434::ImageConfig config;
  bool fullSize = true;
  Stage stage = Stage::idle;
  time_t expires = 0;
  uint32_t readyAt = 0;
  const char *problem = "";
  Photo photo;
};
Job job;
SemaphoreHandle_t mutex = nullptr;
std::atomic<bool> online{false};
bool configured = false;
String cameraId;

struct Lock {
  bool held = mutex && xSemaphoreTake(mutex, pdMS_TO_TICKS(50)) == pdTRUE;
  Lock() = default;
  Lock(const Lock &) = delete;
  ~Lock() { if (held) xSemaphoreGive(mutex); }
  explicit operator bool() const { return held; }
};

bool validId(const String &id) {
  if (id.isEmpty() || id.length() > 64) return false;
  for (const char c : id) {
    if (!isalnum(static_cast<unsigned char>(c)) && c != '-' && c != '_') return false;
  }
  return true;
}

void identity(JsonDocument &data) {
  data["backend"] = "esp32-camera";
  data["protocol_version"] = 1;
  data["camera_id"] = cameraId;
  data["device_id"] = cameraId;
  data["server_time_unix"] = time(nullptr);
}

void status(JsonDocument &data) {
  identity(data);
  data["configured"] = configured;
  data["online"] = online.load();
  data["sensor"] = "Arducam B0434";
  data["default_capture_width"] = 2048;
  data["default_capture_height"] = 1536;
  data["autofocus_supported"] = false;
  data["message"] = !configured ? "พื้นที่ภาพยังไม่พร้อม ให้ลงเฟิร์มแวร์ ETT พร้อมตารางพาร์ทิชัน"
    : online.load() ? "พร้อมถ่าย" : "ตรวจสาย SPI และไฟ 3.3 V ของ Arducam B0434";
}

void expire() {
  if (job.stage == Stage::captured && millis() - job.readyAt >= PhotoTtl) {
    job.stage = Stage::expired;
    LittleFS.remove(PhotoPath);
  }
}

void describe(JsonDocument &data) {
  expire();
  identity(data);
  data["capture_id"] = job.id;
  switch (job.stage) {
    case Stage::queued: data["status"] = "queued"; break;
    case Stage::capturing: data["status"] = "capturing"; break;
    case Stage::captured:
      data["status"] = "captured";
      data["received_at"] = job.photo.receivedAt;
      data["bytes"] = job.photo.length;
      data["sha256"] = job.photo.sha;
      data["width"] = job.fullSize ? 2048 : 640;
      data["height"] = job.fullSize ? 1536 : 480;
      data["sensor"] = "Arducam B0434";
      data["flash_used"] = false;
      break;
    case Stage::failed:
      data["status"] = "failed";
      data["message"] = job.problem;
      break;
    default: data["status"] = "expired"; break;
  }
}

enum class Submit { accepted, invalid, busy, unavailable };
Submit submit(const JsonDocument &options, JsonDocument &reply) {
  const String id = options["capture_id"] | "";
  const time_t now = time(nullptr);
  const int64_t expires = options["expires_at_unix"] | int64_t(0);
  const auto settings = options["arducam"].as<JsonObjectConst>();
  const String resolution = settings.isNull() ? options["resolution"] | "3mp"
                                               : settings["resolution"] | "";
  const String lighting = settings["lighting"] | "normal";
  arducam_b0434::ImageConfig config;
  if (!validId(id) || (resolution != "3mp" && resolution != "vga" && resolution != "sensor_max") ||
      !arducam_b0434::parseImageConfig(lighting, settings["settings"].as<JsonObjectConst>(), config)) {
    return Submit::invalid;
  }
  Lock lock;
  if (!lock) return Submit::busy;
  if (job.id == id) {
    describe(reply);
    return Submit::accepted;
  }
  if (now < 1735689600 || expires <= now || expires > now + 50) return Submit::invalid;
  if (!configured) return Submit::unavailable;
  if (job.stage == Stage::queued || job.stage == Stage::capturing) return Submit::busy;
  job = Job{};
  job.id = id;
  job.fullSize = resolution != "vga";
  job.config = config;
  job.expires = expires;
  job.stage = Stage::queued;
  describe(reply);
  return Submit::accepted;
}

bool savePhoto(Photo &photo) {
  const size_t total = arducam_b0434::total;
  if (total > PhotoLimit || total < 4) return false;
  File file = LittleFS.open(PhotoPath, FILE_WRITE);
  if (!file) return false;
  uint8_t bytes[2048];
  size_t written = 0;
  while (written < total) {
    const size_t count = arducam_b0434::read(bytes, sizeof(bytes));
    if (!count || file.write(bytes, count) != count) return false;
    written += count;
    vTaskDelay(1);
  }
  file.close();
  file = LittleFS.open(PhotoPath, FILE_READ);
  if (!file || file.size() != total) return false;

  // The module can pad the FIFO. Keep the JPEG from SOI to the last EOI.
  const size_t border = std::min<size_t>(total, 258);
  if (file.read(bytes, border) != border) return false;
  size_t start = 0;
  while (start + 1 < border && !(bytes[start] == 0xff && bytes[start + 1] == 0xd8)) ++start;
  if (start + 1 == border || !file.seek(total - border) || file.read(bytes, border) != border) return false;
  size_t last = border - 1;
  while (last && !(bytes[last - 1] == 0xff && bytes[last] == 0xd9)) --last;
  const size_t end = total - border + last + 1;
  if (!last || end < start + 4 || !file.seek(start)) return false;

  mbedtls_sha256_context hash;
  mbedtls_sha256_init(&hash);
  bool valid = mbedtls_sha256_starts(&hash, 0) == 0;
  for (size_t left = end - start; valid && left;) {
    const size_t count = std::min(left, sizeof(bytes));
    valid = file.read(bytes, count) == count && mbedtls_sha256_update(&hash, bytes, count) == 0;
    left -= count;
  }
  unsigned char digest[32];
  valid = valid && mbedtls_sha256_finish(&hash, digest) == 0;
  mbedtls_sha256_free(&hash);
  if (!valid) return false;
  char hex[65];
  for (size_t i = 0; i < sizeof(digest); ++i) snprintf(hex + 2 * i, 3, "%02x", digest[i]);
  photo = {start, end - start, String(hex), nowIso()};
  return !photo.receivedAt.isEmpty();
}

void run(void *) {
  uint32_t lastProbe = millis() - 4000;
  for (;;) {
    bool capture = false;
    arducam_b0434::ImageConfig config;
    bool fullSize = false;
    {
      Lock lock;
      if (lock) {
        expire();
        if (job.stage == Stage::queued) {
          if (time(nullptr) >= job.expires) {
            job.stage = Stage::expired;
          } else {
            config = job.config;
            fullSize = job.fullSize;
            job.stage = Stage::capturing;
            capture = true;
          }
        }
      }
    }
    if (capture) {
      arducam_b0434::begin(fullSize, config);
      while (arducam_b0434::working()) {
        arducam_b0434::tick();
        vTaskDelay(pdMS_TO_TICKS(10));
      }
      Photo photo;
      const bool captured = arducam_b0434::phase == arducam_b0434::Phase::Ready;
      const bool saved = captured && savePhoto(photo);
      if (!saved) LittleFS.remove(PhotoPath);
      online.store(captured || arducam_b0434::validSensor(arducam_b0434::sensorId));
      for (;;) {
        Lock lock;
        if (lock) {
          job.stage = saved ? Stage::captured : Stage::failed;
          job.photo = photo;
          job.readyAt = millis();
          job.problem = captured ? "บันทึก JPEG ไม่สำเร็จหรือภาพใหญ่เกินกำหนด"
                                 : arducam_b0434::failure;
          break;
        }
        vTaskDelay(1);
      }
    } else if (millis() - lastProbe >= 4000) {
      lastProbe = millis();
      online.store(arducam_b0434::probe());
    }
    vTaskDelay(pdMS_TO_TICKS(25));
  }
}

void begin() {
  cameraId = String("cam-") + boardIdentity.deviceId().substring(3);
  const auto *partition = esp_partition_find_first(ESP_PARTITION_TYPE_DATA, ESP_PARTITION_SUBTYPE_DATA_SPIFFS, "spiffs");
  if (!partition || partition->size < PhotoLimit + 65536) return;
  if (!LittleFS.begin(true, "/camera", 3)) return;
  LittleFS.remove(PhotoPath);
  mutex = xSemaphoreCreateMutex();
  if (!mutex) return;
  configured = true;
  if (xTaskCreate(run, "ett-camera", 8192, nullptr, 1, nullptr) != pdPASS) configured = false;
}

esp_err_t photoResponse(httpd_req_t *req) {
  File file = LittleFS.open(PhotoPath, FILE_READ);
  if (!file || !file.seek(job.photo.start)) return error(req, "500 Internal Server Error", "เปิดไฟล์ภาพไม่สำเร็จ");
  httpd_resp_set_type(req, "image/jpeg");
  httpd_resp_set_hdr(req, "Cache-Control", "no-store");
  httpd_resp_set_hdr(req, "X-Capture-ID", job.id.c_str());
  uint8_t bytes[2048];
  for (size_t left = job.photo.length; left;) {
    const size_t count = std::min(left, sizeof(bytes));
    if (file.read(bytes, count) != count ||
        httpd_resp_send_chunk(req, reinterpret_cast<char *>(bytes), count) != ESP_OK) return ESP_FAIL;
    left -= count;
  }
  return httpd_resp_send_chunk(req, nullptr, 0);
}

esp_err_t handle(httpd_req_t *req, const String &suffix) {
  JsonDocument data;
  if (suffix.isEmpty() && req->method == HTTP_GET) {
    status(data);
    return sendJson(req, "200 OK", data);
  }
  if (suffix == "/captures" && req->method == HTTP_POST) {
    char body[1536];
    if (!req->content_len || req->content_len >= sizeof(body)) return error(req, "400 Bad Request", "ตรวจค่าการถ่ายภาพ");
    size_t length = 0;
    while (length < req->content_len) {
      const int count = httpd_req_recv(req, body + length, req->content_len - length);
      if (count <= 0) return ESP_FAIL;
      length += count;
    }
    JsonDocument request;
    if (deserializeJson(request, body, length)) return error(req, "400 Bad Request", "ตรวจค่าการถ่ายภาพ");
    switch (submit(request, data)) {
      case Submit::accepted: return sendJson(req, "202 Accepted", data);
      case Submit::busy: return error(req, "409 Conflict", "กล้องกำลังทำงาน ลองใหม่อีกครั้ง");
      case Submit::unavailable: return error(req, "503 Service Unavailable", "กล้องยังไม่พร้อม");
      default: return error(req, "422 Unprocessable Entity", "ตรวจค่าการถ่ายภาพและเวลาของบอร์ด");
    }
  }
  if (!suffix.startsWith("/captures/") || req->method != HTTP_GET)
    return error(req, "404 Not Found", "ไม่พบคำสั่งกล้อง");
  const bool image = suffix.endsWith("/image");
  const String id = suffix.substring(10, suffix.length() - (image ? 6 : 0));
  Lock lock;
  if (!lock) return error(req, "503 Service Unavailable", "กล้องกำลังส่งภาพ");
  if (!validId(id) || job.id != id) return error(req, "404 Not Found", "ไม่พบภาพของคำขอนี้");
  describe(data);
  if (!image) return sendJson(req, "200 OK", data);
  if (job.stage != Stage::captured) return error(req, "409 Conflict", "ภาพยังไม่พร้อมหรือหมดอายุ");
  return photoResponse(req);
}
}
