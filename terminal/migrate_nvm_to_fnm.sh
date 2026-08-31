#!/bin/bash
set -euo pipefail

FNM_VERSION="1.39.0"
FNM_RELEASE_BASE="https://github.com/Schniz/fnm/releases/download/v$FNM_VERSION"

info() {
  printf '[INFO] %s\n' "$1"
}

fail() {
  printf '[ERROR] %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

usage() {
  cat <<'EOF'
Usage: migrate_nvm_to_fnm.sh [--yes]

Migrates the active NVM-managed Node.js installation to fnm. By default, the
script asks for confirmation that every listed global package came from the
configured npm registry. Use --yes to provide that confirmation noninteractively.
EOF
}

has_nvm_references() {
  grep -Eq 'NVM_DIR|(^|[/])nvm\.sh|\.nvm/|(^|[^[:alnum:]_])nvm([^[:alnum:]_]|$)' "$1"
}

validate_absolute_path() {
  local name="$1" value="$2"
  [[ -z "$value" || "$value" == /* ]] || fail "$name must be an absolute path: $value"
}

snapshot_global_packages() {
  local output_file="$1"
  local json_file="$WORK_DIR/npm-global.json"

  npm ls --global --depth=0 --json --long >"$json_file" \
    || fail "Unable to obtain a complete global npm package inventory."

  if ! node - "$json_file" >"$output_file" <<'NODE'
var fs = require("fs");
var tree = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
var dependencies = tree.dependencies || {};
var problems = tree.problems || [];
var root = tree.path || "";
var prefix = root ? root.replace(/\/$/, "") + "/node_modules/" : "";

if (problems.length > 0) {
  throw new Error("npm reported inventory problems: " + problems.join("; "));
}

Object.keys(dependencies).sort().forEach(function (name) {
  var dependency = dependencies[name] || {};
  var version = dependency.version;

  if (!version) {
    throw new Error("Global package has no installable version: " + name);
  }
  if (dependency.link === true) {
    throw new Error("Linked global packages cannot be migrated automatically: " + name);
  }
  if (dependency.name && dependency.name !== name) {
    throw new Error("Aliased global packages cannot be migrated automatically: " + name);
  }
  if (dependency.path && prefix && dependency.path.indexOf(prefix) !== 0) {
    throw new Error("Global package is outside the npm prefix: " + name);
  }
  if (dependency.extraneous === true) {
    throw new Error("Extraneous global package cannot be migrated safely: " + name);
  }

  process.stdout.write(name + "@" + version + "\n");
});
NODE
  then
    fail "Unable to validate the global npm package inventory."
  fi
}

build_zshrc_candidate() {
  if ! node - "$ZSHRC" "$ZSHRC_CANDIDATE" "$UNSUPPORTED_NVM" <<'NODE'
var fs = require("fs");
var sourcePath = process.argv[2];
var outputPath = process.argv[3];
var unsupportedPath = process.argv[4];
var source = fs.readFileSync(sourcePath, "utf8");
var lines = source.split("\n");
var output = [];
var unsupported = [];
var inFnmBlock = false;

var canonical = [
  'export NVM_DIR="$HOME/.nvm"',
  'export NVM_DIR="${HOME}/.nvm"',
  'export NVM_DIR=$HOME/.nvm',
  'export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"',
  '[ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"',
  '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"',
  '[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"',
  '[ -s "$NVM_DIR/bash_completion" ] && \\. "$NVM_DIR/bash_completion"',
  '[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"',
  '[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"'
];

function containsNvmReference(line) {
  return /NVM_DIR|(^|\/)nvm\.sh|\.nvm\/|(^|[^A-Za-z0-9_])nvm([^A-Za-z0-9_]|$)/.test(line);
}

lines.forEach(function (line, index) {
  if (line === "# >>> fnm setup >>>") {
    if (inFnmBlock) {
      throw new Error("Nested fnm setup block");
    }
    inFnmBlock = true;
    return;
  }
  if (line === "# <<< fnm setup <<<") {
    if (!inFnmBlock) {
      throw new Error("Unexpected fnm setup block terminator");
    }
    inFnmBlock = false;
    return;
  }
  if (inFnmBlock) {
    return;
  }

  var code = line.replace(/[ \t]+#.*$/, "").trim();
  if (canonical.indexOf(code) !== -1) {
    return;
  }
  if (containsNvmReference(line)) {
    unsupported.push(String(index + 1) + ":" + line);
  }
  output.push(line);
});

if (inFnmBlock) {
  throw new Error("Unterminated fnm setup block");
}

fs.writeFileSync(outputPath, output.join("\n"));
fs.writeFileSync(unsupportedPath, unsupported.join("\n"));
NODE
  then
    fail "Unable to parse $ZSHRC safely."
  fi

  if [[ -s "$UNSUPPORTED_NVM" ]]; then
    printf '[ERROR] Unsupported NVM configuration in %s:\n' "$ZSHRC" >&2
    cat "$UNSUPPORTED_NVM" >&2
    fail "Only canonical NVM setup lines are migrated automatically."
  fi

  cat >>"$ZSHRC_CANDIDATE" <<'EOF'

# >>> fnm setup >>>
FNM_INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fnm"
[[ -d "$FNM_INSTALL_DIR" ]] && export PATH="$FNM_INSTALL_DIR:$PATH"
if command -v fnm >/dev/null 2>&1; then
  eval "$(fnm env --use-on-cd --shell zsh)"
fi
unset FNM_INSTALL_DIR
# <<< fnm setup <<<
EOF

  zsh -n "$ZSHRC_CANDIDATE" || fail "The generated Zsh configuration is invalid."
}

install_fnm() {
  local architecture asset checksum archive
  architecture="$(uname -m)"

  case "$architecture" in
    x86_64|amd64)
      asset="fnm-linux.zip"
      checksum="7807664f39d39fc518da1c35ba0181e4b3267603c4b1dedeb4b5fc6ae440a224"
      ;;
    aarch64|arm64)
      asset="fnm-arm64.zip"
      checksum="4eaff58b2c5bf30d0934027572dd0b5bbb60d2a1af309230b53662d4b1d45599"
      ;;
    armv6l|armv7l)
      asset="fnm-arm32.zip"
      checksum="3d11d96a49d49cb3f11051a1aabf968fce30db665e79ee7d81851059731fa4ac"
      ;;
    *)
      fail "Unsupported CPU architecture: $architecture"
      ;;
  esac

  archive="$WORK_DIR/$asset"
  info "Downloading fnm v$FNM_VERSION for $architecture..."
  curl -fL --retry 3 --output "$archive" "$FNM_RELEASE_BASE/$asset"
  printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --status \
    || fail "fnm archive checksum verification failed."

  unzip -q "$archive" -d "$FNM_STAGING_DIR"
  chmod 755 "$FNM_STAGING_DIR/fnm"
  "$FNM_STAGING_DIR/fnm" --version | grep -Fx "fnm $FNM_VERSION" >/dev/null \
    || fail "Unexpected fnm version after installation."
}

cleanup() {
  local cleanup_failed=0 status="$1"
  trap '' INT TERM
  trap - EXIT
  set +e

  if [[ -n "$STAGING_MULTISHELL_PATH" && "$STAGING_MULTISHELL_PATH" == */fnm_multishells/* ]]; then
    rm -rf -- "$STAGING_MULTISHELL_PATH"
    [[ ! -e "$STAGING_MULTISHELL_PATH" && ! -L "$STAGING_MULTISHELL_PATH" ]] || cleanup_failed=1
  fi
  if [[ -n "$FNM_STAGING_DIR" && "$FNM_STAGING_DIR" != "$FNM_INSTALL_DIR" ]]; then
    rm -rf -- "$FNM_STAGING_DIR"
    [[ ! -e "$FNM_STAGING_DIR" && ! -L "$FNM_STAGING_DIR" ]] || cleanup_failed=1
  fi
  if [[ -n "$ZSHRC_REPLACEMENT" ]]; then
    rm -f -- "$ZSHRC_REPLACEMENT"
    [[ ! -e "$ZSHRC_REPLACEMENT" && ! -L "$ZSHRC_REPLACEMENT" ]] || cleanup_failed=1
  fi
  if [[ -n "$WORK_DIR" ]]; then
    rm -rf -- "$WORK_DIR"
    [[ ! -e "$WORK_DIR" && ! -L "$WORK_DIR" ]] || cleanup_failed=1
  fi
  if (( LOCK_CREATED == 1 )); then
    rm -f -- "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR"
    [[ ! -e "$LOCK_DIR" && ! -L "$LOCK_DIR" ]] || cleanup_failed=1
  fi

  if (( cleanup_failed == 1 )); then
    printf '[ERROR] One or more temporary migration paths could not be cleaned up.\n' >&2
    status=1
  fi
  if (( MIGRATION_COMPLETE == 0 && FNM_PUBLISHED == 1 )); then
    printf '[ERROR] fnm was retained at %s; the original %s was not replaced.\n' "$FNM_INSTALL_DIR" "$ZSHRC" >&2
  fi
  exit "$status"
}

ASSUME_REGISTRY_ORIGIN=0
while (( $# > 0 )); do
  case "$1" in
    --yes)
      ASSUME_REGISTRY_ORIGIN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "Unknown argument: $1"
      ;;
  esac
  shift
done

[[ "$(uname -s)" == "Linux" ]] || fail "This migration script supports Linux only."

for required in awk cat chmod cp curl diff dirname env grep id mkdir mktemp mv node npm readlink rm rmdir sha256sum stat unzip zsh; do
  require_command "$required"
done

validate_absolute_path HOME "$HOME"
for variable in XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_RUNTIME_DIR XDG_STATE_HOME; do
  validate_absolute_path "$variable" "${!variable:-}"
done
[[ -d "$HOME" && -O "$HOME" ]] || fail "HOME must be an existing directory owned by the current user: $HOME"
if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
  [[ -d "$XDG_RUNTIME_DIR" && -O "$XDG_RUNTIME_DIR" && ! -L "$XDG_RUNTIME_DIR" ]] \
    || fail "XDG_RUNTIME_DIR must be an owned, nonsymlinked directory: $XDG_RUNTIME_DIR"
fi

ZSHRC="$HOME/.zshrc"
[[ -f "$ZSHRC" ]] || fail "Zsh configuration not found: $ZSHRC"
[[ ! -L "$ZSHRC" ]] || fail "Symbolic .zshrc files are not migrated automatically: $ZSHRC"

LOCK_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/linux-config"
mkdir -p "$LOCK_ROOT"
[[ -d "$LOCK_ROOT" && -O "$LOCK_ROOT" && ! -L "$LOCK_ROOT" ]] \
  || fail "Migration lock directory must be owned and nonsymlinked: $LOCK_ROOT"
LOCK_DIR="$LOCK_ROOT/nvm-to-fnm.lock"
LOCK_CREATED=0
WORK_DIR=""
ZSHRC_REPLACEMENT=""
FNM_STAGING_DIR=""
STAGING_MULTISHELL_PATH=""
FNM_PUBLISHED=0
MIGRATION_COMPLETE=0
mkdir -m 700 "$LOCK_DIR" 2>/dev/null \
  || fail "Another migration may be running; lock directory already exists: $LOCK_DIR"
LOCK_CREATED=1
trap 'cleanup $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf '%s\n' "$$" >"$LOCK_DIR/pid"

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
FNM_INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/fnm"
NODE_BIN="$(command -v node)"

case "$NODE_BIN" in
  "$NVM_DIR"/*) ;;
  *)
    if command -v fnm >/dev/null 2>&1 \
      && grep -q '^# >>> fnm setup >>>$' "$ZSHRC" \
      && ! has_nvm_references "$ZSHRC" \
      && [[ "$NODE_BIN" == *fnm_multishells* ]] \
      && [[ "$(fnm current)" == "$(node --version)" ]]; then
      info "The active shell is already migrated to fnm."
      MIGRATION_COMPLETE=1
      exit 0
    fi
    fail "The active Node executable is not managed by NVM: $NODE_BIN"
    ;;
esac

if command -v fnm >/dev/null 2>&1 \
  || [[ -n "${FNM_DIR:-}" ]] \
  || [[ -e "$HOME/.fnm" || -L "$HOME/.fnm" ]] \
  || [[ -e "$FNM_INSTALL_DIR" || -L "$FNM_INSTALL_DIR" ]]; then
  fail "An existing or partial fnm installation was found; automated merging is intentionally refused."
fi
unset FNM_DIR

NODE_VERSION="$(node --version)"
NODE_VERSION="${NODE_VERSION#v}"
[[ -n "$NODE_VERSION" ]] || fail "Unable to determine the active Node version."

NVM_DIR_REAL="$(readlink -f "$NVM_DIR")"
CURRENT_NPM_PREFIX_REAL="$(readlink -f "$(npm prefix --global)")"
case "$CURRENT_NPM_PREFIX_REAL" in
  "$NVM_DIR_REAL"/*) ;;
  *) fail "The current npm global prefix is outside NVM: $CURRENT_NPM_PREFIX_REAL" ;;
esac

WORK_DIR="$(mktemp -d)"
GLOBAL_PACKAGES_BEFORE="$WORK_DIR/global-packages-before.txt"
GLOBAL_PACKAGES_AFTER="$WORK_DIR/global-packages-after.txt"
ZSHRC_CANDIDATE="$WORK_DIR/zshrc"
UNSUPPORTED_NVM="$WORK_DIR/unsupported-nvm.txt"
ZSHRC_BACKUP=""

ZSHRC_HASH="$(sha256sum "$ZSHRC" | awk '{print $1}')"
snapshot_global_packages "$GLOBAL_PACKAGES_BEFORE"
build_zshrc_candidate

mapfile -t GLOBAL_PACKAGES <"$GLOBAL_PACKAGES_BEFORE"
for package in "${GLOBAL_PACKAGES[@]}"; do
  npm view "$package" version --json >/dev/null \
    || fail "Global package is unavailable from the configured npm registry: $package"
done

info "Node version to migrate: v$NODE_VERSION"
if (( ${#GLOBAL_PACKAGES[@]} > 0 )); then
  info "Registry packages to migrate:"
  printf '  - %s\n' "${GLOBAL_PACKAGES[@]}"
else
  info "No global npm packages need migration."
fi

if (( ASSUME_REGISTRY_ORIGIN == 0 && ${#GLOBAL_PACKAGES[@]} > 0 )); then
  [[ -t 0 ]] \
    || fail "Registry origin confirmation requires an interactive terminal or the explicit --yes flag."
  printf 'Confirm that every listed package was installed from the configured npm registry [y/N]: '
  read -r registry_confirmation
  case "$registry_confirmation" in
    y|Y|yes|YES|Yes) ;;
    *) fail "Migration cancelled because package origin was not confirmed." ;;
  esac
fi

ZSHRC_BACKUP="$(mktemp "${ZSHRC}.bak.nvm-to-fnm.XXXXXXXX")"
cp -p "$ZSHRC" "$ZSHRC_BACKUP"

FNM_PARENT="$(dirname "$FNM_INSTALL_DIR")"
mkdir -p "$FNM_PARENT"
[[ -d "$FNM_PARENT" && -O "$FNM_PARENT" && ! -L "$FNM_PARENT" ]] \
  || fail "fnm parent directory must be owned and nonsymlinked: $FNM_PARENT"
FNM_STAGING_DIR="$(mktemp -d "${FNM_INSTALL_DIR}.migrate.XXXXXXXX")"
install_fnm

export FNM_DIR="$FNM_STAGING_DIR"
export PATH="$FNM_STAGING_DIR:$PATH"
eval "$("$FNM_STAGING_DIR/fnm" env --shell bash)"
STAGING_MULTISHELL_PATH="${FNM_MULTISHELL_PATH:-}"

info "Installing Node v$NODE_VERSION with fnm..."
fnm install "$NODE_VERSION"
fnm default "$NODE_VERSION"
fnm use "$NODE_VERSION" >/dev/null

FNM_STAGING_REAL="$(readlink -f "$FNM_STAGING_DIR")"
STAGING_NPM_PREFIX_REAL="$(readlink -f "$(npm prefix --global)")"
case "$STAGING_NPM_PREFIX_REAL" in
  "$FNM_STAGING_REAL"/*) ;;
  *) fail "The fnm npm global prefix escaped the staging directory: $STAGING_NPM_PREFIX_REAL" ;;
esac

if (( ${#GLOBAL_PACKAGES[@]} > 0 )); then
  info "Installing global npm registry packages under fnm..."
  npm install --global "${GLOBAL_PACKAGES[@]}"
fi

snapshot_global_packages "$GLOBAL_PACKAGES_AFTER"
diff -u "$GLOBAL_PACKAGES_BEFORE" "$GLOBAL_PACKAGES_AFTER" \
  || fail "The global npm package inventory changed during migration."

trap '' INT TERM
mv -T -n "$FNM_STAGING_DIR" "$FNM_INSTALL_DIR"
[[ ! -e "$FNM_STAGING_DIR" && ! -L "$FNM_STAGING_DIR" && -x "$FNM_INSTALL_DIR/fnm" ]] \
  || fail "fnm installation path appeared during migration; refusing to overwrite it."
FNM_STAGING_DIR=""
FNM_PUBLISHED=1
trap 'exit 130' INT
trap 'exit 143' TERM
unset FNM_DIR FNM_MULTISHELL_PATH
FNM_DIR="$FNM_INSTALL_DIR" "$FNM_INSTALL_DIR/fnm" default "$NODE_VERSION"

VALIDATION_ENV=(
  "HOME=$HOME"
  "USER=${USER:-$(id -un)}"
  "LOGNAME=${LOGNAME:-${USER:-$(id -un)}}"
  "SHELL=$(command -v zsh)"
  "TERM=${TERM:-xterm-256color}"
  "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  "EXPECTED_NODE_VERSION=v$NODE_VERSION"
  "ZSHRC_CANDIDATE=$ZSHRC_CANDIDATE"
)
for variable in XDG_CACHE_HOME XDG_CONFIG_HOME XDG_DATA_HOME XDG_RUNTIME_DIR XDG_STATE_HOME; do
  [[ -n "${!variable:-}" ]] && VALIDATION_ENV+=("$variable=${!variable}")
done

if ! env -i "${VALIDATION_ENV[@]}" "$(command -v zsh)" -dfi -c '
  [[ -f "$HOME/.zshenv" ]] && source "$HOME/.zshenv"
  source "$ZSHRC_CANDIDATE"
  [[ "$(node --version)" == "$EXPECTED_NODE_VERSION" ]] || exit 10
  [[ "$(command -v node)" == *fnm_multishells* ]] || exit 11
  [[ "$(fnm current)" == "$EXPECTED_NODE_VERSION" ]] || exit 12
  fnm --version
  node --version
  npm --version
'; then
  fail "Clean Zsh validation failed."
fi

[[ "$(sha256sum "$ZSHRC" | awk '{print $1}')" == "$ZSHRC_HASH" ]] \
  || fail "$ZSHRC changed while the migration was running."
ZSHRC_REPLACEMENT="$(mktemp "${ZSHRC}.migrate.XXXXXXXX")"
cp "$ZSHRC_CANDIDATE" "$ZSHRC_REPLACEMENT"
chmod --reference="$ZSHRC" "$ZSHRC_REPLACEMENT"
[[ "$(sha256sum "$ZSHRC" | awk '{print $1}')" == "$ZSHRC_HASH" ]] \
  || fail "$ZSHRC changed immediately before replacement."

info "Replacing $ZSHRC; do not edit it until completion is reported."
trap '' INT TERM
mv -f "$ZSHRC_REPLACEMENT" "$ZSHRC"
ZSHRC_REPLACEMENT=""
MIGRATION_COMPLETE=1
trap 'exit 130' INT
trap 'exit 143' TERM

info "Migration completed successfully."
info "Zsh backup: $ZSHRC_BACKUP"
info "NVM was retained at $NVM_DIR. Remove it only after validating a new terminal session."
