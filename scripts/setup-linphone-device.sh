#!/usr/bin/env bash
set -u

PACKAGE="${PACKAGE:-org.linphone}"
ADB="${ADB:-adb}"

log() {
  printf '%s\n' "$*"
}

run() {
  log "+ $*"
  "$@" 2>&1 || true
}

run_quiet_failure() {
  local output
  log "+ $*"
  if output="$("$@" 2>&1)"; then
    [ -n "$output" ] && printf '%s\n' "$output"
    return 0
  fi

  if printf '%s' "$output" | grep -qi 'Security exception'; then
    log "  skipped: this device/ROM does not allow this command over adb shell."
  elif printf '%s' "$output" | grep -qi 'Unknown operation string'; then
    log "  skipped: appop is not supported on this Android/ROM."
  else
    [ -n "$output" ] && printf '%s\n' "$output"
  fi
  return 0
}

shell() {
  "$ADB" shell "$@" 2>/dev/null | tr -d '\r'
}

appops_set() {
  local op="$1"
  local mode="$2"
  run_quiet_failure "$ADB" shell cmd appops set "$PACKAGE" "$op" "$mode"
}

grant_runtime_permission() {
  local permission="$1"
  run_quiet_failure "$ADB" shell pm grant "$PACKAGE" "$permission"
}

start_settings_activity() {
  local component="$1"
  shift
  run "$ADB" shell am start -a android.intent.action.MAIN -n "$component" "$@"
}

if ! command -v "$ADB" >/dev/null 2>&1; then
  log "adb not found. Set ADB=/path/to/adb or add adb to PATH."
  exit 1
fi

devices="$("$ADB" devices | awk 'NR > 1 && $2 == "device" { print $1 }')"
device_count="$(printf '%s\n' "$devices" | sed '/^$/d' | wc -l | tr -d ' ')"
if [ "$device_count" = "0" ]; then
  log "No authorized Android device found. Connect a device and enable USB debugging."
  exit 1
fi
if [ "$device_count" != "1" ]; then
  log "Multiple devices found. Run with ADB='adb -s <serial>' or disconnect extras."
  printf '%s\n' "$devices"
  exit 1
fi

if ! shell pm path "$PACKAGE" | grep -q '^package:'; then
  log "Package [$PACKAGE] is not installed on the connected device."
  exit 1
fi

manufacturer="$(shell getprop ro.product.manufacturer)"
brand="$(shell getprop ro.product.brand)"
model="$(shell getprop ro.product.model)"
sdk="$(shell getprop ro.build.version.sdk)"
miui="$(shell getprop ro.miui.ui.version.name)"

log "Device: ${manufacturer:-unknown} ${model:-unknown}, Android SDK ${sdk:-unknown}, MIUI ${miui:-none}"
log "Package: $PACKAGE"
log ""

log "Granting standard runtime permissions where supported..."
grant_runtime_permission android.permission.RECORD_AUDIO
grant_runtime_permission android.permission.CAMERA
grant_runtime_permission android.permission.READ_CONTACTS
grant_runtime_permission android.permission.READ_PHONE_STATE
grant_runtime_permission android.permission.READ_PHONE_NUMBERS
grant_runtime_permission android.permission.POST_NOTIFICATIONS

log ""
log "Setting standard appops best-effort..."
appops_set POST_NOTIFICATION allow
appops_set START_FOREGROUND allow
appops_set OP_READ_PHONE_STATE allow
appops_set READ_PHONE_NUMBERS allow
appops_set RECORD_AUDIO allow
appops_set CAMERA allow

log ""
log "Requesting battery-optimization exemption screen..."
run "$ADB" shell am start \
  -a android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS \
  -d "package:$PACKAGE"

log ""
case "$(printf '%s %s' "$manufacturer" "$brand" | tr '[:upper:]' '[:lower:]')" in
  *xiaomi*|*redmi*|*poco*)
    log "Xiaomi/MIUI detected. Applying tested MIUI appops for background call UI..."
    # These op numbers are MIUI private appops. They are not portable Android APIs.
    # On the tested Xiaomi MIX 2 / MIUI 12 / Android 9 they controlled the call UI
    # being allowed to start from the background.
    appops_set 10008 allow
    appops_set 10021 allow
    log ""
    log "Opening MIUI app permission editor. Please also verify:"
    log "- Autostart: allowed"
    log "- Battery saver: no restrictions"
    log "- Display pop-up windows while running in the background: allowed"
    start_settings_activity "com.miui.securitycenter/com.miui.permcenter.permissions.PermissionsEditorActivity" \
      "--es" "extra_pkgname" "$PACKAGE"
    ;;
  *huawei*|*honor*)
    log "Huawei/Honor detected. Vendor background launch/autostart settings are not stable via adb."
    log "Please manually allow autostart, background activity, notifications, and ignore battery optimization."
    ;;
  *oppo*|*realme*|*oneplus*)
    log "OPPO/Realme/OnePlus detected. Vendor background launch/autostart settings are not stable via adb."
    log "Please manually allow autostart, background activity, notifications, and ignore battery optimization."
    ;;
  *vivo*|*iqoo*)
    log "vivo/iQOO detected. Vendor background launch/autostart settings are not stable via adb."
    log "Please manually allow autostart, background activity, notifications, and ignore battery optimization."
    ;;
  *)
    log "No known vendor-specific automation for this device."
    log "Please manually verify notifications, autostart/background run, and battery optimization."
    ;;
esac

log ""
log "Current appops snapshot:"
shell appops get "$PACKAGE" | sed -n '1,120p'

log ""
log "Done. Best-effort adb setup is complete."
