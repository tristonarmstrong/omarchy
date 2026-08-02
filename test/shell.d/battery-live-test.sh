#!/bin/bash

# Live test for omarchy-battery-status. Runs the actual binary on the host
# and asserts that the fields reported to the power panel are present and
# well-formed. The original bug had size / time / cycles all come back
# empty when a HID++ peripheral was selected as the battery — this catches
# that class of regression even when the test stubs don't reproduce it.
#
# Skips cleanly on hosts without a real laptop battery (desktops, CI VMs).

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Detect a real laptop battery supply. HID++ peripherals report
# type=Battery but don't expose energy/charge capacity files.
has_battery=false
for supply in /sys/class/power_supply/*; do
  [[ -r $supply/type ]] || continue
  [[ $(<"$supply/type") == "Battery" ]] || continue
  [[ -r $supply/energy_full || -r $supply/charge_full ]] || continue
  has_battery=true
  break
done

if [[ $has_battery != "true" ]]; then
  pass "battery live status skipped (no real battery detected)"
  exit 0
fi

shell_output=$("$ROOT/bin/omarchy-battery-status" --shell)

get_field() {
  awk -F'\t' -v key="$1" '$1 == key { sub(/^[^ \t]+[ \t]+/, ""); print; exit }' <<<"$shell_output"
}

percentage=$(get_field percentage)
state=$(get_field state)
rate=$(get_field rate)
size=$(get_field size)
time=$(get_field time)
cycles=$(get_field cycles)

# Required whenever a battery is present.
[[ $percentage =~ ^[0-9]+%$ ]] || fail "battery live status: percentage" "got=$percentage"
[[ -n $state ]] || fail "battery live status: state is empty"
[[ $state =~ ^(discharging|charging|fully-charged|pending-charge|pending-discharge|unknown)$ ]] \
  || fail "battery live status: state has unexpected value" "got=$state"
[[ $rate =~ ^[0-9.]+W$ ]] || fail "battery live status: rate" "got=$rate"
[[ $size =~ ^[0-9]+Wh$ ]] || fail "battery live status: size is empty or malformed" "got=$size"

# Time is only meaningful when current is flowing. If it's there, it must
# have a recognizable format. If the battery is in an idle state
# (fully-charged, charge-threshold active), the panel shows "-" and we
# don't see this field at all.
if [[ $state == "discharging" || $state == "charging" ]]; then
  [[ -n $time ]] || fail "battery live status: time is empty while $state"
  [[ $time =~ ^[0-9]+(h( [0-9]+m)?|m)$ ]] \
    || fail "battery live status: time has unexpected format" "got=$time"
fi

# Cycles is optional — only emitted when the sysfs supply exposes
# cycle_count. If present, it must be a non-negative integer.
if [[ -n $cycles ]]; then
  [[ $cycles =~ ^[0-9]+$ ]] || fail "battery live status: cycles" "got=$cycles"
fi

pass "battery live status has all required fields"
