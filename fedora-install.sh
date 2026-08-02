#!/bin/bash

set -euo pipefail

OMARCHY_PATH="$(dirname "$(realpath "$0")")"
OMARCHY_INSTALL="$OMARCHY_PATH/install"
BIN_DIR="$HOME/.local/bin"
SRC_DIR="$HOME/.local/src"

# Ensure omarchy commands are available
export PATH="$OMARCHY_PATH/bin:$PATH"

log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

log "Preflight"
# ---------------------------------------------------------------------------
sudo dnf install -y rpm-ostree rpm-build git curl wget jq fzf

mkdir -p "$SRC_DIR" "$BIN_DIR"

# ---------------------------------------------------------------------------
log "1/10  Enable repositories (RPM Fusion + solopasha/hyprland COPR for uwsm + satty)"
# ---------------------------------------------------------------------------
sudo dnf install -y 'dnf-plugins-core'
# RPM Fusion is installed via RPM packages, not repo files
sudo dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
sudo dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

sudo dnf copr enable -y solopasha/hyprland

# ---------------------------------------------------------------------------
log "2/10  Bootstrap tooling + build dependencies"
# ---------------------------------------------------------------------------
sudo dnf install -y \
  gcc gcc-c++ make cmake pkgconf-pkg-config \
  git curl wget jq fzf bat eza fd-find ripgrep \
  glibc-devel libxkbcommon-devel wayland-devel \
  cairo-devel pango-devel pixman-devel libinput-devel \
  libudev-devel libdrm-devel mesa-libGL-devel \
  hwdata-devel libepoxy-devel libxkbcommon-x11-devel \
  gobject-introspection-devel pipewire-devel \
  rustc cargo

# ---------------------------------------------------------------------------
log "3/10  Core desktop packages (dnf)"
# ---------------------------------------------------------------------------
sudo dnf install -y \
  hyprland hyprlock hypridle waybar swww \
  mako grim slurp wl-clipboard \
  mate-polkit \
  sddm \
  dnf-plugins-core rpm-build git \
  btop bat eza fd-find ripgrep \
  pipewire pipewire-pulse wireplumber \
  fcitx5 fcitx5-mozc \
  thunar thunar-volman tumbler \
  gvfs gvfs-mtp \
  firefox \
  libreoffice \
  vim nano \
  htop \
  neovim \
  git curl wget unzip zip tree jq \
  python3-pip npm nodejs \
  gcc gcc-c++ make cmake \
  lutris steam gamemode \
  mesa-vulkan-drivers vulkan-tools \
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  adwaita-icon-theme papirus-icon-theme \
  jetbrains-mono-fonts-all google-nerd-fonts \
  google-noto-sans-fonts google-noto-emoji-color-fonts \
  alacritty foot helix \
  satty uwsm power-profiles-daemon \
  acpi brightnessctl playerctl pamixer \
  wl-clipboard clipman wtype xdotool scrot flameshot \
  obsidian zathura zathura-pdf-mupdf zathura-djvu \
  zathura-cb zathura-ps \
  --skip-unavailable --allowerasing

# ---------------------------------------------------------------------------
log "4/10  Hyprland + desktop extras (installed via dnf from solopasha/hyprland COPR)"
# ---------------------------------------------------------------------------
# Hyprland, hyprlock, hypridle, waybar, swww, mako, grim, slurp, wl-clipboard,
# elephant, walker, satty, uwsm, powerprofilesctl, and other desktop packages
# are already installed in section 3 via dnf from the solopasha/hyprland COPR.
# No local build needed on Fedora.

# ---------------------------------------------------------------------------
log "5/10  Build starship from source (aarch64 - dnf version may be older)"
# ---------------------------------------------------------------------------
if [[ ! -x $BIN_DIR/starship ]]; then
  cargo install --locked starship 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
log "6/10  Deploy Omarchy configs (quattro Lua-based)"
# ---------------------------------------------------------------------------
mkdir -p ~/.config/hypr
cp "$OMARCHY_PATH"/config/hypr/hyprland.lua ~/.config/hypr/hyprland.lua
cp "$OMARCHY_PATH"/config/hypr/autostart.lua ~/.config/hypr/autostart.lua
cp "$OMARCHY_PATH"/config/hypr/bindings.lua ~/.config/hypr/bindings.lua
cp "$OMARCHY_PATH"/config/hypr/input.lua ~/.config/hypr/input.lua
cp "$OMARCHY_PATH"/config/hypr/looknfeel.lua ~/.config/hypr/looknfeel.lua
cp "$OMARCHY_PATH"/config/hypr/monitors.lua ~/.config/hypr/monitors.lua
cp "$OMARCHY_PATH"/config/hypr/hyprsunset.conf ~/.config/hypr/hyprsunset.conf
cp "$OMARCHY_PATH"/config/hypr/xdph.conf ~/.config/hypr/xdph.conf
cp "$OMARCHY_PATH"/default/bashrc ~/.bashrc

# Deploy fontconfig (quattro uses default/fontconfig/conf.avail/50-omarchy.conf)
mkdir -p ~/.config/fontconfig/conf.d
cp "$OMARCHY_PATH"/default/fontconfig/conf.avail/50-omarchy.conf ~/.config/fontconfig/conf.d/50-omarchy.conf
fc-cache -f ~/.config/fontconfig 2>/dev/null || true

gsettings set org.gnome.desktop.interface gtk-enable-primary-paste true || true
systemctl --user enable --now gnome-keyring-daemon 2>/dev/null || true

# ---------------------------------------------------------------------------
log "7/10  Theme + first-run guards"
# ---------------------------------------------------------------------------
mkdir -p ~/.config/omarchy/themes
mkdir -p ~/.config/btop/themes ~/.config/mako
ln -snf ~/.config/omarchy/current/theme/btop.theme ~/.config/btop/themes/current.theme
ln -snf ~/.config/omarchy/current/theme/mako.ini ~/.config/mako/config

# Mark all migrations done (fresh deploy) so nothing Arch-specific runs
mkdir -p ~/.local/state/omarchy/migrations
for f in "$OMARCHY_PATH"/migrations/*.sh; do
  touch ~/.local/state/omarchy/migrations/"$(basename "$f")"
done

# Create toggles directory (Lua-based toggles for quattro) - copy all toggle files
mkdir -p ~/.local/state/omarchy/toggles/hypr
for toggle in "$OMARCHY_PATH"/default/hypr/toggles/*.lua; do
  cp "$toggle" ~/.local/state/omarchy/toggles/hypr/
done

if omarchy-battery-present; then
  powerprofilesctl set balanced 2>/dev/null || true
else
  powerprofilesctl set performance 2>/dev/null || true
fi
systemctl --user enable --now omarchy-recover-internal-monitor.service 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-enable-primary-paste true 2>/dev/null || true

OMARCHY_THEME_HEADLESS=1 omarchy-theme-set "Tokyo Night"

# ---------------------------------------------------------------------------
log "8/10  SDDM + autologin + graphical target"
# ---------------------------------------------------------------------------
if ! grep -q polkit-mate-authentication-agent-1 "$HOME/.config/hypr/autostart.lua" 2>/dev/null; then
  # Patch the polkit agent path in the autostart (mate-polkit
  # is the Fedora package; the binary lives at /usr/libexec/polkit-mate-authentication-agent-1).
  if [[ -f "$HOME/.config/hypr/autostart.lua" ]]; then
    sed -i 's#/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1#/usr/libexec/polkit-mate-authentication-agent-1#' "$HOME/.config/hypr/autostart.lua" 2>/dev/null || true
  fi
fi

sudo bash "$OMARCHY_INSTALL/login/sddm.sh"

# ---------------------------------------------------------------------------
log "9/10  Services"
# ---------------------------------------------------------------------------
sudo systemctl enable --now sddm.service
systemctl --user enable omarchy-recover-internal-monitor.service 2>/dev/null || true
sudo systemctl set-default graphical.target

# ---------------------------------------------------------------------------
log "10/10  PATH + graphical session environment"
# ---------------------------------------------------------------------------
mkdir -p ~/.config/environment.d
cat > ~/.config/environment.d/10-omarchy.conf <<ENVEOF
export OMARCHY_PATH="$OMARCHY_PATH"
export PATH="\$HOME/.local/bin:\$PATH"
ENVEOF

# Run user finalization (sets up skill symlinks, xdg dirs, runs install/user/all.sh)
# Use --first-install to mark migrations complete for fresh deploy
OMARCHY_INSTALL="$OMARCHY_INSTALL" OMARCHY_PATH="$OMARCHY_PATH" omarchy-finalize-user --first-install

log "Done. Reboot into the desktop:  sudo systemctl reboot"
log "If the desktop doesn't come up, check:  journalctl -u sddm -b"
