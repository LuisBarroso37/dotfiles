#!/usr/bin/env bash
set -euo pipefail

# Linux bootstrap for these dotfiles. Companion to install.sh (macOS/Homebrew).
#
# SUPPORTED — three package managers, and therefore these distro families:
#
#   pacman   Arch, Manjaro, EndeavourOS, CachyOS      fully verified (daily driver)
#   apt      Debian, Ubuntu, Mint, Pop!_OS, Raspbian  package names verified
#   dnf      Fedora, RHEL, Rocky, AlmaLinux           package names verified
#
# "Verified" means the package names were checked against each distro's package
# index and the GitHub release assets were fetched and run; it does NOT mean the
# script has been executed end-to-end on Debian or Fedora. Only Arch has had that.
#
# NOT supported, deliberately: zypper (openSUSE) and xbps (Void) were removed
# rather than carried as untested guesses — a branch that claims support and then
# fails on a wrong package name is worse than an upfront "unsupported". Alpine
# (apk) likewise: it is musl, so the prebuilt glibc binaries this script falls
# back to would not even load. Adding one back means verifying its package names
# and, for Alpine, teaching gh_release_install to prefer musl assets.
#
# Philosophy — because we can't know the distro *or* which tools its repos carry:
#   1. Detect the package manager (not the distro name) at runtime.
#   2. Best-effort install every tool via that PM; whatever the repo doesn't
#      carry is REPORTED at the end with a fallback recipe — never pretended.
#   3. On Arch, fall through to the AUR (yay/paru) for the three tools no distro
#      packages: sesh, carapace, herdr. Bootstrapped if no helper is installed.
#   3b. Then fall through to upstream GitHub releases, into ~/.local/bin. This is
#      what makes non-Arch distros viable: Debian has no yazi/sesh/carapace/herdr
#      and Fedora additionally lacks lazygit/starship, none of which have an AUR
#      to fall back on.
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

# Sourced early and deliberately: install.common.sh runs the refuse-to-run-as-root
# check at source time (it guards the stow/terminfo steps that live in there), and
# derives $BACKUP from $HOME. So nothing above this line may touch $HOME.
# Provides bin_name, stow_with_backup and finish_install (which runs the tail,
# verifies, prints next steps and returns non-zero if verification failed),
# plus the $BACKUP default.
# shellcheck source=install.common.sh
source "$DOTFILES/install.common.sh"

# Package-manager chatter is verbose and mostly noise, so it goes to a log and
# only surfaces when something actually fails. NOT /dev/null: the old script sent
# stderr there too, which swallowed sudo's password prompt and made the install
# look like it had hung.
LOG="${TMPDIR:-/tmp}/dotfiles-install.$$.log"
: > "$LOG"

MISSING=()  # tools no repo could provide → reported at the end with a recipe

# The GitHub-release fallback installs into ~/.local/bin. .zshrc already puts it
# first on PATH for future shells, but this run needs it too — otherwise the
# `command -v` checks in install_tool and verify_install can't see what we just
# installed and would report it missing.
mkdir -p "$HOME/.local/bin"
case ":$PATH:" in *":$HOME/.local/bin:"*) : ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac
export PATH

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
if   command -v apt-get >/dev/null 2>&1; then PM=apt
elif command -v dnf     >/dev/null 2>&1; then PM=dnf
elif command -v pacman  >/dev/null 2>&1; then PM=pacman
else
  echo "!! Unsupported package manager." >&2
  echo "   This script supports apt, dnf and pacman only — see the header." >&2
  echo "" >&2
  echo "   To use these dotfiles anyway, install the tools your distro provides" >&2
  echo "   by hand — at minimum git, curl, zsh, tmux and stow — then re-run." >&2
  echo "   The GitHub-releases fallback covers most of the rest." >&2
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
  esac
}

pkg_name() { # map a tool to this PM's package name (differences are the exception)
  case "$1" in
    fd)          case "$PM" in apt|dnf) echo "fd-find" ;; *) echo "fd" ;; esac ;;
    # Arch ships GitHub's CLI as github-cli, not gh.
    gh)          case "$PM" in pacman) echo "github-cli" ;; *) echo "gh" ;; esac ;;
    sevenzip)    case "$PM" in apt) echo "p7zip-full" ;; dnf) echo "p7zip" ;; *) echo "7zip" ;; esac ;;
    poppler)     case "$PM" in pacman) echo "poppler" ;; *) echo "poppler-utils" ;; esac ;;
    imagemagick) case "$PM" in dnf) echo "ImageMagick" ;; *) echo "imagemagick" ;; esac ;;
    shellcheck)  case "$PM" in dnf) echo "ShellCheck" ;; *) echo "shellcheck" ;; esac ;;
    # Supplies tic, used to compile terminfo/ below.
    ncurses)     case "$PM" in apt) echo "ncurses-bin" ;; *) echo "ncurses" ;; esac ;;
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
  *)      : ;;  # dnf and pacman refresh implicitly on install
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
# 2b. GitHub-releases fallback (any distro)
# ---------------------------------------------------------------------------
# The AUR covers sesh/carapace/herdr on Arch, but nothing equivalent exists on
# Debian or Fedora, where yazi, sesh, carapace and herdr — plus lazygit and
# starship on Fedora — are in no repo at all. All of them publish static Linux
# binaries on GitHub, so pull those into ~/.local/bin as a last resort before
# giving up on a tool.
gh_release_repo() {
  case "$1" in
    sesh)      echo "joshmedeski/sesh" ;;
    carapace)  echo "carapace-sh/carapace-bin" ;;
    herdr)     echo "herdrdev/herdr" ;;
    yazi)      echo "sxyazi/yazi" ;;
    lazygit)   echo "jesseduffield/lazygit" ;;
    starship)  echo "starship/starship" ;;
    zoxide)    echo "ajeetdsouza/zoxide" ;;
    git-delta) echo "dandavison/delta" ;;
    ripgrep)   echo "BurntSushi/ripgrep" ;;
    bat)       echo "sharkdp/bat" ;;
    fd)        echo "sharkdp/fd" ;;
    jq)        echo "jqlang/jq" ;;
    gh)        echo "cli/cli" ;;
    shellcheck) echo "koalaman/shellcheck" ;;
    *)         return 1 ;;
  esac
}

# Binaries to lift out of the archive. Only tools shipping more than one (or
# under a name that isn't bin_name) need an entry.
gh_release_bins() {
  case "$1" in
    yazi) echo "yazi ya" ;;   # ya is the plugin/package manager half
    *)    bin_name "$1" ;;
  esac
}

# Asset names across these projects are wildly inconsistent — sesh_Linux_x86_64,
# carapace-bin_1.7.3_linux_amd64, yazi-x86_64-unknown-linux-gnu.zip, a bare
# herdr-linux-x86_64 — so match the release list rather than hardcoding URLs
# that would rot at the next upstream rename.
gh_release_install() {
  local tool="$1" repo urls url arch_pat tmp f b rc=1
  repo="$(gh_release_repo "$tool")" || return 1
  command -v curl >/dev/null 2>&1 || return 1

  case "$(uname -m)" in
    x86_64|amd64)  arch_pat='x86[_-]?64|amd64|x64' ;;
    aarch64|arm64) arch_pat='aarch64|arm64' ;;
    *)             return 1 ;;   # no prebuilt binaries for anything else
  esac

  # Parsed with grep rather than jq: jq is itself one of the tools this may be
  # asked to install, so it cannot be a dependency of the installer.
  urls="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
          | grep -o '"browser_download_url": *"[^"]*"' \
          | sed 's/.*"\(https[^"]*\)"/\1/')" || return 1
  [ -n "$urls" ] || return 1

  # Drop distro packages, installers, checksums and signatures — we want the
  # portable archive or the bare binary, not something needing a package manager.
  _pick() {
    printf '%s\n' "$urls" \
      | grep -Ei 'linux' \
      | grep -Eiv '\.(deb|rpm|apk|msi|exe|pkg|sig|asc|pem|sha[0-9]*|sha[0-9]*sum|sbom|json|txt)$' \
      | grep -Ei "$arch_pat" \
      | grep -Ei "$1" \
      | head -1
  }
  # Prefer glibc builds — all three supported distros are glibc — then fall back
  # to whatever else is offered, since some projects (starship for a long while)
  # ship Linux musl builds exclusively. Static musl binaries run fine on glibc.
  url="$(_pick 'gnu')"
  [ -n "$url" ] || url="$(_pick '.')"
  [ -n "$url" ] || return 1

  tmp="$(mktemp -d)" || return 1
  if curl -fsSL -o "$tmp/asset" "$url"; then
    case "$url" in
      *.tar.gz|*.tgz) tar -xzf "$tmp/asset" -C "$tmp" 2>/dev/null ;;
      *.tar.xz)       tar -xJf "$tmp/asset" -C "$tmp" 2>/dev/null ;;
      *.tar.bz2)      tar -xjf "$tmp/asset" -C "$tmp" 2>/dev/null ;;
      *.zip)          unzip -oq "$tmp/asset" -d "$tmp" 2>/dev/null ;;
      *)              mv "$tmp/asset" "$tmp/$(bin_name "$tool")" ;;  # bare binary
    esac
    rc=0
    for b in $(gh_release_bins "$tool"); do
      # -print -quit: archives often nest under a versioned directory.
      f="$(find "$tmp" -type f -name "$b" -print -quit 2>/dev/null)"
      if [ -n "$f" ]; then
        install -m 0755 "$f" "$HOME/.local/bin/$b"
      else
        rc=1
      fi
    done
  fi
  rm -rf "$tmp"
  return "$rc"
}

# ---------------------------------------------------------------------------
# 3. Best-effort install (repo → AUR → GitHub releases → reported as missing)
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
  elif { echo "### GitHub releases: $tool"; gh_release_install "$tool"; } >>"$LOG" 2>&1; then
    echo "✓ $(gh_release_repo "$tool") (GitHub release → ~/.local/bin)"
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

# mise is packaged on Arch but not everywhere; fall back to its own
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
    pacman)
      pm_install ghostty >>"$LOG" 2>&1 || true ;;                    # official repo
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
    herdr)     echo "REQUIRED by .zshrc's wth/wthr — https://github.com/herdrdev/herdr/releases" ;;
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
finish_install
