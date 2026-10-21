# Direct mobile Wi-Fi provisioning, firmware 0.6.0-local

The ESP32 serves its existing HTTPS identity on STA and SoftAP interfaces. No PC provisioning service or cloud account is required after firmware installation. All provisioning endpoints require the existing Bearer token and are under `/api/v1/devices/incubator-01`.

- `GET /wifi`: board identity, connected/saved SSID, LAN IP, setup AP status, last request ID/phase, and cached scan. Never returns passwords or API tokens.
- `POST /wifi/start`: opens or renews the setup AP window. Returns 202 before changing radio state.
- `POST /wifi/scan`: schedules an asynchronous 2.4 GHz scan. Poll `/wifi` until `scan_state=ready` or `failed`. Enterprise/WEP networks are excluded from the app picker.
- `POST /wifi`: JSON `request_id`, `ssid`, `password`, `reuse_password`, `allow_open`. Returns 202. The same ID/body is idempotent; an active competing operation or a conflicting body returns 409.

The loop changes Wi-Fi after the HTTP response. Candidates stay in RAM until the requested SSID connects and receives an IP. Then SSID/password are committed together as the NVS `network_v2` JSON value. A 30-second failure or NVS write error restores the previous saved network. Legacy `ssid`/`wifi_pass` values remain readable for upgrades.

Success requires the matching request ID, `phase=connected`, `connected=true`, and the requested SSID. A restored old network with `phase=failed` is not success. A request timeout is ambiguous; query its ID instead of issuing a duplicate change.

SoftAP: `AquaHatch-117C`, IP `192.168.4.1`, password is the first 16 lowercase hex characters of SHA-256 over UTF-8 `AquaHatch setup v1:` plus the pairing token. The app derives this password locally from the saved/entered pairing token. The token is not embedded in the APK. Use `tools/print_pairing_card.py` to create a private printable card.

AP opens at boot and after prolonged loss of STA connection. After ten minutes on a working home network, it closes when no setup client or operation is active. Power-cycle to reopen, or call authenticated `/wifi/start` from the existing LAN connection. The AP is protected by its generated WPA password, and application traffic uses the private CA and verified DNS identity. No HTTP, open AP, or certificate bypass is added.

Android uses the system Wi-Fi settings screen for association. While the wizard is open it can bind the app process to an available Wi-Fi network so mobile data does not steal setup traffic. It releases the binding on completion/exit. Only the normal ACCESS_NETWORK_STATE permission is added; scan results come from the ESP32 rather than phone location APIs.
