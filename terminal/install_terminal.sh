#!/bin/bash
# Fresh-install bootstrap for Zsh + Oh My Zsh + Powerlevel10k + GNOME Terminal.
set -euo pipefail

echo "[INFO] Installing dependencies..."
sudo apt update
sudo apt install -y zsh git curl unzip fonts-powerline tree

echo "[INFO] Installing Oh My Zsh..."
OMZ_INSTALLER="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$OMZ_INSTALLER"
export RUNZSH=no
sh "$OMZ_INSTALLER"
rm -f "$OMZ_INSTALLER"

echo "[INFO] Installing Powerlevel10k..."
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [[ -d "$P10K_DIR" ]]; then
  echo "[INFO] Powerlevel10k already present, skipping clone."
else
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
fi

echo "[INFO] Copying configuration files..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for f in .zshrc .p10k.zsh; do
  if [[ -f "$HOME/$f" ]]; then
    backup="$HOME/$f.bak.$(date +%Y%m%d%H%M%S)"
    echo "[INFO] Backing up existing ~/$f to $backup"
    cp "$HOME/$f" "$backup"
  fi
  cp "$SCRIPT_DIR/$f" "$HOME/$f"
done

echo "[INFO] Installing JetBrains Mono Nerd Font..."
mkdir -p "$HOME/.local/share/fonts"
FONT_ZIP="$(mktemp --suffix=.zip)"
curl -fLo "$FONT_ZIP" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
unzip -o "$FONT_ZIP" -d "$HOME/.local/share/fonts"
rm -f "$FONT_ZIP"
fc-cache -fv

echo "[INFO] Installing zsh-syntax-highlighting..."
SYNTAX_HL_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
if [[ -d "$SYNTAX_HL_DIR" ]]; then
  echo "[INFO] zsh-syntax-highlighting already present, skipping clone."
else
  git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$SYNTAX_HL_DIR"
fi

echo "[INFO] Installing Papirus icon theme (latest release)..."
PAPIRUS_TAG=$(curl -fsSL https://api.github.com/repos/PapirusDevelopmentTeam/papirus-icon-theme/releases/latest \
  | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
PAPIRUS_TAG="${PAPIRUS_TAG:-master}"
curl -fsSL https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh | TAG="$PAPIRUS_TAG" sh

echo "[INFO] Setting Zsh as the default shell..."
chsh -s "$(command -v zsh)"

if command -v gsettings >/dev/null 2>&1; then
  echo "[INFO] Configuring GNOME Terminal..."
  PROFILE_ID=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")
  PROFILE_PATH="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$PROFILE_ID/"

  gsettings set "$PROFILE_PATH" use-system-font false
  gsettings set "$PROFILE_PATH" font 'JetBrainsMono Nerd Font 12'
  gsettings set "$PROFILE_PATH" use-theme-colors false
  gsettings set "$PROFILE_PATH" background-color '#1E1E1E'
  gsettings set "$PROFILE_PATH" foreground-color '#C0C0C0'

  echo "[INFO] Setting Papirus as the active icon theme..."
  gsettings set org.gnome.desktop.interface icon-theme 'Papirus'
else
  echo "[INFO] gsettings not found, skipping GNOME Terminal styling and icon theme selection."
fi

echo "[INFO] Installation complete."
echo "[INFO] Log out or restart to apply all changes."
