#pragma once

namespace ett_camera {
void relayCapture(const String &url, const aqua_relay::Keys &keys) {
  if (!configured) return;
  const String endpoint = url + "/v1/cameras/" + keys.room + "/agent";
  JsonDocument snapshot;
  status(snapshot);
  String state, response;
  serializeJson(snapshot, state);
  if (aqua_relay::postJson(endpoint, keys.writer, state, &response) != 200 ||
      url != aqua_relay::origin(prefs)) return;

  JsonDocument incoming, options, metadata;
  if (deserializeJson(incoming, response) || !incoming["job"].is<JsonObject>()) return;
  options.set(incoming["job"]);
  const String id = options["capture_id"] | "";
  if (!validId(id)) return;

  int uploaded = 0;
  if (submit(options, metadata) == Submit::accepted) {
    const uint32_t started = millis();
    while (millis() - started < 32000 && url == aqua_relay::origin(prefs) &&
           time(nullptr) < (options["expires_at_unix"] | int64_t(0))) {
      {
        Lock lock;
        if (lock) {
          if (job.id != id || job.stage == Stage::failed || job.stage == Stage::expired) break;
          if (job.stage == Stage::captured) {
            describe(metadata);
            if (job.stage != Stage::captured) break;
            File file = LittleFS.open(PhotoPath, FILE_READ);
            if (file && file.seek(job.photo.start)) {
              String header;
              serializeJson(metadata, header);
              uploaded = aqua_relay::postStream(endpoint + "/photo/" + id, keys.writer,
                                                file, job.photo.length, header);
            }
            break;
          }
        }
      }
      vTaskDelay(pdMS_TO_TICKS(200));
    }
  }
  if (uploaded != 200 && url == aqua_relay::origin(prefs)) {
    aqua_relay::postJson(endpoint + "/error/" + id, keys.writer, "{}");
  }
}
}
