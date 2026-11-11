#pragma once
#include "ph_calibration.h"
#include <algorithm>
#include <cstddef>

namespace ph_filter {
class Window {
 public:
  static constexpr std::size_t Size = 20;

  void reset() { next_ = count_ = 0; }

  void add(float voltage) {
    samples_[next_] = voltage;
    next_ = (next_ + 1) % Size;
    if (count_ < Size) ++count_;
  }

  float voltage() const {
    if (count_ < Size) return NAN;

    float ordered[Size];
    std::size_t valid = 0;
    for (float sample : samples_) {
      if (ph_math::inputValid(sample)) ordered[valid++] = sample;
    }
    if (valid < MinInliers) return NAN;
    std::sort(ordered, ordered + valid);

    // Choose the tightest group of at least 15 of the last 20 attempts.
    std::size_t first = 0;
    float span = ordered[MinInliers - 1] - ordered[0];
    for (std::size_t i = 1; i + MinInliers <= valid; ++i) {
      const float candidate = ordered[i + MinInliers - 1] - ordered[i];
      if (candidate < span) {
        first = i;
        span = candidate;
      }
    }
    if (span > MaxSpan) return NAN;
    const float median = ordered[first + MinInliers / 2];

    // Stop publishing the old group quickly when the probe is moved or lost.
    std::size_t recent = 0;
    for (std::size_t i = 1; i <= 5; ++i) {
      const float sample = samples_[(next_ + Size - i) % Size];
      if (ph_math::inputValid(sample) && std::fabs(sample - median) <= MaxSpan) ++recent;
    }
    return recent >= 3 ? median : NAN;
  }

 private:
  static constexpr std::size_t MinInliers = 15;
  static constexpr float MaxSpan = 0.010f;
  float samples_[Size] = {};
  std::size_t next_ = 0;
  std::size_t count_ = 0;
};
}
