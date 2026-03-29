#!/usr/bin/env bash
###############################################################################
# Sway Dotfiles Installer for Raspberry Pi OS Lite (Bookworm)
# Optimized for Raspberry Pi 5 (8GB) — Pure Productivity Edition
# (No gaps, no transparency, Wayland-native, PipeWire audio)
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_URL="https://github.com/Ruixi-rebirth/sway-dotfiles.git"
INSTALL_DIR="${HOME}/sway-dotfiles"
LOG_FILE="${HOME}/.sway-install.log"

log()     { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; }
warning() { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"; }

confirm() {
    local response
    read -rp "$(echo -e "${YELLOW}$1${NC}") (y/n) " response
    [[ "$response" =~ ^[Yy]$ ]]
}

###############################################################################
# System Setup & Hardware
###############################################################################

check_system() {
    log "Checking system compatibility..."

    # FIX: Prevent running as root — user services (PipeWire, MPD) break under root
    if [ "$(id -u)" = "0" ]; then
        error "Do not run this script as root. Run as your normal user with sudo access."
        exit 1
    fi

    if ! command -v sudo &>/dev/null; then
        error "sudo is required but not installed."
        exit 1
    fi

    if grep -q "Raspberry Pi" /sys/firmware/devicetree/base/model 2>/dev/null; then
        log "Raspberry Pi detected. Verifying DRM graphics drivers..."
        local cfg="/boot/firmware/config.txt"
        [ -f "$cfg" ] || cfg="/boot/config.txt"

        if [ -f "$cfg" ]; then
            if grep -q "dtoverlay=vc4-fkms-v3d" "$cfg"; then
                sudo sed -i 's/dtoverlay=vc4-fkms-v3d/dtoverlay=vc4-kms-v3d/' "$cfg"
                success "Replaced legacy fkms with kms overlay"
            elif ! grep -q "dtoverlay=vc4-kms-v3d" "$cfg"; then
                echo "dtoverlay=vc4-kms-v3d" | sudo tee -a "$cfg" > /dev/null
                success "KMS/DRM overlay added to config.txt"
            else
                success "KMS/DRM overlay already configured"
            fi
            # FIX: Set explicit GPU memory — default can be too low for a Wayland session
            if ! grep -q "^gpu_mem=" "$cfg"; then
                echo "gpu_mem=128" | sudo tee -a "$cfg" > /dev/null
                success "GPU memory set to 128 MB"
            fi
        else
            warning "Could not locate config.txt — ensure dtoverlay=vc4-kms-v3d is set before booting."
        fi
    fi

    success "System check passed (user: $USER)"
}

update_system() {
    log "Updating system packages..."
    sudo apt-get update
    sudo apt-get upgrade -y
    success "System updated"
}

install_build_tools() {
    log "Installing build tools and dependencies..."
    sudo apt-get install -y build-essential git curl wget pkg-config cmake unzip
    success "Build tools installed"
}

###############################################################################
# Core Wayland, Sway & Login Manager
###############################################################################

install_wayland_base() {
    log "Installing Wayland base..."
    sudo apt-get install -y wl-clipboard xwayland libwayland-dev
    success "Wayland base installed"
}

install_greeter() {
    log "Installing greetd login manager..."
    # greetd + agreety are in Debian Bookworm repos.
    # FIX: tuigreet is NOT in any Debian apt repo — it is a Rust binary distributed
    # only via its GitHub releases page. We download it directly.
    sudo apt-get install -y greetd

    local TUIGREET_VER="0.9.1"
    local TUIGREET_URL="https://github.com/apognu/tuigreet/releases/download/${TUIGREET_VER}/tuigreet-${TUIGREET_VER}-aarch64"

    log "Downloading tuigreet ${TUIGREET_VER} binary..."
    sudo wget -qO /usr/local/bin/tuigreet "$TUIGREET_URL" || {
        warning "tuigreet download failed. Falling back to agreety (text-mode greeter)."
        sudo bash -c 'cat > /etc/greetd/config.toml << GREETD
[terminal]
vt = 1

[default_session]
command = "agreety --cmd sway"
user = "greeter"
GREETD'
        sudo systemctl enable greetd
        success "greetd configured with agreety fallback"
        return
    }
    sudo chmod +x /usr/local/bin/tuigreet

    # FIX: Write the entire [default_session] block explicitly instead of using
    # a fragile sed that targets the first matching "command = .*" line.
    sudo bash -c "cat > /etc/greetd/config.toml << 'GREETD'
[terminal]
vt = 1

[default_session]
command = \"tuigreet --time --cmd sway\"
user = \"greeter\"
GREETD"

    sudo systemctl enable greetd
    success "greetd + tuigreet installed and configured"
}

install_sway() {
    log "Installing Sway window manager..."
    sudo apt-get install -y sway swaybg swayidle swaylock kanshi
    success "Sway installed"
}

install_waybar() {
    log "Installing Waybar..."
    sudo apt-get install -y waybar
    success "Waybar installed"
}

###############################################################################
# Shell and Terminal
###############################################################################

install_shell() {
    log "Installing Fish shell..."
    sudo apt-get install -y fish
    # FIX: Do NOT attempt to run fish or install OMF here.
    # (a) fish is not yet in the current bash session's PATH right after apt install.
    # (b) OMF's installer does not have a reliable --noninteractive flag and
    #     always opens an interactive prompt which hangs non-TTY installs.
    # Instead, write a clean Fish config directly — no plugin manager needed.
    success "Fish shell installed (OMF skipped — clean config written in configure step)"
}

install_kitty() {
    log "Installing Kitty terminal..."
    sudo apt-get install -y kitty
    success "Kitty installed"
}

###############################################################################
# App Launcher & Notifications
###############################################################################

install_launcher() {
    log "Installing Wofi (Wayland-native app launcher)..."
    sudo apt-get install -y wofi
    success "Wofi installed"
}

install_notifications() {
    log "Installing Dunst notification daemon..."
    sudo apt-get install -y dunst libnotify-bin
    success "Dunst installed (single daemon — no mako conflict)"
}

###############################################################################
# Audio — PipeWire (NOT PulseAudio)
###############################################################################

install_audio() {
    log "Installing PipeWire audio system..."

    # FIX: pipewire-audio-client-libraries was renamed to pipewire-audio in
    # Debian Bookworm. The old package name causes an apt "unable to locate" error.
    sudo apt-get install -y \
        pipewire \
        pipewire-pulse \
        pipewire-alsa \
        pipewire-audio \
        wireplumber \
        pavucontrol \
        playerctl

    # FIX: loginctl enable-linger allows the user's systemd session (and its
    # services — PipeWire, wireplumber) to persist after login and start on boot.
    # Without this, PipeWire user services fail to start under greetd.
    loginctl enable-linger "$USER" 2>/dev/null || true

    # These run as user services (no sudo). The || true is intentional:
    # systemctl --user may not be available mid-install before a session exists.
    systemctl --user enable pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null || true

    success "PipeWire audio installed"
}

###############################################################################
# Network and System Tools
###############################################################################

install_system_tools() {
    log "Installing system utilities..."
    sudo apt-get install -y \
        brightnessctl \
        btop \
        htop \
        network-manager \
        network-manager-gnome \
        lxpolkit

    sudo systemctl enable NetworkManager
    # Allow $USER to control backlight without sudo
    sudo usermod -aG video "$USER"
    success "System tools installed"
}

###############################################################################
# Applications
###############################################################################

install_apps() {
    log "Installing daily applications..."
    sudo apt-get install -y \
        thunar \
        thunar-volman \
        ranger \
        w3m \
        w3m-img \
        imv \
        mpv \
        mpd \
        mpc \
        ncmpcpp \
        firefox-esr \
        zathura \
        zathura-pdf-poppler \
        neovim \
        neofetch

    log "Installing screen capture tools..."
    sudo apt-get install -y grim slurp

    # FIX: wf-recorder is often absent from RPi OS repos. Try apt first,
    # skip silently if unavailable rather than hard-failing the whole install.
    sudo apt-get install -y wf-recorder 2>/dev/null || \
        warning "wf-recorder not found in repos — screen recording unavailable."

    # FIX: grimshot is a shell script, not a Debian package.
    if [ ! -f /usr/local/bin/grimshot ]; then
        log "Installing grimshot..."
        sudo wget -qO /usr/local/bin/grimshot \
            https://raw.githubusercontent.com/swaywm/sway/master/contrib/grimshot
        sudo chmod +x /usr/local/bin/grimshot
    fi

    # yt-dlp binary install (latest, always up to date with site changes)
    if [ ! -f /usr/local/bin/yt-dlp ]; then
        log "Installing yt-dlp binary..."
        sudo wget -qO /usr/local/bin/yt-dlp \
            https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp
        sudo chmod a+rx /usr/local/bin/yt-dlp
    fi

    mkdir -p ~/Music ~/.config/mpd ~/.local/share/mpd ~/.config/mpd/playlists
    touch ~/.local/share/mpd/database

    systemctl --user enable mpd.service 2>/dev/null || true

    success "Applications installed"
}

###############################################################################
# Fonts and Themes
###############################################################################

install_fonts() {
    log "Installing fonts..."
    sudo apt-get install -y fonts-noto fonts-twemoji fonts-liberation fonts-font-awesome

    mkdir -p ~/.local/share/fonts

    if ! fc-list | grep -qi "JetBrainsMono"; then
        log "Downloading JetBrains Mono Nerd Font v3.2.1..."
        # FIX: cd inside a subshell so the caller's working directory is unaffected
        (
            cd /tmp
            wget -q \
                "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.zip" \
                -O JetBrainsMono.zip
            unzip -q -o JetBrainsMono.zip -d ~/.local/share/fonts/JetBrainsMono
            rm -f JetBrainsMono.zip
        )
        fc-cache -f
        success "JetBrains Mono Nerd Font installed"
    else
        success "JetBrains Mono Nerd Font already present"
    fi
}

install_themes() {
    log "Installing GTK/Qt themes and icons..."
    # FIX (Trixie): arc-theme has been dropped from Debian 13 repos.
    # Use Adwaita-dark (always available) instead.
    # Added qt6ct + adwaita-qt6 — Qt6 apps are common in Trixie and need their own theme engine.
    sudo apt-get install -y \
        lxappearance \
        qt5ct \
        qt6ct \
        qtwayland5 \
        adwaita-qt \
        adwaita-qt6

    # FIX: git.io URL shortener was shut down by GitHub in April 2022.
    # All git.io links 404. papirus-icon-theme IS in Debian Bookworm apt — just use it.
    sudo apt-get install -y papirus-icon-theme

    success "Themes and icons installed"
}

###############################################################################
# Dotfiles Setup & Productivity Patches
###############################################################################

clone_and_copy_dotfiles() {
    log "Cloning sway-dotfiles repository..."

    if [ -d "$INSTALL_DIR" ]; then
        warning "Directory exists: $INSTALL_DIR. Backing up..."
        mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%s)"
    fi

    git clone "$REPO_URL" "$INSTALL_DIR"

    log "Copying configs to ~/.config..."
    mkdir -p ~/.config/{sway,waybar,kitty,wofi,dunst,fish}

    # FIX: Use a subshell for the cd so the working directory change is scoped
    # to this block. Without this, every function called after clone_and_copy_dotfiles
    # runs from inside $INSTALL_DIR and relative paths break.
    (
        cd "$INSTALL_DIR"
        [ -d sway ]   && cp -r sway/*   ~/.config/sway/   2>/dev/null || true
        [ -d waybar ] && cp -r waybar/* ~/.config/waybar/ 2>/dev/null || true
        [ -d kitty ]  && cp -r kitty/*  ~/.config/kitty/  2>/dev/null || true
        [ -d dunst ]  && cp -r dunst/*  ~/.config/dunst/  2>/dev/null || true
        [ -d fish ]   && cp -r fish/*   ~/.config/fish/   2>/dev/null || true
        [ -d btop ]   && cp -r btop     ~/.config/        2>/dev/null || true
        [ -d ranger ] && cp -r ranger   ~/.config/        2>/dev/null || true
    )

    # Swap Rofi for Wofi in the sway config (the dotfiles use rofi)
    if [ -f ~/.config/sway/config ]; then
        sed -i 's|exec rofi -show drun|exec wofi --show drun|g' ~/.config/sway/config || true
    fi

    success "Dotfiles copied"
}

patch_for_productivity() {
    log "Applying Pure Productivity patches (no gaps, no transparency)..."

    # 1. Remove gaps and enforce solid borders in Sway config
    if [ -f ~/.config/sway/config ]; then
        sed -i 's/^gaps inner.*/gaps inner 0/'  ~/.config/sway/config || true
        sed -i 's/^gaps outer.*/gaps outer 0/'  ~/.config/sway/config || true
        sed -i 's/^smart_gaps.*/smart_gaps off/' ~/.config/sway/config || true

        if ! grep -q "default_border" ~/.config/sway/config; then
            printf '\ndefault_border pixel 1\ndefault_floating_border pixel 1\n' \
                >> ~/.config/sway/config
        fi
    fi

    # 2. Make Kitty fully opaque
    if [ -f ~/.config/kitty/kitty.conf ]; then
        if grep -q "background_opacity" ~/.config/kitty/kitty.conf; then
            sed -i 's/^background_opacity.*/background_opacity 1.0/' \
                ~/.config/kitty/kitty.conf || true
        else
            echo "background_opacity 1.0" >> ~/.config/kitty/kitty.conf
        fi
    fi

    # 3. Strip transparency from Waybar CSS
    # FIX: Use sed -E (extended regex) for reliable \s handling across all
    # GNU sed versions. The basic-mode \s works on GNU sed but -E is safer
    # and the intent is clearer.
    if [ -f ~/.config/waybar/style.css ]; then
        sed -i -E \
            's/rgba\(([0-9]+),\s*([0-9]+),\s*([0-9]+),\s*[0-9.]+\)/rgb(\1,\2,\3)/g' \
            ~/.config/waybar/style.css || true
    fi

    success "Productivity patches applied"
}

###############################################################################
# GTK / Qt settings (Trixie — Adwaita-dark, no arc-theme)
###############################################################################

write_gtk_config() {
    log "Writing GTK and Qt theme settings..."
    mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0

    cat > ~/.config/gtk-3.0/settings.ini << 'GTK3_EOF'
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=JetBrainsMono Nerd Font 11
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-button-images=0
gtk-menu-images=0
gtk-enable-event-sounds=0
gtk-enable-input-feedback-sounds=0
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintfull
gtk-xft-rgba=rgb
gtk-application-prefer-dark-theme=1
GTK3_EOF

    cat > ~/.config/gtk-4.0/settings.ini << 'GTK4_EOF'
[Settings]
gtk-application-prefer-dark-theme=1
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=JetBrainsMono Nerd Font 11
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
GTK4_EOF

    # GTK2 legacy (Thunar still reads this)
    cat > ~/.gtkrc-2.0 << 'GTK2_EOF'
gtk-theme-name="Adwaita-dark"
gtk-icon-theme-name="Papirus-Dark"
gtk-font-name="JetBrainsMono Nerd Font 11"
gtk-cursor-theme-name="Adwaita"
gtk-cursor-theme-size=24
gtk-button-images=0
gtk-menu-images=0
gtk-enable-event-sounds=0
gtk-enable-input-feedback-sounds=0
GTK2_EOF

    # qt5ct config — Adwaita-dark style, matches GTK
    mkdir -p ~/.config/qt5ct
    cat > ~/.config/qt5ct/qt5ct.conf << 'QT5CT_EOF'
[Appearance]
style=adwaita-dark
color_scheme_path=
custom_palette=false
icon_theme=Papirus-Dark
standard_dialogs=default
QT5CT_EOF

    # qt6ct config — same settings, adwaita-qt6 package provides the style
    mkdir -p ~/.config/qt6ct
    cat > ~/.config/qt6ct/qt6ct.conf << 'QT6CT_EOF'
[Appearance]
style=adwaita-dark
color_scheme_path=
custom_palette=false
icon_theme=Papirus-Dark
standard_dialogs=default
QT6CT_EOF

    success "GTK and Qt theme settings written"
}

###############################################################################
# Fish shell config (written directly — no OMF required)
###############################################################################

configure_fish() {
    log "Writing Fish shell config..."
    mkdir -p ~/.config/fish/functions

    # Only write if no config exists yet (or the dotfiles didn't provide one)
    if [ ! -f ~/.config/fish/config.fish ]; then
        cat > ~/.config/fish/config.fish << 'FISH_EOF'
set -g fish_greeting

set -x EDITOR   nvim
set -x VISUAL   nvim
set -x BROWSER  firefox-esr
set -x QT_QPA_PLATFORMTHEME qt5ct
set -x QT_QPA_PLATFORM      wayland
set -x MOZ_ENABLE_WAYLAND   1
# Trixie: Qt6 apps use qt6ct; adwaita-qt6 provides the Adwaita-dark style
set -x QT6CT_STYLE          adwaita-dark

fish_add_path ~/.local/bin /usr/local/bin

alias vim='nvim'
alias ll='ls -lah --color=auto'
alias conf-sway='nvim ~/.config/sway/config'
alias conf-waybar='nvim ~/.config/waybar/config'
alias conf-kitty='nvim ~/.config/kitty/kitty.conf'
alias sway-reload='swaymsg reload'
FISH_EOF
    fi

    success "Fish config written"
}

###############################################################################
# Environment Variables
###############################################################################

setup_environment() {
    log "Configuring environment variables..."

    sudo bash -c 'cat > /etc/profile.d/wayland-env.sh << EOF
export MOZ_ENABLE_WAYLAND=1
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM="wayland;xcb"
export QT_QPA_PLATFORMTHEME=qt5ct
export QT6CT_STYLE=adwaita-dark
export SDL_VIDEODRIVER=wayland
export _JAVA_AWT_WM_NONREPARENTING=1
EOF'

    if [ "$SHELL" != "/usr/bin/fish" ]; then
        if confirm "Set Fish as default shell?"; then
            chsh -s /usr/bin/fish
            success "Fish shell set as default"
        fi
    else
        success "Fish is already the default shell"
    fi
}

###############################################################################
# Cleanup
###############################################################################

cleanup() {
    log "Cleaning up..."
    sudo apt-get autoremove -y
    sudo apt-get autoclean -y
    success "Cleanup completed"
}

###############################################################################
# Summary
###############################################################################

print_summary() {
    cat << EOF

${GREEN}═══════════════════════════════════════════════════════════════${NC}
${GREEN}           Sway Productivity Setup Complete!${NC}
${GREEN}═══════════════════════════════════════════════════════════════${NC}

${BLUE}Installed:${NC}
  ✓ Hardware-accelerated KMS driver + 128 MB GPU mem
  ✓ greetd + tuigreet (Wayland-native login manager)
  ✓ Sway + Wofi + Waybar (fully Wayland-native)
  ✓ PipeWire audio (Bookworm-native, no PA conflict)
  ✓ Dunst only (no mako conflict)
  ✓ Thunar + Ranger (no GNOME baggage)
  ✓ Adwaita-dark GTK + Papirus-Dark icons + qt5ct/qt6ct (Trixie)
  ✓ JetBrains Mono Nerd Font
  ✓ Firefox ESR, Neovim, MPV, MPD/ncmpcpp, Zathura
  ✓ Productivity patches: 0 gaps, opaque everywhere
  ✓ loginctl linger enabled (PipeWire survives greetd login)

${YELLOW}Next Steps:${NC}

  1. ${RED}REBOOT YOUR RASPBERRY PI${NC}
       sudo reboot

  2. You will see the tuigreet login prompt on TTY1.
     Log in — Sway starts automatically.

  3. Firefox theme:
     Firefox has no profile until first launch.
     Open it once, close it, then copy chrome/ from
     ~/sway-dotfiles manually.

${BLUE}Log file:${NC} $LOG_FILE

${GREEN}═══════════════════════════════════════════════════════════════${NC}

EOF
}

###############################################################################
# Main
###############################################################################

main() {
    clear
    cat << EOF
${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}
${BLUE}║      Sway OS Installer — Raspberry Pi 5 (Productivity)       ║${NC}
${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}

  Wayland-native · PipeWire · No gaps · No transparency
  greetd + tuigreet · Adwaita-dark · Catppuccin Mocha (Kitty/Waybar)

EOF

    if ! confirm "Begin installation?"; then
        log "Cancelled."
        exit 0
    fi

    check_system
    update_system
    install_build_tools

    install_wayland_base
    install_greeter
    install_sway
    install_waybar

    install_shell
    install_kitty
    install_launcher
    install_notifications

    install_audio
    install_system_tools
    install_apps

    install_fonts
    install_themes

    clone_and_copy_dotfiles
    patch_for_productivity
    write_gtk_config
    configure_fish

    setup_environment
    cleanup
    print_summary
}

main "$@"
