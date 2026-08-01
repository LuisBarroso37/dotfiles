#!/usr/bin/env bash
set -euo pipefail

# Linux bootstrap for these dotfiles. Companion to install.sh (macOS/Homebrew).
#
# Philosophy — because we can't know the distro *or* which tools its repos carry:
#   1. Detect the package manager (not the distro name) at runtime.
#   2. Best-effort install every tool via that PM; whatever the repo doesn't
#      carry is REPORTED at the end with a fallback recipe — never pretended.
#   3. On Arch, fall through to the AUR (yay/paru) for the three tools no distro
#      packages: sesh, carapace, herdr. Bootstrapped if no helper is installed.
#   4. mise (runtime version manager) comes from the repo when packaged and from
#      its own installer otherwise; language runtimes are then chosen per machine
#      with `mise use -g` (see .zshrc).
#   5. The tail (submodules, stow, TPM, sesh file) is identical to install.sh.
#
# Re-running this script is safe: every step is idempotent.

# Resolve the repo from this script's own location, so the bootstrap works from a
# clone anywhere — not just ~/dotfiles. (Was hardcoded to $HOME/dotfiles, which
# broke `git clone … ~/src/dotfiles && ./install.linux.sh`.)
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Mirror of install.sh's guard, pointing the other way.
if [ "$(uname -s)" = "Darwin" ]; then
  echo "install.linux.sh is for Linux. On macOS, run ./install.sh instead." >&2
  exit 1
fi

# Anything this script has to move out of the way lands here rather than being
# clobbered — a fresh machine usually ships a skeleton ~/.zshrc, and stow refuses
# to overwrite it (which is what made a first run abort with "existing target").
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

# Package-manager chatter is verbose and mostly noise, so it goes to a log and
# only surfaces when something actually fails. NOT /dev/null: the old script sent
# stderr there too, which swallowed sudo's password prompt and made the install
# look like it had hung.
LOG="${TMPDIR:-/tmp}/dotfiles-install.$$.log"
: > "$LOG"

MISSING=()  # tools no repo could provide → reported at the end with a recipe

SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then SUDO="sudo"; fi

# ---------------------------------------------------------------------------
# 0. Prime sudo up front
# ---------------------------------------------------------------------------
# Package output is redirected to $LOG below, so a sudo prompt raised mid-loop
# would be invisible and the script would sit there looking dead. Authenticate
# once here, where the prompt is on the terminal, then keep the timestamp warm
# for the rest of the run.
if [ -n "$SUDO" ]; then
  echo "==> Requesting sudo (needed to install packages)"
  sudo -v || { echo "!! sudo authentication failed" >&2; exit 1; }
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
  SUDO_KEEPALIVE=$!
  trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null || true' EXIT
fi

# ---------------------------------------------------------------------------
# 1. Detect the package manager
# ---------------------------------------------------------------------------
echo "==> Detecting package manager"
if   command -v apt-get      >/dev/null 2>&1; then PM=apt
elif command -v dnf          >/dev/null 2>&1; then PM=dnf
elif command -v pacman       >/dev/null 2>&1; then PM=pacman
elif command -v zypper       >/dev/null 2>&1; then PM=zypper
elif command -v apk          >/dev/null 2>&1; then PM=apk
elif command -v xbps-install >/dev/null 2>&1; then PM=xbps
else
  echo "!! No supported package manager found (apt/dnf/pacman/zypper/apk/xbps)."
  echo "   Install the tools manually, then re-run from the '==> Stowing' step."
  exit 1
fi
echo "   Using: $PM"

pm_install() { # install one or more packages; returns non-zero if the PM fails
  case "$PM" in
    apt)    $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf)    $SUDO dnf install -y "$@" ;;
    pacman) $SUDO pacman -S --needed --noconfirm "$@" ;;
    zypper) $SUDO zypper --non-interactive install "$@" ;;
    apk)    $SUDO apk add "$@" ;;
    xbps)   $SUDO xbps-install -Sy "$@" ;;
  esac
}

pkg_name() { # map a tool to this PM's package name (differences are the exception)
  case "$1" in
    fd)          case "$PM" in apt|dnf) echo "fd-find" ;; *) echo "fd" ;; esac ;;
    git-delta)   case "$PM" in apk|xbps) echo "delta" ;; *) echo "git-delta" ;; esac ;;
    # Arch/Alpine/Void ship GitHub's CLI as github-cli, not gh.
    gh)          case "$PM" in pacman|apk|xbps) echo "github-cli" ;; *) echo "gh" ;; esac ;;
    sevenzip)    case "$PM" in apt) echo "p7zip-full" ;; dnf) echo "p7zip" ;; *) echo "7zip" ;; esac ;;
    poppler)     case "$PM" in pacman) echo "poppler" ;; zypper) echo "poppler-tools" ;; *) echo "poppler-utils" ;; esac ;;
    imagemagick) case "$PM" in dnf|zypper|xbps) echo "ImageMagick" ;; *) echo "imagemagick" ;; esac ;;
    shellcheck)  case "$PM" in dnf|zypper) echo "ShellCheck" ;; *) echo "shellcheck" ;; esac ;;
    # Supplies tic, used to compile terminfo/ below.
    ncurses)     case "$PM" in apt) echo "ncurses-bin" ;; zypper) echo "ncurses-utils" ;; *) echo "ncurses" ;; esac ;;
    *)           echo "$1" ;;
  esac
}

bin_name() { # the executable a tool provides, for "is it already here?" checks
  case "$1" in
    neovim)      echo "nvim" ;;
    ripgrep)     echo "rg" ;;
    git-delta)   echo "delta" ;;
    sevenzip)    echo "7z" ;;
    poppler)     echo "pdftoppm" ;;
    imagemagick) echo "magick" ;;
    ncurses)     echo "tic" ;;
    fontconfig)  echo "fc-cache" ;;
    *)           echo "$1" ;;
  esac
}

aur_name() { # AUR package for the tools no distro repo carries
  case "$1" in
    carapace) echo "carapace-bin" ;;
    sesh)     echo "sesh-bin" ;;
    herdr)    echo "herdr" ;;
    *)        echo "$1" ;;
  esac
}

# Refresh package indexes once up front where the PM needs it.
echo "==> Refreshing package index"
case "$PM" in
  apt)    $SUDO apt-get update >>"$LOG" 2>&1 || true ;;
  zypper) $SUDO zypper --non-interactive refresh >>"$LOG" 2>&1 || true ;;
  xbps)   $SUDO xbps-install -S >>"$LOG" 2>&1 || true ;;
  *)      : ;;  # dnf/pacman/apk refresh implicitly on install
esac

# ---------------------------------------------------------------------------
# 2. AUR helper (Arch only)
# ---------------------------------------------------------------------------
# sesh, carapace and herdr are in no distro's official repos. On Arch they're all
# one `yay -S` away, so bootstrap a helper rather than dumping three manual
# recipes on the user. yay-bin is the prebuilt package — no Go toolchain needed.
AUR=""
if [ "$PM" = pacman ]; then
  if   command -v yay  >/dev/null 2>&1; then AUR=yay
  elif command -v paru >/dev/null 2>&1; then AUR=paru
  elif [ "$(id -u)" -ne 0 ]; then
    echo "==> Bootstrapping yay (AUR helper — for sesh, carapace, herdr)"
    _aurtmp="$(mktemp -d)"
    if { pm_install git base-devel \
         && git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$_aurtmp/yay-bin" \
         && ( cd "$_aurtmp/yay-bin" && makepkg -si --noconfirm ); } >>"$LOG" 2>&1
    then
      AUR=yay
      echo "   ✓ yay"
    else
      echo "   ✗ yay — could not bootstrap (see $LOG)"
    fi
    rm -rf "$_aurtmp"
  fi
  [ -n "$AUR" ] && echo "   AUR helper: $AUR"
fi

# makepkg refuses to run as root, so AUR installs never take $SUDO — the helper
# escalates internally for the pacman step.
aur_install() {
  [ -n "$AUR" ] || return 1
  "$AUR" -S --needed --noconfirm "$@"
}

# ---------------------------------------------------------------------------
# 3. Best-effort install (repo → AUR → reported as missing)
# ---------------------------------------------------------------------------
install_tool() {
  local tool="$1" pkg bin
  pkg="$(pkg_name "$tool")"
  bin="$(bin_name "$tool")"
  printf '   %-13s ' "$tool"
  if command -v "$bin" >/dev/null 2>&1; then
    echo "✓ already installed"
    return 0
  fi
  if { echo "### $PM: $tool ($pkg)"; pm_install "$pkg"; } >>"$LOG" 2>&1; then
    echo "✓ $pkg"
  elif { echo "### AUR: $tool ($(aur_name "$tool"))"; aur_install "$(aur_name "$tool")"; } >>"$LOG" 2>&1; then
    echo "✓ $(aur_name "$tool") (AUR)"
  else
    echo "✗ not available"
    MISSING+=("$tool")
  fi
}

# git + curl are bootstrap deps (submodules, TPM clone, mise installer).
# zsh is NOT optional and was the omission that made a fresh install look like it
# had done nothing: every config here is zsh-side, so without it (and without the
# chsh in step 5) you land back in bash and none of this is ever loaded.
# jq and herdr are likewise load-bearing — .zshrc's wth/wthr/_herdr_ws_at pipe
# `herdr workspace list` through jq.
# The last four are yazi's preview backends (video / archive / PDF / HEIC-JXL),
# and were only in install.sh — every Linux rebuild came up without previews.
echo "==> Installing tools (best-effort; details in $LOG)"
for tool in \
  git curl zsh tmux stow neovim ripgrep fzf zoxide bat fd \
  gh lazygit git-delta starship atuin yazi carapace sesh herdr \
  mise jq shellcheck ncurses unzip fontconfig \
  ffmpeg sevenzip poppler imagemagick
do
  install_tool "$tool"
done

# ---------------------------------------------------------------------------
# 4. Debian/Ubuntu binary-name fixups (fd→fdfind, bat→batcat)
# ---------------------------------------------------------------------------
# ~/.local/bin is already first on PATH (see zsh/.zshrc). Alias the renamed
# binaries back to the names the configs expect.
if [ "$PM" = apt ]; then
  mkdir -p "$HOME/.local/bin"
  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    echo "   ↳ symlinked fdfind → ~/.local/bin/fd"
  fi
  if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
    ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
    echo "   ↳ symlinked batcat → ~/.local/bin/bat"
  fi
fi

# mise is packaged on Arch/Void but not everywhere; fall back to its own
# installer only when the loop above couldn't get it.
if ! command -v mise >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/mise" ]; then
  echo "==> Installing mise via its own installer"
  curl -fsSL https://mise.run | sh >>"$LOG" 2>&1 \
    && MISSING=("${MISSING[@]/mise}") \
    || echo "   ✗ mise — see $LOG"
fi

# ---------------------------------------------------------------------------
# 5. Make zsh the login shell
# ---------------------------------------------------------------------------
# The step whose absence caused "I installed it and nothing happened": the repo
# stows .zshrc/.zshenv/.zprofile, but a distro default account is on bash, so
# none of them are ever read.
if command -v zsh >/dev/null 2>&1; then
  ZSH_PATH="$(command -v zsh)"
  CURRENT_SHELL="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
  if [ "$CURRENT_SHELL" = "$ZSH_PATH" ]; then
    echo "==> Login shell already zsh"
  else
    # chsh only accepts shells listed in /etc/shells.
    # Failing to append here is not fatal (chsh below reports it), so never let
    # a read-only /etc/shells or a denied sudo take the whole script down.
    if ! grep -qxF "$ZSH_PATH" /etc/shells 2>/dev/null; then
      echo "$ZSH_PATH" | $SUDO tee -a /etc/shells >/dev/null 2>&1 || true
    fi
    if [ -t 0 ]; then
      printf '==> Change login shell from %s to %s? [Y/n] ' "${CURRENT_SHELL:-unknown}" "$ZSH_PATH"
      read -r _reply
      case "${_reply:-y}" in
        [Nn]*) echo "   skipped — run 'chsh -s $ZSH_PATH' when ready" ;;
        *)     chsh -s "$ZSH_PATH" && echo "   ✓ login shell set (takes effect on next login)" \
                 || echo "   ✗ chsh failed — run 'chsh -s $ZSH_PATH' manually" ;;
      esac
    else
      echo "==> Non-interactive: login shell left as ${CURRENT_SHELL:-unknown}"
      echo "   run: chsh -s $ZSH_PATH"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 6. ghostty — official on some PMs, community/snap on others
# ---------------------------------------------------------------------------
# (https://ghostty.org/docs/install/binary#linux)
echo "==> Installing ghostty"
if ! command -v ghostty >/dev/null 2>&1; then
  case "$PM" in
    pacman|xbps)
      pm_install ghostty >>"$LOG" 2>&1 || true ;;                    # official repo
    apk)
      # official, but lives in the 'testing' repo (not enabled on stable)
      { $SUDO apk add ghostty \
        || $SUDO apk add --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing ghostty; } >>"$LOG" 2>&1 || true ;;
    dnf)
      # not in Fedora's official repos → community COPR
      { $SUDO dnf copr enable -y scottames/ghostty && pm_install ghostty; } >>"$LOG" 2>&1 || true ;;
  esac
  # cross-distro fallback: the semi-official snap (classic confinement)
  if ! command -v ghostty >/dev/null 2>&1 && command -v snap >/dev/null 2>&1; then
    $SUDO snap install ghostty --classic >>"$LOG" 2>&1 || true
  fi
fi
if command -v ghostty >/dev/null 2>&1; then
  echo "   ✓ ghostty"
else
  echo "   ✗ ghostty — no direct package for $PM. Options:"
  case "$PM" in
    apt)    echo "       • community .deb: https://github.com/mkasberg/ghostty-ubuntu" ;;
    dnf)    echo "       • COPR: sudo dnf copr enable scottames/ghostty && sudo dnf install ghostty" ;;
    zypper) echo "       • openSUSE dropped it (Zig version) — build from source" ;;
  esac
  echo "       • snap:     sudo snap install ghostty --classic"
  echo "       • AppImage: https://ghostty.org/docs/install/binary (any distro)"
fi

# ---------------------------------------------------------------------------
# 7. Nerd Font
# ---------------------------------------------------------------------------
# Packaged on Arch; everywhere else pull the release zip into ~/.local/share/fonts.
# This used to be printed as a manual step, so a fresh machine came up with a
# broken prompt (starship + the tmux/yazi themes are all glyph-dependent).
echo "==> Installing JetBrainsMono Nerd Font"
if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
  echo "   ✓ already installed"
elif [ "$PM" = pacman ] && pm_install ttf-jetbrains-mono-nerd >>"$LOG" 2>&1; then
  echo "   ✓ ttf-jetbrains-mono-nerd"
elif command -v curl >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
  _fontdir="$HOME/.local/share/fonts"
  mkdir -p "$_fontdir"
  if curl -fsSL -o "$_fontdir/JetBrainsMono.zip" \
       https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip >>"$LOG" 2>&1 \
     && unzip -oq "$_fontdir/JetBrainsMono.zip" -d "$_fontdir" >>"$LOG" 2>&1
  then
    rm -f "$_fontdir/JetBrainsMono.zip"
    fc-cache -f >>"$LOG" 2>&1 || true
    echo "   ✓ installed to $_fontdir"
  else
    rm -f "$_fontdir/JetBrainsMono.zip"
    echo "   ✗ download failed — see $LOG"
  fi
else
  echo "   ✗ need curl + unzip to fetch the font"
fi

# ---------------------------------------------------------------------------
# 8. Report what no repo could provide, with fallback recipes
# ---------------------------------------------------------------------------
hint() {
  case "$1" in
    starship)  echo "curl -sS https://starship.rs/install.sh | sh" ;;
    atuin)     echo "curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh" ;;
    zoxide)    echo "curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh" ;;
    yazi)      echo "cargo install --locked yazi-fm yazi-cli   (or GitHub releases)" ;;
    sesh)      echo "mise use -g go@latest && go install github.com/joshmedeski/sesh/v2@latest" ;;
    carapace)  echo "GitHub releases: https://github.com/carapace-sh/carapace-bin/releases" ;;
    herdr)     echo "REQUIRED by .zshrc's wth/wthr — https://github.com/herdr-dev/herdr releases" ;;
    jq)        echo "REQUIRED by .zshrc's wth/wthr — GitHub releases: jqlang/jq" ;;
    lazygit)   echo "go install github.com/jesseduffield/lazygit@latest   (or GitHub releases)" ;;
    git-delta) echo "cargo install git-delta   (or GitHub releases: dandavison/delta)" ;;
    gh)        echo "GitHub's repo: https://github.com/cli/cli/blob/trunk/docs/install_linux.md" ;;
    neovim)    echo "If the packaged version is too old: GitHub releases (neovim/neovim) or the AppImage" ;;
    zsh)       echo "REQUIRED — none of these dotfiles load without it" ;;
    mise)      echo "curl https://mise.run | sh" ;;
    sevenzip)  echo "yazi archive previews only" ;;
    poppler)   echo "yazi PDF previews only" ;;
    imagemagick) echo "yazi HEIC/AVIF/JXL previews only" ;;
    ffmpeg)    echo "yazi video previews only" ;;
    shellcheck) echo "optional — shell linting in nvim" ;;
    *)         echo "install manually" ;;
  esac
}

if [ ${#MISSING[@]} -gt 0 ]; then
  echo ""
  echo "==> Install these manually (no repo provided them):"
  printf '%s\n' "${MISSING[@]}" | awk 'NF && !seen[$0]++' | while read -r t; do
    printf '   - %-12s %s\n' "$t" "$(hint "$t")"
  done
fi

# ---------------------------------------------------------------------------
# 8b. Optional per-machine install steps
# ---------------------------------------------------------------------------
# An untracked install.local.sh next to this script (gitignored + stowignored) is
# sourced here if present — extra packages, embedded toolchains, etc. — so this
# tracked script stays portable.
if [ -f "$DOTFILES/install.local.sh" ]; then
  echo ""
  echo "==> Running install.local.sh (machine-specific)"
  # shellcheck source=/dev/null
  source "$DOTFILES/install.local.sh"
fi

# ---------------------------------------------------------------------------
# 9. Shared tail — mirrors install.sh
# ---------------------------------------------------------------------------
echo ""
echo "==> Initialising submodules"
cd "$DOTFILES"
if [ -e "$DOTFILES/.git" ]; then
  git submodule update --init --recursive
else
  echo "   ! not a git clone — skipping (catppuccin/tmux theme will be absent)"
fi

# Stow refuses to overwrite a real file that it doesn't own, and a fresh distro
# account usually ships a skeleton ~/.zshrc — which aborted the whole restow and
# left the install half-applied. Move whatever it objects to into $BACKUP and
# retry, using stow's own conflict report as the authority on what's in the way.
stow_with_backup() {
  local target="$1"; shift
  local attempt out conflicts rel
  for attempt in 1 2 3; do
    if out="$(stow --restow --target="$target" "$@" 2>&1)"; then
      [ -n "$out" ] && printf '%s\n' "$out"
      return 0
    fi
    conflicts="$(printf '%s\n' "$out" \
      | sed -n -e 's/^ *\* existing target is[^:]*: *//p' \
               -e 's/^ *\* cannot stow .* over existing target \(.*\) since.*$/\1/p')"
    if [ -z "$conflicts" ]; then
      printf '%s\n' "$out" >&2
      return 1
    fi
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      [ -e "$target/$rel" ] || [ -L "$target/$rel" ] || continue
      mkdir -p "$BACKUP/$(dirname "$rel")"
      mv "$target/$rel" "$BACKUP/$rel"
      echo "   ↳ backed up $target/$rel → $BACKUP/$rel"
    done <<< "$conflicts"
  done
  echo "!! stow still reports conflicts after 3 attempts" >&2
  return 1
}

# Stow BEFORE cloning TPM: this makes ~/.config/tmux a symlink into the repo, so the
# TPM clone below lands at $DOTFILES/tmux/plugins/tpm (gitignored). Cloning first
# would create a real ~/.config/tmux directory and make `stow .` conflict on tmux.
echo "==> Stowing dotfiles"
mkdir -p "$HOME/.config"      # stow aborts if --target from .stowrc doesn't exist
stow_with_backup "$HOME/.config" .   # nvim, tmux, sesh, ghostty, starship, atuin, git, lazygit, yazi
stow_with_backup "$HOME" zsh         # zsh dotfiles live in ~, not ~/.config

## herdr is stowignored: it writes runtime state (logs, sockets, session.json)
## into ~/.config/herdr, so that directory has to stay a real directory rather
## than a stow-folded symlink into the repo. Only config.toml is linked, by hand.
echo "==> Linking herdr config"
# An earlier run (before herdr was added to .stowrc's ignore list) folded the whole
# directory into a symlink → $DOTFILES/herdr. Left in place, the ln below resolves
# source and target to the same path, fails "are the same file", and `set -e` kills
# the script before terminfo/TPM/sesh ever run. Unfold it first.
if [ -L "$HOME/.config/herdr" ]; then
  rm -f "$HOME/.config/herdr"
  echo "   ↳ unfolded stow symlink at ~/.config/herdr into a real directory"
fi
mkdir -p "$HOME/.config/herdr"
ln -sfn "$DOTFILES/herdr/config.toml" "$HOME/.config/herdr/config.toml"

## terminfo/ is stowignored: these are compiled into ~/.terminfo, not symlinked.
## Adds an xterm-256color variant carrying Smulx/Setulc so neovim emits undercurl
## inside herdr panes (see the TERM swap in zsh/.zshrc).
echo "==> Compiling terminfo entries"
if command -v tic >/dev/null 2>&1; then
  for ti in "$DOTFILES"/terminfo/*.terminfo; do
    [ -e "$ti" ] || continue
    tic -x -o "$HOME/.terminfo" "$ti" && echo "   ✓ $(basename "$ti")"
  done
else
  echo "   ✗ tic not found (install ncurses) — undercurl in herdr panes will be off"
fi

echo "==> Installing TPM (tmux plugin manager)"
if [ ! -d "$HOME/.config/tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm"
else
  echo "   ✓ already present"
fi

# sesh/sesh.toml imports a machine-specific session file; sesh errors if the
# import target is missing, so guarantee it exists (empty is fine). Put work/
# client project sessions here — it stays untracked, outside the dotfiles repo.
echo "==> Ensuring machine-specific sesh session file exists"
[ -f "$HOME/.config/sesh.local.toml" ] || touch "$HOME/.config/sesh.local.toml"

# ---------------------------------------------------------------------------
# 10. Verify
# ---------------------------------------------------------------------------
# The old script reported on the package step only, so a run that stowed nothing
# still ended with "Done!". Check what actually landed.
echo ""
echo "==> Verifying"
_fail=0

for tool in zsh tmux stow neovim ripgrep fzf zoxide bat fd gh lazygit \
            git-delta starship atuin yazi carapace sesh herdr mise jq; do
  bin="$(bin_name "$tool")"
  command -v "$bin" >/dev/null 2>&1 || { echo "   ✗ missing binary: $bin ($tool)"; _fail=1; }
done

check_link() { # $1 = path that must resolve into the repo
  # Deliberately not `[ -L ]`: when stow folds a whole package it links the
  # *directory* (~/.config/ghostty → repo/ghostty), so the file underneath is a
  # real file reached through the symlink. What matters is where the path ends
  # up, not which component carries the link — so resolve and compare.
  local real
  if [ -e "$1" ] && real="$(readlink -f "$1")" \
     && case "$real" in "$DOTFILES"/*) true ;; *) false ;; esac; then
    return 0
  fi
  echo "   ✗ not linked into the repo: $1"; _fail=1
}
for l in "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.zprofile" \
         "$HOME/.config/nvim" "$HOME/.config/tmux" "$HOME/.config/sesh" \
         "$HOME/.config/starship.toml" "$HOME/.config/atuin" \
         "$HOME/.config/git" "$HOME/.config/lazygit" "$HOME/.config/yazi" \
         "$HOME/.config/ghostty/config" "$HOME/.config/herdr/config.toml"; do
  check_link "$l"
done

[ -d "$HOME/.config/tmux/plugins/tpm" ] || { echo "   ✗ TPM not installed"; _fail=1; }
[ -f "$HOME/.config/sesh.local.toml" ]  || { echo "   ✗ sesh.local.toml missing"; _fail=1; }
infocmp xterm-256color-undercurl >/dev/null 2>&1 \
  || echo "   ! terminfo entry xterm-256color-undercurl not compiled (undercurl only)"

if [ "$_fail" -eq 0 ]; then
  echo "   ✓ all checks passed"
else
  echo "   (anything above is listed with a recipe in the 'Install these manually' section)"
fi

[ -d "$BACKUP" ] && echo "" && echo "==> Files moved aside are in $BACKUP"

echo ""
echo "Done! Log: $LOG"
echo "Next:"
echo "  1. Restart your terminal (or 'exec zsh') — the login shell change needs a re-login."
echo "  2. In tmux, press prefix+I to install plugins."
echo "  3. Run 'gh auth login' so wtr can detect merged PRs."
echo "  4. Pick language runtimes: mise use -g node@lts java@corretto-25 go@latest"
