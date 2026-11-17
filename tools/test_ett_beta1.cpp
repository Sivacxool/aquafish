#include <assert.h>
#include <stdint.h>
#include "../aqua_hatch/firmware/local_server/ett_boot_sound.h"
#include "../aqua_hatch/firmware/local_server/renke_do_protocol.h"

int main() {
  using namespace ett_relays;
  constexpr uint8_t pump = AllOff & ~(1u << PumpBit);
  constexpr uint8_t pumpAndFan = pump & ~(1u << FanBit);
  constexpr uint8_t fan = AllOff & ~(1u << FanBit);

  BootSound dry;
  assert(dry.portValue(AllOff, true, 0) == AllOff);
  assert(!dry.buzzerOn(0));
  assert(dry.portValue(pumpAndFan, true, 500) == fan);
  assert(dry.buzzerOn(500));
  assert(!dry.buzzerOn(540));
  dry.wifiConnected();
  assert(dry.buzzerOn(1500));
  assert(!dry.buzzerOn(1540));
  assert(dry.buzzerOn(2500));
  assert(dry.portValue(pumpAndFan, true, 3499) == fan);
  assert(dry.portValue(pumpAndFan, true, 3500) == pumpAndFan);
  assert(dry.buzzerOn(3500));  // Wi-Fi confirmation resumes after countdown.
  assert(!dry.buzzerOn(3535));
  assert(dry.buzzerOn(3600));
  assert(!dry.buzzerOn(3635));
  assert(dry.portValue(AllOff, false, 4000) == AllOff);
  assert(dry.portValue(pump, true, 5000) == pump);
  assert(!dry.buzzerOn(5000));

  BootSound fullAtBoot;
  assert(fullAtBoot.portValue(AllOff, false, 0) == AllOff);
  assert(fullAtBoot.portValue(pump, true, 5000) == pump);
  assert(!fullAtBoot.buzzerOn(5000));
  fullAtBoot.wifiConnected();
  assert(fullAtBoot.buzzerOn(5100));
  assert(!fullAtBoot.buzzerOn(5175));

  BootSound interrupted;
  assert(interrupted.portValue(pump, true, UINT32_MAX - 800) == AllOff);
  assert(interrupted.buzzerOn(UINT32_MAX - 800));
  assert(interrupted.buzzerOn(199));  // Second beep after millis() rolls over.
  assert(interrupted.portValue(AllOff, false, 200) == AllOff);
  assert(!interrupted.buzzerOn(200));
  assert(interrupted.portValue(pump, true, 1000) == pump);

  BootSound ioFault;
  assert(ioFault.portValue(pump, true, 500) == AllOff);
  ioFault.cancelPump();
  assert(!ioFault.buzzerOn(515));

  uint8_t response[20] = {
    1, 3, 12, 0x3f, 0x80, 0, 0, 0x40, 0xa0, 0, 0, 0x41, 0xe0, 0, 0,
  };
  const uint16_t crc = renke_do::crc16(response, 15);
  response[15] = crc & 0xff;
  response[16] = crc >> 8;
  response[17] = 0xff;
  assert(renke_do::replySize(response, 1, 6) == 0);
  assert(renke_do::replySize(response, 16, 6) == 0);
  const size_t size = renke_do::replySize(response, sizeof(response), 6);
  assert(size == 17);
  renke_do::Reading reading{};
  assert(renke_do::decode(response, size, 1, reading) == renke_do::Result::ok);
  assert(reading.mgL == 5.0f && reading.temperatureC == 28.0f);
  assert(renke_do::decode(response, size, 2, reading) == renke_do::Result::wrong_device);
  response[15] ^= 1;
  assert(renke_do::decode(response, size, 1, reading) == renke_do::Result::crc_error);
  uint8_t exception[] = {1, 0x83, 2, 0, 0, 255};
  const uint16_t exceptionCrc = renke_do::crc16(exception, 3);
  exception[3] = exceptionCrc & 0xff;
  exception[4] = exceptionCrc >> 8;
  const size_t exceptionSize = renke_do::replySize(exception, sizeof(exception), 6);
  assert(exceptionSize == 5);
  assert(renke_do::decode(exception, exceptionSize, 1, reading) == renke_do::Result::exception);
}
