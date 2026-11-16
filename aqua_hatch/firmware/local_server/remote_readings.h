#pragma once
#include <AquaRelay.h>
#include <atomic>
#include <memory>
#include <new>
#include <freertos/queue.h>

namespace remote_readings {
struct Upload { String origin, body; };
QueueHandle_t pending = nullptr;
std::atomic<int> lastResult{0};
uint32_t lastQueued = 0;

void sender(void *) {
  const aqua_relay::Keys keys(API_TOKEN);
  for (;;) {
    Upload *next = nullptr;
    if (xQueueReceive(pending, &next, portMAX_DELAY) != pdTRUE) continue;
    std::unique_ptr<Upload> upload(next);
    if (upload->origin != aqua_relay::origin(prefs) || WiFi.status() != WL_CONNECTED) continue;
    lastResult.store(aqua_relay::postJson(
      upload->origin + "/v1/readings/" + keys.room, keys.writer, upload->body));
#if defined(AQUAHATCH_ET_WROOM32UE)
    if (upload->origin == aqua_relay::origin(prefs)) ett_camera::relayCapture(upload->origin, keys);
#endif
  }
}

void tick() {
  if (WiFi.status() != WL_CONNECTED || time(nullptr) < 1735689600) return;
  const uint32_t now = millis();
  if (now - lastQueued < 12000) return;
  lastQueued = now;
  const String url = aqua_relay::origin(prefs);
  if (url.isEmpty()) return;
  if (!pending) {
#if defined(AQUAHATCH_ET_WROOM32UE)
    const uint32_t stackSize = 12288;
#else
    const uint32_t stackSize = 8192;
#endif
    pending = xQueueCreate(1, sizeof(Upload *));
    if (!pending) return;
    if (xTaskCreate(sender, "aqua-readings", stackSize, nullptr, 1, nullptr) != pdPASS) {
      vQueueDelete(pending);
      pending = nullptr;
      return;
    }
  }

  auto *upload = new (std::nothrow) Upload;
  if (!upload) return;
  upload->origin = url;
  JsonDocument data;
  snapshot(data);
  data.remove("config");
  data.remove("capabilities");
  data.remove("command_count");
  data.remove("uptime_ms");
  auto telemetry = data["telemetry"].as<JsonObject>();
  telemetry.remove("outputs");
  telemetry.remove("hardware_message");
  serializeJson(data, upload->body);
  if (xQueueSend(pending, &upload, 0) != pdTRUE) delete upload;
}
}
