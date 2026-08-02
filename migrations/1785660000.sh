echo "Re-apply keyboard backlight slider to omarchy.monitor panel"

# Adds a keyboard backlight slider between the screen brightness and text
# size sections in the omarchy.monitor popup. Upstream omarchy.monitor only
# covers display brightness, so on machines with a controllable keyboard
# backlight (like the J314) the slider is missing without this patch.
#
# The Panel.qml file lives inside the omarchy package, so `omarchy update`
# overwrites it with the upstream version and removes our local addition.
# This migration re-applies the patch after every update.
#
# Idempotent: if the patch has already been applied (detected by the
# `kbdBrightnessAvailable` property existing in the file), the migration
# is a no-op.

config_file="$OMARCHY_PATH/shell/plugins/panels/monitor/Panel.qml"
patch_file="$OMARCHY_PATH/migrations/keyboard-backlight-monitor.patch"

# Already applied: no work to do.
if grep -q 'property bool kbdBrightnessAvailable' "$config_file" 2>/dev/null; then
  echo "Keyboard backlight slider already present in omarchy.monitor panel."
  exit 0
fi

# patch(1) must be available.
if ! command -v patch >/dev/null 2>&1; then
  echo "Warning: 'patch' command not found; skipping keyboard backlight migration."
  exit 0
fi

# Try a dry-run first so we never leave the file in a half-applied state
# if upstream has diverged enough to break the patch.
if ! patch --dry-run -p1 -d "$OMARCHY_PATH" <"$patch_file" >/dev/null 2>&1; then
  echo "Warning: keyboard backlight patch does not apply cleanly to current omarchy.monitor panel."
  echo "The keyboard backlight slider will be missing until this migration is updated."
  exit 0
fi

if patch -p1 -d "$OMARCHY_PATH" <"$patch_file" >/dev/null; then
  echo "Re-applied keyboard backlight slider to omarchy.monitor panel."
  omarchy-restart-shell >/dev/null 2>&1 || true
else
  echo "Failed to apply keyboard backlight patch."
  exit 1
fi
