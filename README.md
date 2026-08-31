# linux_config

Personal Linux bootstrap configuration for a fresh Ubuntu/Debian desktop with GNOME.

## Requirements

- Ubuntu/Debian with `apt` and a GNOME desktop session.
- A user with `sudo` access (the terminal installer needs it).
- Internet access (downloads Oh My Zsh, plugins, and a Nerd Font release from GitHub).

## Contents

- `terminal/` installs Zsh, Oh My Zsh, Powerlevel10k, fnm with the latest Node.js LTS release, syntax highlighting, JetBrains Mono Nerd Font, the Papirus icon theme (always the latest release), and configures GNOME Terminal.
- `apps/` contains application configuration, including Firefox preferences and Zed settings.
- `git/` contains a `.gitconfig` template (user identity, default branch, rebase-on-pull).
- `wallpaper/` stores the wallpaper image and its source link.

## First installation

Run the terminal installer as the desktop user:

```bash
bash terminal/install_terminal.sh
```

The script uses `sudo` to install packages, replaces `~/.zshrc` and `~/.p10k.zsh` (backing up any existing ones first), installs the latest Papirus icon theme release, changes the login shell to Zsh, and configures the active GNOME Terminal profile plus the system icon theme. It is intended for a fresh installation; on GNOME-less desktops the terminal styling and icon theme selection steps are skipped automatically.

Log out and back in after it completes so the login-shell change takes effect.

## Migrate an existing NVM setup

Run the migration from a Zsh session where NVM currently provides `node` and
`npm`:

```bash
bash terminal/migrate_nvm_to_fnm.sh
```

The script preserves the active Node.js version and exact versions of global
packages available through the configured npm registry. It installs a pinned,
checksum-verified `fnm` release, backs up and atomically updates `~/.zshrc`, and
validates the result in a clean Zsh session. Linked, aliased, extraneous, or
noncanonical NVM setups and global npm prefixes outside the managed Node.js
installation are rejected without replacing the existing shell configuration.
Before changing anything, it asks you to confirm that the listed global
packages came from the configured npm registry; `--yes` provides that
confirmation for an intentional noninteractive run. The script does not delete
`~/.nvm`; keep that directory until the migrated tools have been verified from
a new terminal.

## Application configuration

- [Firefox preferences](apps/README.md): copy `user.js` into the Firefox profile shown in `about:profiles`.
- Zed: copy `apps/zed_editor/settings.json` to `~/.config/zed/settings.json`. Back up an existing settings file first.
- [Git](git/README.md): copy `git/.gitconfig` to `~/.gitconfig`. Back up an existing one first.
- Wallpaper: apply `wallpaper/wallpaper.png` (see [wallpaper/README.md](wallpaper/README.md) for the original source).

Application installation is intentionally manual.
