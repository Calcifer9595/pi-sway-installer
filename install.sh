#!/usr/bin/env bash

###############################################################################
# Sway Dotfiles Installer for Raspberry Pi OS Lite (Bookworm)
# Optimized for Raspberry Pi 5 (8GB) - Pure Productivity Edition
# (No gaps, no transparency, Wayland-native, PipeWire audio)
###############################################################################

# Exit on error, but we carefully handle commands that might legally fail
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_URL="https://github.com/Ruixi-rebirth/sway-dotfiles.git"
INSTALL_DIR="${HOME}/sway-dotfiles"
LOG_FILE="${HOME}/.sway-install.log"

###############################################################################
# Helper Functions
###############################################################################

log() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; }
warning() { echo -e "${YELLOW}[!]${NC} $1" | tee -a "$LOG_FILE"; }

confirm() {
    local prompt="$1"
    local response
    read -p "$(echo -e ${YELLOW}${prompt}${NC}) (y/n) " response
    [[ "$response" =~ ^[Yy]$ ]]
}

###############################################################################
# System Setup & Hardware
###############################################################################

check_system() {
    log "Checking system compatibility..."
    
    if ! command -v sudo &> /dev/null; then
        error "sudo is required but not installed."
        exit 1
    fi

    # Raspberry Pi 5 DRM / KMS Check
    if grep -q "Raspberry Pi" /sys/firmware/devicetree/base/model 2>/dev/null; then
        log "Raspberry Pi detected. Verifying DRM graphics drivers..."
        if ! grep -q "dtoverlay=vc4-kms-v3d" /boot/firmware/config.txt; then
            warning "Hardware acceleration not found in /boot/firmware/config.txt"
            if confirm "Enable vc4-kms-v3d driver now? (Required for Sway)"; then
                echo "dtoverlay=vc4-kms-v3d" | sudo tee -a /boot/firmware/config.txt
                success "Graphics driver enabled. (Reboot will be required)"
            fi
        else
            success "Hardware acceleration (vc4-kms-v3d) is correctly configured."
        fi
    fi
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
    log "Installing Wayland base and Login Manager (greetd)..."
    # Removed generic 'wayland' package, added greetd for lightweight login
    sudo apt-get install -y wl-clipboard xwayland libwayland-dev greetd tuigreet
    
    # Configure greetd to launch sway
    sudo sed -i 's/command = .*/command = "tuigreet --time --cmd sway"/' /etc/greetd/config.toml || true
    sudo systemctl enable greetd
    success "Wayland base and greetd configured"
}

install_sway() {
    log "Installing Sway window manager..."
    sudo apt-get install -y sway swaybg swayidle swaylock
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
    log "Installing Fish shell and Oh-My-Fish..."
    sudo apt-get install -y fish
    
    if [ ! -d ~/.local/share/omf ]; then
        log "Installing Oh-My-Fish framework non-interactively..."
        curl -L https://get.oh-my.fish > /tmp/omf-install
        fish /tmp/omf-install --noninteractive || true
        rm -f /tmp/omf-install
    fi
    success "Fish shell installed"
}

install_kitty() {
    log "Installing Kitty terminal..."
    sudo apt-get install -y kitty
    success "Kitty installed"
}

###############################################################################
# App Launcher & Notifications
###############################################################################

install_rofi_alt() {
    log "Installing Wofi (Wayland-native app launcher)..."
    sudo apt-get install -y wofi
    success "Wofi installed"
}

install_notification_daemons() {
    log "Installing Dunst notification daemon..."
    # Removed mako-notifier to prevent dbus conflicts
    sudo apt-get install -y dunst libnotify-bin
    success "Dunst installed"
}

###############################################################################
# Audio, Network and System Tools
###############################################################################

install_audio() {
    log "Installing PipeWire audio system..."
    sudo apt-get install -y pipewire pipewire-pulse wireplumber pipewire-audio-client-libraries pavucontrol
    
    # Enable user services for Pipewire
    systemctl --user enable wireplumber.service pipewire.service pipewire-pulse.service || true
    success "PipeWire audio installed"
}

install_system_tools() {
    log "Installing system utilities..."
    sudo apt-get install -y brightnessctl btop htop network-manager network-manager-gnome
    sudo systemctl enable NetworkManager
    success "System tools installed"
}

###############################################################################
# File Managers, Media & Viewers
###############################################################################

install_apps() {
    log "Installing daily applications..."
    # Thunar is much lighter than Nautilus for Sway
    sudo apt-get install -y thunar ranger w3m w3m-img imv mpv firefox-esr zathura neovim neofetch
    
    log "Installing screen capture tools..."
    sudo apt-get install -y grim slurp wf-recorder
    
    # Grimshot is a script, not in Debian apt
    if [ ! -f /usr/local/bin/grimshot ]; then
        sudo wget -qO /usr/local/bin/grimshot https://raw.githubusercontent.com/swaywm/sway/master/contrib/grimshot
        sudo chmod +x /usr/local/bin/grimshot
    fi

    # yt-dlp via binary ensures it is up-to-date
    if [ ! -f /usr/local/bin/yt-dlp ]; then
        log "Installing yt-dlp binary..."
        sudo wget -qO /usr/local/bin/yt-dlp https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp
        sudo chmod a+rx /usr/local/bin/yt-dlp
    fi
    success "Applications installed"
}

###############################################################################
# Fonts and Themes
###############################################################################

install_fonts() {
    log "Installing fonts..."
    sudo apt-get install -y fonts-noto fonts-twemoji fonts-liberation
    
    log "Installing Nerd Fonts..."
    mkdir -p ~/.local/share/fonts
    
    # Subshell prevents the rest of the script from executing in the wrong directory
    (
        cd ~/.local/share/fonts
        if ! ls JetBrainsMono*.ttf 1> /dev/null 2>&1; then
            log "Downloading JetBrains Mono Nerd Font..."
            wget -q "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip" || warning "Download failed"
            unzip -q -o JetBrainsMono.zip 2>/dev/null || true
            rm -f JetBrainsMono.zip
            fc-cache -f -v
        fi
    )
    success "Fonts installed"
}

install_themes() {
    log "Installing GTK/Qt themes and Icon tools..."
    sudo apt-get install -y lxappearance qt5ct qtwayland5
    
    mkdir -p ~/.local/share/icons
    (
        cd ~/.local/share/icons
        if [ ! -d Papirus-Dark ]; then
            log "Installing Papirus icons..."
            wget -qO- https://git.io/papirus-icon-theme-install | sh
        fi
    )
    success "Themes installed"
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
    
    cd "$INSTALL_DIR"
    [ -d sway ] && cp -r sway/* ~/.config/sway/ 2>/dev/null || true
    [ -d waybar ] && cp -r waybar/* ~/.config/waybar/ 2>/dev/null || true
    [ -d kitty ] && cp -r kitty/* ~/.config/kitty/ 2>/dev/null || true
    [ -d dunst ] && cp -r dunst/* ~/.config/dunst/ 2>/dev/null || true
    [ -d fish ] && cp -r fish/* ~/.config/fish/ 2>/dev/null || true
    [ -d btop ] && cp -r btop ~/.config/ 2>/dev/null || true
    [ -d ranger ] && cp -r ranger ~/.config/ 2>/dev/null || true
    
    # Since we swapped Rofi for Wofi, alias the launcher in Sway config
    if [ -f ~/.config/sway/config ]; then
        sed -i 's/exec rofi -show drun/exec wofi --show drun/' ~/.config/sway/config || true
    fi
    
    success "Dotfiles copied"
}

patch_for_productivity() {
    log "Applying Pure Productivity patches (No gaps, no transparency)..."
    
    # 1. Remove gaps and add strict borders in Sway
    if [ -f ~/.config/sway/config ]; then
        sed -i 's/gaps inner.*/gaps inner 0/' ~/.config/sway/config || true
        sed -i 's/gaps outer.*/gaps outer 0/' ~/.config/sway/config || true
        sed -i 's/smart_gaps.*/smart_gaps off/' ~/.config/sway/config || true
        
        # Ensure strict 1px borders
        if ! grep -q "default_border" ~/.config/sway/config; then
            echo "default_border pixel 1" >> ~/.config/sway/config
            echo "default_floating_border pixel 1" >> ~/.config/sway/config
        fi
    fi

    # 2. Make Kitty terminal opaque
    if [ -f ~/.config/kitty/kitty.conf ]; then
        sed -i 's/background_opacity.*/background_opacity 1.0/' ~/.config/kitty/kitty.conf || true
    fi

    # 3. Strip transparency from Waybar (Replacing rgba(x,x,x,0.x) with hex/rgb limits transparency)
    if [ -f ~/.config/waybar/style.css ]; then
        # Converts rgba(r,g,b, 0.something) to solid rgb(r,g,b)
        sed -i 's/rgba(\([0-9]*\),\s*\([0-9]*\),\s*\([0-9]*\),\s*[0-9.]*)/rgb(\1,\2,\3)/g' ~/.config/waybar/style.css || true
    fi
    
    success "Productivity aesthetic applied."
}

###############################################################################
# Environment Variables
###############################################################################

setup_environment() {
    log "Configuring environment variables..."
    
    # Set Wayland and Qt Environment Variables globally
    sudo bash -c 'cat > /etc/profile.d/wayland-env.sh << EOF
export MOZ_ENABLE_WAYLAND=1
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM="wayland;xcb"
export QT_QPA_PLATFORMTHEME=qt5ct
EOF'

    if [ "$SHELL" != "/usr/bin/fish" ]; then
        if confirm "Set Fish as default shell?"; then
            chsh -s /usr/bin/fish
            success "Fish shell set as default"
        fi
    fi
}

###############################################################################
# Cleanup and Summary
###############################################################################

cleanup() {
    log "Cleaning up..."
    sudo apt-get autoremove -y
    sudo apt-get autoclean -y
    success "Cleanup completed"
}

print_summary() {
    cat << EOF

${GREEN}═══════════════════════════════════════════════════════════════${NC}
${GREEN}           Sway Productivity Setup Complete!${NC}
${GREEN}═══════════════════════════════════════════════════════════════${NC}

${BLUE}Installation Summary:${NC}
✓ Hardware accelerated KMS driver activated
✓ GreetD Login Manager installed
✓ Sway + Wofi + Waybar (Wayland Native)
✓ PipeWire audio system
✓ Pure Productivity patches applied (0 Gaps, Opaque Backgrounds)
✓ Firefox, Thunar, Kitty, and utility tools installed

${YELLOW}Next Steps & Important Notes:${NC}
1. ${RED}REBOOT YOUR RASPBERRY PI${NC} to apply hardware & systemd changes.
   Run: sudo reboot

2. Upon reboot, you will see the 'tuigreet' terminal login. 
   Log in with your username and password, and Sway will launch instantly.

3. Firefox Theme Setup:
   Because Firefox has not been launched yet, its profile doesn't exist.
   To install the theme later, open Firefox once, close it, then copy
   the theme files manually from ~/sway-dotfiles.

${GREEN}═══════════════════════════════════════════════════════════════${NC}
EOF
}

###############################################################################
# Main Execution
###############################################################################

main() {
    clear
    cat << EOF
${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}
${BLUE}║      Sway OS Installer for Raspberry Pi 5 (Productivity)      ║${NC}
${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}
This script installs a heavily optimized, Wayland-native environment.
EOF

    if ! confirm "Begin installation?"; then exit 0; fi
    
    check_system
    update_system
    install_build_tools
    
    install_wayland_base
    install_sway
    install_waybar
    
    install_shell
    install_kitty
    install_rofi_alt
    install_notification_daemons
    
    install_audio
    install_system_tools
    install_apps
    
    install_fonts
    install_themes
    
    clone_and_copy_dotfiles
    patch_for_productivity
    
    setup_environment
    cleanup
    print_summary
}

main "$@"