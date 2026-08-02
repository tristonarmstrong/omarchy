#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# ---------------------------------------------------------------------------
# Scenario 1: single battery, sysfs rate is used (live power draw).
# ---------------------------------------------------------------------------
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
mkdir -p "$tmp_dir/power/BAT0"
printf 'Battery\n' >"$tmp_dir/power/BAT0/type"
printf '56870000\n' >"$tmp_dir/power/BAT0/energy_full"
printf '900000\n' >"$tmp_dir/power/BAT0/current_now"
printf '12000000\n' >"$tmp_dir/power/BAT0/voltage_now"
cat >"$tmp_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  exit 0
fi

if [[ $1 == "-i" ]]; then
  cat <<'INFO'
  native-path:          BAT0
  state:                discharging
  energy:               28.3 Wh
  energy-full:          56.7 Wh
  energy-rate:          7.3 W
  time to empty:        2.5 hours
  percentage:           51%
INFO
  exit 0
fi

exit 1
STUB
chmod +x "$tmp_dir/bin/upower"

shell_output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'percentage\t51%' <<<"$shell_output" >/dev/null || fail "battery status reports percentage"
grep -Fx $'state\tdischarging' <<<"$shell_output" >/dev/null || fail "battery status reports state"
grep -Fx $'rate\t10.8W' <<<"$shell_output" >/dev/null || fail "battery status reports live sysfs power rate"
grep -Fx $'size\t56Wh' <<<"$shell_output" >/dev/null || fail "battery status reports full capacity"
grep -Fx $'time\t2h 30m' <<<"$shell_output" >/dev/null || fail "battery status reports remaining time"

# ---------------------------------------------------------------------------
# Scenario 2: HID++ peripheral + real laptop battery, peripheral first
# alphabetically. Script must skip the peripheral and report the real one.
# Reproduces the bug on machines where wireless mice expose type=Battery
# supplies without energy/charge capacity files.
# ---------------------------------------------------------------------------
multi_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir" "$multi_dir"' EXIT

mkdir -p "$multi_dir/bin"
mkdir -p "$multi_dir/power/hidpp_battery_0"
mkdir -p "$multi_dir/power/macsmc-battery"
printf 'Battery\n' >"$multi_dir/power/hidpp_battery_0/type"
printf 'Battery\n' >"$multi_dir/power/macsmc-battery/type"
# Peripheral only exposes a capacity percentage; no energy/charge capacity files.
printf '60\n' >"$multi_dir/power/hidpp_battery_0/capacity"
# Real battery has the full set of sysfs telemetry.
printf '51870000\n' >"$multi_dir/power/macsmc-battery/energy_full"
printf '9500000\n' >"$multi_dir/power/macsmc-battery/power_now"
printf '10500000\n' >"$multi_dir/power/macsmc-battery/current_now"
printf '11800000\n' >"$multi_dir/power/macsmc-battery/voltage_now"
printf '514\n' >"$multi_dir/power/macsmc-battery/cycle_count"

cat >"$multi_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  cat <<'DEVICES'
/org/freedesktop/UPower/devices/battery_hidpp_battery_0
/org/freedesktop/UPower/devices/battery_macsmc_battery
DEVICES
  exit 0
fi

case $2 in
  *hidpp_battery_0)
    cat <<'INFO'
  native-path:          hidpp_battery_0
  state:                discharging
  percentage:           60%
INFO
    exit 0
    ;;
  *macsmc_battery)
    cat <<'INFO'
  native-path:          macsmc-battery
  state:                discharging
  energy:               43.8 Wh
  energy-full:          51.87 Wh
  energy-rate:          9.5 W
  time to empty:        4.6 hours
  percentage:           84%
INFO
    exit 0
    ;;
esac

exit 1
STUB
chmod +x "$multi_dir/bin/upower"

multi_output=$(OMARCHY_POWER_SUPPLY_PATH="$multi_dir/power" PATH="$multi_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'percentage\t84%' <<<"$multi_output" >/dev/null || fail "multi-battery picks real battery percentage (got: $multi_output)"
grep -Fx $'state\tdischarging' <<<"$multi_output" >/dev/null || fail "multi-battery picks real battery state"
grep -Fx $'size\t51Wh' <<<"$multi_output" >/dev/null || fail "multi-battery picks real battery size"
grep -Fx $'rate\t9.5W' <<<"$multi_output" >/dev/null || fail "multi-battery picks real battery rate"
grep -Fx $'time\t4h 35m' <<<"$multi_output" >/dev/null || fail "multi-battery picks real battery time"
grep -Fx $'cycles\t514' <<<"$multi_output" >/dev/null || fail "multi-battery picks real battery cycles"

if matches=$(rg -n 'omarchy-battery-(capacity|remaining|remaining-time)' "$ROOT/bin" "$ROOT/test" "$ROOT/shell" "$ROOT/docs"); then
  fail "battery status owns capacity and remaining calculations" "$matches"
fi

pass "battery status owns capacity and remaining calculations"
