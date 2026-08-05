# linux_config

Personal Linux bootstrap configuration for a fresh Ubuntu/Debian desktop with GNOME.

## Contents

- `terminal/` installs Zsh, Oh My Zsh, Powerlevel10k, syntax highlighting, JetBrains Mono Nerd Font, and configures GNOME Terminal.
- `apps/` contains application configuration, including Firefox preferences and Zed settings.
- `wallpaper/` stores the source for the wallpaper.

## First installation

Run the terminal installer as the desktop user:

```bash
bash terminal/install_terminal.sh
```

The script uses `sudo` to install packages, replaces `~/.zshrc` and `~/.p10k.zsh`, changes the login shell to Zsh, and configures the active GNOME Terminal profile. It is intended for a fresh installation; do not run it again on an existing shell setup without first backing up your configuration.

Log out and back in after it completes so the login-shell change takes effect.

## Application configuration

- [Firefox preferences](apps/README.md): copy `user.js` into the Firefox profile shown in `about:profiles`.
- Zed: copy `apps/zed_editor/settings.json` to `~/.config/zed/settings.json`. Back up an existing settings file first.
- Wallpaper: download and apply the image linked in [wallpaper/README.md](wallpaper/README.md).

Application installation is intentionally manual.
