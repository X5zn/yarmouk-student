#!/bin/bash
# Renders every screen of the app in the simulator with sample data (-demo) and saves PNGs.
set -u
APP="$1"
BID=com.baihas.yarmoukstudent
UDID="$2"
mkdir -p screens
xcrun simctl install "$UDID" "$APP"
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true

shot() {
  local name=$1; shift
  xcrun simctl terminate "$UDID" "$BID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BID" -demo "$@" -AppleLanguages "(ar)" -AppleLocale ar_JO >/dev/null
  sleep 6
  xcrun simctl io "$UDID" screenshot "screens/$name.png" >/dev/null 2>&1 && echo "shot $name"
}

xcrun simctl ui "$UDID" appearance light
for s in home schedule summary account course course_teams forum discussion assignment folder records info marks registered notes assignments exams plan settings poetry search onboarding grades_calc export; do
  shot "$s" -screen "$s"
done
shot schedule_week -screen schedule -week
shot schedule_freeday -screen schedule -day 7
shot home_empty -screen home -empty
shot summary_empty -screen summary -empty
shot course_empty -screen course -empty
shot course_loading -screen course -empty -loading
shot records_empty -screen records -empty
shot marks_empty -screen marks -empty
shot account_empty -screen account -empty

xcrun simctl ui "$UDID" appearance dark
for s in home schedule summary account course forum records marks registered settings notes info; do
  shot "dark_$s" -screen "$s"
done
shot dark_schedule_week -screen schedule -week
shot dark_course_empty -screen course -empty
ls -la screens | head -80
