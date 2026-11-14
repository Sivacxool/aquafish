#pragma once

#include <Arduino.h>
#include <SD_MMC.h>
#include <esp_random.h>
#include <stdio.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

namespace capture_archive {
constexpr char mountPath[] = "/sdcard";
constexpr char directory[] = "/sdcard/AQUAHATCH";

bool mount() {
  // SD_MMC's 1-bit bus leaves GPIO4 available for the camera's flash LED.
  if (!SD_MMC.begin(mountPath, true, false, SDMMC_FREQ_DEFAULT, 2)) {
    Serial.println("SD_UNAVAILABLE: check the FAT32 card");
    return false;
  }
  struct stat entry {};
  if (mkdir(directory, 0777) != 0 &&
      (stat(directory, &entry) != 0 || !S_ISDIR(entry.st_mode))) {
    Serial.println("SD_UNAVAILABLE: could not create AQUAHATCH directory");
    SD_MMC.end();
    return false;
  }
  return true;
}

bool writeJpeg(const uint8_t *jpeg, size_t length, time_t captured) {
  struct tm utc {};
  char stamp[20];
  if (!gmtime_r(&captured, &utc) ||
      !strftime(stamp, sizeof(stamp), "%Y%m%d_%H%M%S", &utc)) {
    Serial.println("SD_SAVE_FAILED: invalid capture timestamp");
    return false;
  }
  char path[72], temporary[72];
  const auto suffix = static_cast<unsigned long>(esp_random());
  snprintf(path, sizeof(path), "%s/%s_%08lX.jpg", directory, stamp, suffix);
  snprintf(temporary, sizeof(temporary), "%s/%s_%08lX.tmp", directory, stamp, suffix);

  // Publish a .jpg only after the complete JPEG has been written and flushed.
  struct stat entry {};
  if (stat(path, &entry) == 0 || stat(temporary, &entry) == 0) {
    Serial.println("SD_SAVE_FAILED: filename already exists");
    return false;
  }
  FILE *file = fopen(temporary, "wb");
  if (!file) {
    Serial.println("SD_SAVE_FAILED: could not open file");
    return false;
  }
  const bool written = fwrite(jpeg, 1, length, file) == length &&
                       fflush(file) == 0 && fsync(fileno(file)) == 0;
  const bool closed = fclose(file) == 0;
  if (!written || !closed || rename(temporary, path) != 0) {
    remove(temporary);
    Serial.println("SD_SAVE_FAILED: could not finish writing JPG");
    return false;
  }
  Serial.printf("SD_SAVED %s (%u bytes)\n", path + sizeof(mountPath) - 1,
                static_cast<unsigned>(length));
  return true;
}

bool save(const uint8_t *jpeg, size_t length, time_t captured) {
  // Keep SDMMC and FAT buffers out of Wi-Fi setup and idle HTTPS handshakes.
  // The camera mutex serializes local and remote captures.
  if (!mount()) return false;
  const bool saved = writeJpeg(jpeg, length, captured);
  SD_MMC.end();
  return saved;
}
}
