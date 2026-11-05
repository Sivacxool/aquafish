#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/ios-delivery
flutter build ios --simulator --debug --no-codesign 2>&1 | tee build/ios-delivery/simulator-build.log
sim_id="$(xcrun simctl list devices available --json | python3 -c 'import json,sys;d=json.load(sys.stdin);print(next(v["udid"] for group in d["devices"].values() for v in group if v.get("isAvailable") and "iPhone" in v["name"]))')"
xcrun simctl boot "$sim_id" || true
xcrun simctl bootstatus "$sim_id" -b
xcrun simctl install "$sim_id" build/ios/iphonesimulator/Runner.app
xcrun simctl launch --terminate-running-process "$sim_id" th.ac.aquahatch.aquaHatch | tee build/ios-delivery/simulator-launch.log
sleep 12
xcrun simctl spawn "$sim_id" launchctl list > build/ios-delivery/simulator-processes.log
grep -q 'UIKitApplication:th.ac.aquahatch.aquaHatch' build/ios-delivery/simulator-processes.log
xcrun simctl io "$sim_id" screenshot build/ios-delivery/ios-simulator.png
python3 - "$sim_id" <<'PY'
from pathlib import Path
import json,sys
p=Path('build/ios-delivery/simulator-verification.json')
p.write_text(json.dumps({'simulator_udid':sys.argv[1],'app_launched':True,'process_still_running_after_seconds':12,'physical_iphone_tested':False},indent=2)+'\n')
PY
