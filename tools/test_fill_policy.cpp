#include <cassert>
#include <cstdint>
#include "../aqua_hatch/firmware/local_server/fill_policy.h"

int main() {
  FillPolicy fill;
  fill.sample(true, 0);
  fill.sample(true, 500);
  assert(!fill.armed && !fill.running);

  fill.arm(true);
  fill.sample(true, 501);
  assert(fill.armed && fill.running);
  fill.sample(false, 550);
  assert(fill.armed && !fill.running);

  // A brief open contact stops the pump without resetting the fill deadline.
  fill.sample(true, 600);
  fill.sample(true, 1099);
  assert(!fill.running);
  fill.sample(true, 1100);
  assert(fill.running);
  fill.arm(true);
  fill.sample(true, 60501);
  assert(!fill.running && !fill.armed && fill.timedOut);
  fill.sample(true, 60502);
  assert(!fill.running);

  fill.arm(true);
  fill.sample(true, 60503);
  assert(fill.running && !fill.timedOut);
  fill.arm(false);
  assert(!fill.running && !fill.armed);

  // A stable open contact ends the cycle and a later refill gets a new timer.
  fill.arm(true);
  fill.sample(true, 60504);
  fill.sample(false, 60600);
  fill.sample(false, 62600);
  fill.sample(true, 130000);
  fill.sample(true, 130500);
  assert(fill.armed && fill.running);

  FillPolicy rollover;
  rollover.arm(true);
  rollover.sample(true, UINT32_MAX - 400);
  rollover.sample(true, 99);
  assert(rollover.running);
  rollover.sample(true, 60099);
  assert(rollover.timedOut && !rollover.running);
}
