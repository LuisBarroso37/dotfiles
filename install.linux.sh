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
#   5. The tail (submodules, stow, TPM, sesh file, verification) is shared with
#      install.sh — it lives in install.common.sh, sourced below.
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

# Run as YOURSELF, never `sudo ./install.linux.sh`. Under sudo, $HOME becomes
# /root, so every user-scoped step silently targets the wrong account:
#   * stow links the whole repo into /root instead of your home;
#   * chsh switches root's login shell, leaving yours on bash — so the install
#     looks like it did nothing;
#   * terminfo compiles into /root/.terminfo;
#   * makepkg (and therefore yay/paru) refuse to run as root outright, so every
#     AUR package fails.
# The script escalates with sudo on its own for the package steps that need it.
if [ "$(id -u)" -eq 0 ] && [ -z "${DOTFILES_ALLOW_ROOT:-}" ]; then
  echo "!! Do not run this script with sudo or as root." >&2
  echo "   \$HOME would be $HOME, so stow, chsh and terminfo would all target" >&2
  echo "   the wrong account, and yay/makepkg refuse to run as root." >&2
  echo "" >&2
  echo "   Run it as your normal user instead:" >&2
  echo "     ./install.linux.sh" >&2
  echo "" >&2
  echo "   (It calls sudo itself for the package installs.)" >&2
  echo "   Genuinely provisioning a root account? DOTFILES_ALLOW_ROOT=1 overrides." >&2
  exit 1
fi

# Sourced AFTER the root guard: install.common.sh derives $BACKUP from $HOME, and
# under sudo that would be /root. Provides bin_name, stow_with_backup,
# run_shared_tail, verify_install, print_next_steps and the $BACKUP default.
# shellcheck source=install.common.sh
source "$DOTFILES/install.common.sh"

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

# </dev/null throughout: output is redirected to the log, so anything that stops
# to ask a question would hang with no visible prompt. Fail fast on EOF instead.
pm_install() { # install one or more packages; returns non-zero if the PM fails
  case "$PM" in
    apt)    $SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" </dev/null ;;
    dnf)    $SUDO dnf install -y "$@" </dev/null ;;
    pacman) $SUDO pacman -S --needed --noconfirm "$@" </dev/null ;;
    zypper) $SUDO zypper --non-interactive install "$@" </dev/null ;;
    apk)    $SUDO apk add "$@" </dev/null ;;
    xbps)   $SUDO xbps-install -Sy "$@" </dev/null ;;
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

aur_name() { # AUR package for the tools no distro repo carries
  # Always the -bin variants. The from-source herdr pulls cargo + zig just to
  # rebuild a binary upstream already ships, which turns a ~5s install into a
  # multi-minute compile that reads as a hang behind the log redirect.
  case "$1" in
    carapace) echo "carapace-bin" ;;
    sesh)     echo "sesh-bin" ;;
    herdr)    echo "herdr-bin" ;;
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
#
# --noconfirm alone is NOT enough to make yay non-interactive: when a previous
# run left files in /tmp/yay it still opens the "Packages to cleanBuild?" and
# "Diffs to show?" menus, which block forever behind the log redirect with no
# visible prompt. The --answer* flags pre-answer all four menus; </dev/null
# below is the backstop, turning any prompt we haven't anticipated into an
# immediate EOF failure rather than a hang.
aur_install() {
  [ -n "$AUR" ] || return 1
  case "$AUR" in
    yay)  yay  -S --needed --noconfirm --removemake \
              --answerclean=None --answerdiff=None \
              --answeredit=None  --answerupgrade=None "$@" </dev/null ;;
    paru) paru -S --needed --noconfirm --removemake --skipreview "$@" </dev/null ;;
    *)    "$AUR" -S --needed --noconfirm "$@" </dev/null ;;
  esac
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
# 9. Shared tail + verification — install.common.sh (also used by install.sh)
# ---------------------------------------------------------------------------
NEXT_STEP_FIRST="Log out and back in — the login-shell change only applies to a new login."
run_shared_tail
verify_install
print_next_steps
