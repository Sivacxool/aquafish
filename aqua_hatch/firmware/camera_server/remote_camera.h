#pragma once
#include <atomic>

namespace remote_camera {
TaskHandle_t task = nullptr;
std::atomic<int> lastResult{0};
uint32_t lastStartCheck = 0;

void poll(const String &url, const aqua_relay::Keys &keys) {
  const String endpoint = url + "/v1/cameras/" + keys.room + "/agent";
  String state;
  {
    CameraGuard guard;
    if (!guard) return;
    if (!cameraReady && millis() - lastCameraProbeAt > 15000) initCamera();
    JsonDocument snapshot;
    status(snapshot);
    snapshot.remove("ip");
    serializeJson(snapshot, state);
  }

  String response;
  const int code = aqua_relay::postJson(endpoint, keys.writer, state, &response);
  lastResult.store(code);
  if (code != 200 || url != aqua_relay::origin(prefs)) return;
  JsonDocument incoming;
  if (deserializeJson(incoming, response) || !incoming["job"].is<JsonObject>()) return;
  JsonDocument options;
  options.set(incoming["job"]);
  const String id = options["capture_id"] | "";
  if (!validId(id)) return;

  int uploaded = 0;
  {
    CameraGuard guard;
    if (guard) {
      JsonDocument metadata;
      String message;
      performCapture(options, metadata, message);
      if (message.isEmpty() && photo && photo->len <= 1500000 &&
          url == aqua_relay::origin(prefs)) {
        String header;
        serializeJson(metadata, header);
        uploaded = aqua_relay::post(endpoint + "/photo/" + id, keys.writer, "image/jpeg",
                                    photo->buf, photo->len, nullptr, header);
      }
    }
  }
  if (uploaded != 200 && url == aqua_relay::origin(prefs)) {
    aqua_relay::postJson(endpoint + "/error/" + id, keys.writer, "{}");
  }
  lastResult.store(uploaded);
}

void run(void *) {
  const aqua_relay::Keys keys(API_TOKEN);
  for (;;) {
    const String url = aqua_relay::origin(prefs);
    if (!url.isEmpty() && WiFi.status() == WL_CONNECTED && time(nullptr) >= 1735689600) {
      poll(url, keys);
    }
    vTaskDelay(pdMS_TO_TICKS(6000));
  }
}

void tick() {
  if (task || millis() - lastStartCheck < 2000) return;
  lastStartCheck = millis();
  if (aqua_relay::origin(prefs).isEmpty()) return;
  if (xTaskCreate(run, "aqua-camera", 12288, nullptr, 1, &task) != pdPASS) task = nullptr;
}
}
