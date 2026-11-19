#!/usr/bin/env bash
set -euo pipefail

# Linux bootstrap for these dotfiles. Companion to install.sh (macOS/Homebrew).
#
# SUPPORTED — three package managers, and therefore these distro families:
#
#   pacman   Arch, Manjaro, EndeavourOS, CachyOS      archlinux:latest + real hardware
#   apt      Debian, Ubuntu, Mint, Pop!_OS            debian:trixie
#   dnf      Fedora, RHEL, Rocky, AlmaLinux           fedora:latest
#
# Only x86_64 and aarch64 are supported. Use the 64-bit Raspberry Pi OS with apt.
#
# Each was run end-to-end as a non-root sudo user in a clean container of the
# image named above, finishing with every verification check passing — not merely
# eyeballed against a package index. Arch additionally runs on real hardware.
#
# Two honest limits on that claim. The derivatives listed in each row are inferred
# from sharing the parent's package manager and repos; only the named image was
# actually tested. And a container exercises no GUI, so ghostty and the Nerd Font
# are confirmed to *install* but never to render.
#
# zypper, xbps and apk are unsupported. Alpine also needs musl-specific release selection.
#
# Try native packages, then AUR on Arch, then GitHub releases into ~/.local/bin.
# Release downloads use upstream checksums when available and replace unusably old packages.
# Report missing tools with manual recipes. mise also has its own installer fallback.
# Shared setup and verification live in install.common.sh.
#
# Re-running this script is safe: every step is idempotent.

# Resolve the repo from this script, regardless of the clone location.
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Mirror of install.sh's guard, pointing the other way.
if [ "$(uname -s)" = "Darwin" ]; then
  echo "install.linux.sh is for Linux. On macOS, run ./install.sh instead." >&2
  exit 1
fi

# Source shared steps before touching $HOME so the root guard runs first.
# shellcheck source=install.common.sh
source "$DOTFILES/install.common.sh"

# Keep package output in a log for troubleshooting. Authenticate sudo before redirecting output.
# mktemp prevents predictable paths from following an attacker's symlink.
LOG="$(mktemp)"

MISSING=()     # tools no repo could provide → reported at the end with a recipe
UNVERIFIED=()  # GitHub-release downloads no upstream checksum covered → also reported

# Use a token when available to raise GitHub's API limit from 60 to 5000 requests/hour.
GH_API_TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [ -z "$GH_API_TOKEN" ] && command -v gh >/dev/null 2>&1; then
  GH_API_TOKEN="$(gh auth token 2>/dev/null || true)"
fi
# Reject characters that cannot be safely interpolated into curl's quoted header.
case "$GH_API_TOKEN" in
  "") ;;
  *[!A-Za-z0-9_]*)
    echo "!! ignoring a GitHub token containing unexpected characters" >&2
    GH_API_TOKEN="" ;;
esac
GH_RATE_LIMITED=0   # set when the API refuses us, so the report can say so

# Return the response body followed by the HTTP status on its own line.
# Pass the token through stdin, not process arguments that other users can read.
# Quote the header value, since curl silently ignores an unquoted value with spaces.
gh_api_get() {
  if [ -n "$GH_API_TOKEN" ]; then
    printf 'header = "Authorization: Bearer %s"\n' "$GH_API_TOKEN" \
      | curl -sSL -w '\n%{http_code}' --config - "$1" 2>/dev/null
  else
    curl -sSL -w '\n%{http_code}' "$1" 2>/dev/null
  fi
}

# Put release downloads on PATH for this run, not only future zsh sessions.
mkdir -p "$HOME/.local/bin"
case ":$PATH:" in *":$HOME/.local/bin:"*) : ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac
export PATH

SUDO=""
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then SUDO="sudo"; fi

# ---------------------------------------------------------------------------
# 0. Prime sudo up front
# ---------------------------------------------------------------------------
# Authenticate while the prompt is visible, then keep sudo authorization active.
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
    apt)    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" </dev/null ;;
    dnf)    $SUDO dnf install -y "$@" </dev/null ;;
    pacman) $SUDO pacman -S --needed --noconfirm "$@" </dev/null ;;
  esac
}

pkg_name() { # map a tool to this PM's package name (differences are the exception)
  # May return MORE than one package (see ncurses) — install_tool word-splits it
  # on purpose, so nothing here may contain a space inside a single package name.
  case "$1" in
    fd)          case "$PM" in apt|dnf) echo "fd-find" ;; *) echo "fd" ;; esac ;;
    # Arch ships GitHub's CLI as github-cli, not gh.
    gh)          case "$PM" in pacman) echo "github-cli" ;; *) echo "gh" ;; esac ;;
    # dnf: `7zip` is in RPM Fusion (nonfree) on Fedora, NOT in standard repos or
    # EPEL. Without RPM Fusion enabled, dnf install 7zip fails and falls through
    # to gh_release_install (sevenzip has no gh_release_repo entry, so it ends
    # up in MISSING with the hint "yazi archive previews only" — correct outcome).
    # apt keeps p7zip-full which on Debian 13+ pulls 7zip transitionally.
    sevenzip)    case "$PM" in apt) echo "p7zip-full" ;; *) echo "7zip" ;; esac ;;
    poppler)     case "$PM" in pacman) echo "poppler" ;; *) echo "poppler-utils" ;; esac ;;
    imagemagick) case "$PM" in dnf) echo "ImageMagick" ;; *) echo "imagemagick" ;; esac ;;
    shellcheck)  case "$PM" in dnf) echo "ShellCheck" ;; *) echo "shellcheck" ;; esac ;;
    # Fedora names its packaged build ffmpeg-free, not ffmpeg.
    ffmpeg)      case "$PM" in dnf) echo "ffmpeg-free" ;; *) echo "ffmpeg" ;; esac ;;
    # apt needs ncurses-bin for tic and ncurses-term for tmux's default tmux-256color entry.
    ncurses)     case "$PM" in apt) echo "ncurses-bin ncurses-term" ;; *) echo "ncurses" ;; esac ;;
    *)           echo "$1" ;;
  esac
}

# Binary aliases live in install.common.sh. ImageMagick 6 counts as installed,
# but yazi's HEIC/AVIF/JXL previews require magick, so report the limitation.
tool_note() {
  case "$1" in
    imagemagick)
      if ! command -v magick >/dev/null 2>&1 && command -v convert >/dev/null 2>&1; then
        printf ' (ImageMagick 6 — no magick binary; yazi HEIC/AVIF/JXL previews unavailable)'
      fi ;;
    *) : ;;
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
  dnf)
    # RHEL derivatives need EPEL for tools including stow. Fedora does not need it.
    # Match ID, not ID_LIKE, so derivatives still warn if EPEL installation fails.
    $SUDO dnf install -y epel-release >>"$LOG" 2>&1 </dev/null \
      || { grep -Eq '^ID="?fedora"?$' /etc/os-release 2>/dev/null \
           || echo "!! EPEL setup failed — EPEL packages may not install (see $LOG)" >&2; } ;;
  *)      : ;;  # pacman refreshes implicitly on install
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

# AUR builds run without sudo. Helpers escalate for the package installation step.
# Pre-answer yay's menus, since --noconfirm alone still prompts after interrupted runs.
# stdin from /dev/null turns unexpected prompts into failures instead of hidden hangs.
aur_install() {
  [ -n "$AUR" ] || return 1
  case "$AUR" in
    yay)  yay  -S --needed --noconfirm --removemake \
              --answerclean=None --answerdiff=None \
              --answeredit=None  --answerupgrade=None "$@" </dev/null ;;
    paru) paru -S --needed --noconfirm --removemake --skipreview "$@" </dev/null ;;
  esac
}

# ---------------------------------------------------------------------------
# 2b. GitHub-releases fallback (any distro)
# ---------------------------------------------------------------------------
# Use upstream releases for unpackaged tools and packages below min_version.
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
    worktrunk) echo "max-sixty/worktrunk" ;;
    shellcheck) echo "koalaman/shellcheck" ;;
    neovim)    echo "neovim/neovim" ;;
    fzf)       echo "junegunn/fzf" ;;
    atuin)     echo "atuinsh/atuin" ;;
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
  local tool="$1" repo urls url arch_pat tmp f b c rc=1
  local asset sums_url want root
  repo="$(gh_release_repo "$tool")" || return 1
  command -v curl >/dev/null 2>&1 || return 1

  case "$(uname -m)" in
    x86_64|amd64)  arch_pat='x86[_-]?64|amd64|x64' ;;
    aarch64|arm64) arch_pat='aarch64|arm64' ;;
    *)             return 1 ;;   # no prebuilt binaries for anything else
  esac

  # Track 403/429 responses separately so the final report explains API limits.
  local resp code body
  resp="$(gh_api_get "https://api.github.com/repos/$repo/releases/latest")" || return 1
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  case "$code" in
    200)     : ;;
    403|429) GH_RATE_LIMITED=1; return 1 ;;
    *)       return 1 ;;
  esac

  # Use grep because jq can be an installation target. Treat no matches as empty.
  urls="$(printf '%s' "$body" \
          | grep -o '"browser_download_url": *"[^"]*"' \
          | sed 's/.*"\(https[^"]*\)"/\1/')" || urls=""
  [ -n "$urls" ] || return 1

  # Select portable clients, excluding installers, metadata, Android, AppImages and server/updater helpers.
  _pick() {
    printf '%s\n' "$urls" \
      | grep -Ei 'linux' \
      | grep -Eiv '\.(deb|rpm|apk|msi|exe|pkg|sig|asc|pem|sha[0-9]*|sha[0-9]*sum|sbom|json|txt|appimage|zsync)$' \
      | grep -Eiv -- '-(server|update|updater)[-_.]' \
      | grep -Eiv 'android' \
      | grep -Ei "$arch_pat" \
      | grep -Ei "$1" \
      | head -1
  }
  # Prefer glibc, then static musl, then assets without a libc label.
  # Explicit target triples cover ARM assets. Treat the first missing match as empty.
  url="$(_pick 'unknown-linux-gnu')" || url=""
  [ -n "$url" ] || url="$(_pick 'gnu')"
  [ -n "$url" ] || url="$(_pick 'unknown-linux-musl')"
  [ -n "$url" ] || url="$(_pick '.')"
  [ -n "$url" ] || return 1
  asset="${url##*/}"

  # Find the checksum published alongside the asset we picked. _pick throws these
  # away on purpose — we never want to *install* a .sha256 — so search the raw
  # asset list instead: a per-asset sum first (neovim, cargo-dist projects), then
  # a release-wide manifest (fzf's fzf_<ver>_checksums.txt, SHA256SUMS, …).
  sums_url=""
  for c in "$url.sha256" "$url.sha256sum" "$url.sha256.txt"; do
    if printf '%s\n' "$urls" | grep -Fxq "$c"; then sums_url="$c"; break; fi
  done
  if [ -z "$sums_url" ]; then
    # Missing checksum manifests are allowed, but reported below.
    sums_url="$(printf '%s\n' "$urls" \
      | grep -Ei '(checksums?|sha256sums?|sha256\.sum)[^/]*$' \
      | grep -Eiv '\.(sig|asc|pem)$' \
      | head -1)" || sums_url=""
  fi

  tmp="$(mktemp -d)" || return 1
  if ! curl -fsSL -o "$tmp/asset" "$url"; then
    rm -rf "$tmp"
    return 1
  fi

  # Reject checksum mismatches. If verification is unavailable, install and report UNVERIFIED.
  if [ -z "$sums_url" ]; then
    UNVERIFIED+=("$tool — $repo publishes no checksum for $asset")
  elif ! command -v sha256sum >/dev/null 2>&1; then
    UNVERIFIED+=("$tool — sha256sum is not installed, could not check $asset")
  elif ! curl -fsSL -o "$tmp/sums" "$sums_url"; then
    UNVERIFIED+=("$tool — could not download ${sums_url##*/} for $asset")
  else
    # Two shapes in the wild: a bare hash on its own (per-asset .sha256 files) or
    # "<hash>  <filename>" lines covering the whole release.
    if [ "$(wc -w < "$tmp/sums")" -le 1 ]; then
      want="$(tr -d '[:space:]' < "$tmp/sums")"
    else
      # Match the exact filename field, stripping binary-mode markers and directory prefixes.
      want="$(awk -v a="$asset" \
        '{ n = $NF; sub(/^\*/, "", n); sub(/.*\//, "", n); if (n == a) { print $1; exit } }' \
        "$tmp/sums")"
    fi
    if [ -z "$want" ]; then
      UNVERIFIED+=("$tool — ${sums_url##*/} has no entry for $asset")
    else
      # Re-point the sum at our local filename so sha256sum -c does the compare
      # (and the hex parsing) rather than a hand-rolled string equality test.
      printf '%s  asset\n' "$want" > "$tmp/expect"
      if ! ( cd "$tmp" && sha256sum -c --status expect ); then
        echo "!! $tool: sha256 MISMATCH on $asset — refusing to install" >&2
        rm -rf "$tmp"
        return 1
      fi
    fi
  fi

  case "$url" in
    *.tar.gz|*.tgz) tar -xzf "$tmp/asset" -C "$tmp" 2>/dev/null ;;
    *.tar.xz)       tar -xJf "$tmp/asset" -C "$tmp" 2>/dev/null ;;
    *.tar.bz2)      tar -xjf "$tmp/asset" -C "$tmp" 2>/dev/null ;;
    *.zip)
      # Report a missing extractor instead of hiding the failure in redirected output.
      if ! command -v unzip >/dev/null 2>&1; then
        echo "!! $tool: cannot extract $asset — unzip is not installed" >&2
        rm -rf "$tmp"
        return 1
      fi
      unzip -oq "$tmp/asset" -d "$tmp" ;;
    *)              mv "$tmp/asset" "$tmp/$(bin_name "$tool")" ;;  # bare binary
  esac

  if [ "$tool" = neovim ]; then
    # Keep Neovim's whole tree, since bin/nvim locates its runtime relative to itself.
    f="$(find "$tmp" -type f -path '*/bin/nvim' -print -quit 2>/dev/null)" || f=""
    if [ -n "$f" ]; then
      root="$(dirname "$(dirname "$f")")"
      mkdir -p "$HOME/.local/opt"
      # Copy across filesystems before replacing the working editor. Rename within ~/.local/opt.
      # Clear stale staging to avoid nested copies. Report success only after linking completes.
      rm -rf "$HOME/.local/opt/nvim.new"
      if cp -r "$root" "$HOME/.local/opt/nvim.new" \
         && rm -rf "$HOME/.local/opt/nvim" \
         && mv "$HOME/.local/opt/nvim.new" "$HOME/.local/opt/nvim" \
         && ln -sfn "$HOME/.local/opt/nvim/bin/nvim" "$HOME/.local/bin/nvim"
      then
        rc=0
        rm -rf "$root"
      else
        echo "!! neovim: could not install into $HOME/.local/opt (out of space?)" >&2
        rm -rf "$HOME/.local/opt/nvim.new"
      fi
    fi
  else
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
# 2c. Minimum versions
# ---------------------------------------------------------------------------
# Minimum versions required to load these configurations: LazyVim needs Neovim 0.11.2,
# and .zshrc's fzf --zsh integration needs fzf 0.48. atuin/config.toml's daemon-fuzzy
# with autostart needs 18.24.6 (older builds reject the key or hang on shell exit).
min_version() {
  case "$1" in
    neovim) echo "0.11.2" ;;
    fzf)    echo "0.48.0" ;;
    atuin)  echo "18.24.6" ;;
    *)      : ;;
  esac
}

# First dotted number out of `<tool> --version`. Only ever called for tools that
# have a floor, so no assumption is made about tools that don't take --version.
tool_version() {
  local bin out
  bin="$(bin_name "$1")"
  command -v "$bin" >/dev/null 2>&1 || return 1
  out="$("$bin" --version 2>/dev/null | head -1)" || return 1
  # Treat an unparseable version as empty instead of triggering errexit.
  out="$(printf '%s\n' "$out" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)" || out=""
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# True when $1 >= $2, comparing dotted fields numerically. Not `sort -V`: that is
# a GNU extension whose collation of prerelease suffixes differs between busybox
# and coreutils, and the inputs here are plain x.y.z triples.
version_ge() {
  local i ai bi
  local -a a b
  IFS=. read -r -a a <<< "$1"
  IFS=. read -r -a b <<< "$2"
  for i in 0 1 2 3; do
    ai="${a[i]:-0}"; bi="${b[i]:-0}"
    ai="${ai%%[^0-9]*}"; bi="${bi%%[^0-9]*}"   # drop -rc1, +dfsg, etc.
    [ -n "$ai" ] || ai=0
    [ -n "$bi" ] || bi=0
    [ "$ai" -gt "$bi" ] && return 0
    [ "$ai" -lt "$bi" ] && return 1
  done
  return 0
}

# The question install_tool actually needs answered: is this tool present under a
# name we accept, AND new enough to be worth reporting as installed?
tool_ok() {
  local tool="$1" floor ver
  # Clear cached paths so newly installed releases take precedence over distro binaries.
  hash -r 2>/dev/null || true
  have_tool "$tool" || return 1
  floor="$(min_version "$tool")"
  [ -n "$floor" ] || return 0
  # An unparseable --version is not evidence of an old tool, so don't block on it.
  ver="$(tool_version "$tool")" || return 0
  version_ge "$ver" "$floor"
}

# ---------------------------------------------------------------------------
# 3. Best-effort install (repo → AUR → GitHub releases → reported as missing)
# ---------------------------------------------------------------------------
install_tool() {
  local tool="$1" pkg bin floor
  pkg="$(pkg_name "$tool")"
  bin="$(bin_name "$tool")"
  floor="$(min_version "$tool")"
  printf '   %-13s ' "$tool"

  if tool_ok "$tool"; then
    echo "✓ already installed$(tool_note "$tool")"
    return 0
  fi

  # Skip package-manager retries for installed versions below the required minimum.
  if [ -n "$floor" ] && command -v "$bin" >/dev/null 2>&1; then
    if { echo "### GitHub releases: $tool ($(tool_version "$tool" || echo '?') < $floor)"
         gh_release_install "$tool"; } >>"$LOG" 2>&1 && tool_ok "$tool"; then
      echo "✓ $(gh_release_repo "$tool") $(tool_version "$tool") (GitHub release → ~/.local/bin; packaged build too old)"
    else
      echo "✗ $(tool_version "$tool" || echo 'installed version') is older than the required $floor"
      MISSING+=("$tool")
      # Record unusable versions as fatal, since verify_install only detects binary presence.
      FAILED_PKGS+=" $tool"
    fi
    return 0
  fi

  # Require a usable binary after each install. Split pkg_name's multi-package results deliberately.
  # shellcheck disable=SC2086  # deliberate word splitting of the package list
  if { echo "### $PM: $tool ($pkg)"; pm_install $pkg; } >>"$LOG" 2>&1 && tool_ok "$tool"; then
    echo "✓ $pkg$(tool_note "$tool")"
  elif { echo "### AUR: $tool ($(aur_name "$tool"))"; aur_install "$(aur_name "$tool")"; } >>"$LOG" 2>&1 && tool_ok "$tool"; then
    echo "✓ $(aur_name "$tool") (AUR)"
  elif { echo "### GitHub releases: $tool"; gh_release_install "$tool"; } >>"$LOG" 2>&1 && tool_ok "$tool"; then
    echo "✓ $(gh_release_repo "$tool") (GitHub release → ~/.local/bin)"
  else
    echo "✗ not available"
    # Let verify_install assign severity. Optional missing tools must not become fatal here.
    # Ghostty and font failures need separate accounting because its binary loops omit them.
    MISSING+=("$tool")
  fi
}

# Install git, curl and unzip before tools that need downloads or extraction.
# zsh is required. Install both clipboard providers to cover Wayland and X11.
# The last four tools provide yazi previews.
echo "==> Installing tools (best-effort; details in $LOG)"
for tool in \
  git curl unzip zsh tmux stow neovim ripgrep fzf zoxide bat fd \
  gh lazygit git-delta starship atuin yazi carapace sesh herdr worktrunk \
  mise jq shellcheck ncurses fontconfig wl-clipboard xclip \
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
  # This fallback has no checksum step. Record it as UNVERIFIED only after success.
  if curl -fsSL https://mise.run | sh >>"$LOG" 2>&1; then
    # Remove mise entirely rather than leaving an empty array element.
    _kept=()
    for _m in ${MISSING[@]+"${MISSING[@]}"}; do
      [ "$_m" = mise ] || _kept+=("$_m")
    done
    MISSING=(${_kept[@]+"${_kept[@]}"})
    unset _kept _m
    UNVERIFIED+=("mise — installed via curl https://mise.run | sh (no checksum; convert to gh_release_install to verify)")
    echo "   ✓ mise (mise.run → ~/.local/bin)"
  else
    echo "   ✗ mise — see $LOG"
  fi
fi

# ---------------------------------------------------------------------------
# 5. Decide about the login shell (the switch itself happens at the very end)
# ---------------------------------------------------------------------------
# Decide whether to change the login shell now, but switch only after successful setup.
ZSH_PATH=""
CURRENT_SHELL=""
if command -v zsh >/dev/null 2>&1; then
  ZSH_PATH="$(command -v zsh)"
  # Missing getent or passwd entries leave the shell unknown instead of aborting setup.
  CURRENT_SHELL="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)" || CURRENT_SHELL=""
  if [ "$CURRENT_SHELL" = "$ZSH_PATH" ]; then
    echo "==> Login shell already zsh"
    ZSH_PATH=""   # nothing for step 10 to do
  else
    NEXT_STEP_FIRST="Log out and back in — the login-shell change only applies to a new login."
  fi
fi

# ---------------------------------------------------------------------------
# 6. ghostty — official on some PMs, community/snap on others
# ---------------------------------------------------------------------------
# (https://ghostty.org/docs/install/binary#linux)
# Containers (Docker: /.dockerenv, Podman: /run/.containerenv) have no display:
# the host terminal renders ghostty and the font, so steps 6 and 7 skip them.
IN_CONTAINER=""
if [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then IN_CONTAINER=1; fi
echo "==> Installing ghostty"
if [ -z "$IN_CONTAINER" ] && ! command -v ghostty >/dev/null 2>&1; then
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
if [ -n "$IN_CONTAINER" ]; then
  echo "   - skipped in a container"
elif command -v ghostty >/dev/null 2>&1; then
  echo "   ✓ ghostty"
else
  # Record the failure because verify_install does not test Ghostty's binary.
  FAILED_PKGS+=" ghostty"
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
# Use Arch's package or download the release zip into ~/.local/share/fonts for theme glyphs.
echo "==> Installing JetBrainsMono Nerd Font"
if [ -n "$IN_CONTAINER" ]; then
  echo "   - skipped in a container"
elif fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
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
    # This latest-release download skips checksum verification, so report it explicitly.
    UNVERIFIED+=("JetBrainsMono Nerd Font — ryanoasis/nerd-fonts publishes SHA256SUMS but this download uses the /releases/latest/download/ redirect without a checksum step")
    echo "   ✓ installed to $_fontdir"
  else
    rm -f "$_fontdir/JetBrainsMono.zip"
    # Record the failure because fonts have no binary for verify_install to detect.
    FAILED_PKGS+=" font-jetbrains-mono-nerd-font"
    echo "   ✗ download failed — see $LOG"
  fi
else
  FAILED_PKGS+=" font-jetbrains-mono-nerd-font"
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
    # yazi-build replaces the retired split crates. --force overwrites their installed binaries.
    yazi)      echo "cargo install --force yazi-build   (or GitHub releases)" ;;
    sesh)      echo "mise use -g go@latest && go install github.com/joshmedeski/sesh/v2@latest" ;;
    carapace)  echo "GitHub releases: https://github.com/carapace-sh/carapace-bin/releases" ;;
    herdr)     echo "Herdr agent workspaces — https://github.com/herdrdev/herdr/releases" ;;
    jq)        echo "JSON processor — GitHub releases: jqlang/jq" ;;
    worktrunk) echo "Git worktrees — https://worktrunk.dev/" ;;
    lazygit)   echo "go install github.com/jesseduffield/lazygit@latest   (or GitHub releases)" ;;
    git-delta) echo "cargo install git-delta   (or GitHub releases: dandavison/delta)" ;;
    gh)        echo "GitHub's repo: https://github.com/cli/cli/blob/trunk/docs/install_linux.md" ;;
    neovim)    echo "REQUIRED >= 0.11.2 by nvim/lazy-lock.json — GitHub releases (neovim/neovim)" ;;
    # Same story: .zshrc sources `fzf --zsh` (0.48+) and sets --color=selected-bg
    # (0.42+); Ubuntu 22.04's 0.29 makes every fzf call in the shell fail.
    fzf)       echo "REQUIRED >= 0.48 by .zshrc's 'fzf --zsh' — GitHub releases: junegunn/fzf" ;;
    zsh)       echo "REQUIRED — none of these dotfiles load without it" ;;
    # RHEL derivatives need EPEL to install stow.
    stow)      echo "REQUIRED — nothing is symlinked without it. RHEL/Rocky/Alma: sudo dnf install epel-release && sudo dnf install stow" ;;
    mise)      echo "curl https://mise.run | sh" ;;
    sevenzip)  echo "yazi archive previews only" ;;
    poppler)   echo "yazi PDF previews only" ;;
    imagemagick) echo "yazi HEIC/AVIF/JXL previews only" ;;
    ffmpeg)    echo "yazi video previews only" ;;
    # Not an nvim linter: no lang.sh extra is enabled in nvim/lazyvim.json and
    # nothing under nvim/lua/ references it. It is used directly on these install
    # scripts, and check.sh runs it over them at severity >= warning.
    shellcheck) echo "used to lint these install scripts (and by check.sh) — not needed at runtime" ;;
    # Wayland and X11 halves of the same job. One of the two is enough; which one
    # depends on the session, so neither is individually required.
    wl-clipboard) echo "clipboard for tmux-yank + nvim's \"+ yanks (Wayland; xclip covers X11)" ;;
    xclip)     echo "clipboard for tmux-yank + nvim's \"+ yanks (X11; wl-clipboard covers Wayland)" ;;
    *)         echo "install manually" ;;
  esac
}

# Printed before the manual list, because it changes how to read it: these tools
# may be perfectly installable, just not in this hour.
if [ "$GH_RATE_LIMITED" -eq 1 ]; then
  echo ""
  echo "!! GitHub's API rate-limited us, so the release fallback could not run for"
  echo "   some tools — anything below may well be installable, just not right now."
  echo "   Either wait an hour and re-run, or raise the limit from 60/hour to 5000:"
  echo "     gh auth login          # the script picks up 'gh auth token'"
  echo "     GITHUB_TOKEN=… ./install.linux.sh"
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  echo ""
  echo "==> Install these manually (no repo provided them):"
  printf '%s\n' "${MISSING[@]}" | awk 'NF && !seen[$0]++' | while read -r t; do
    printf '   - %-12s %s\n' "$t" "$(hint "$t")"
  done
fi

# Show unverified downloads on the terminal. Mismatches are rejected and reported as failures instead.
if [ ${#UNVERIFIED[@]} -gt 0 ]; then
  echo ""
  echo "!! Installed WITHOUT checksum verification:"
  printf '   - %s\n' "${UNVERIFIED[@]}"
fi

# ---------------------------------------------------------------------------
# 8b. Optional per-machine install steps
# ---------------------------------------------------------------------------
# Optional machine-specific steps live in the ignored install.local.sh.
if [ -f "$DOTFILES/install.local.sh" ]; then
  echo ""
  echo "==> Running install.local.sh (machine-specific)"
  # shellcheck source=/dev/null
  # Continue to shared steps and verification even if local installation fails.
  source "$DOTFILES/install.local.sh" || true
fi

# ---------------------------------------------------------------------------
# 9. Shared tail + verification — install.common.sh (also used by install.sh)
# ---------------------------------------------------------------------------
# NEXT_STEP_FIRST was set back in step 5, before this call, because
# finish_install is what prints the closing "Next:" list.
INSTALL_RC=0
finish_install || INSTALL_RC=1

# ---------------------------------------------------------------------------
# 10. Make zsh the login shell — deliberately the LAST thing this script does
# ---------------------------------------------------------------------------
# Switch only after successful verification so the next login has working zsh configuration.
if [ -n "$ZSH_PATH" ] && [ "$INSTALL_RC" -eq 0 ]; then
  # chsh only accepts shells listed in /etc/shells.
  # Failing to append here is not fatal (chsh below reports it), so never let
  # a read-only /etc/shells or a denied sudo take the whole script down.
  if ! grep -qxF "$ZSH_PATH" /etc/shells 2>/dev/null; then
    echo "$ZSH_PATH" | $SUDO tee -a /etc/shells >/dev/null 2>&1 || true
  fi
  echo ""
  if [ -t 0 ]; then
    printf '==> Change login shell from %s to %s? [Y/n] ' "${CURRENT_SHELL:-unknown}" "$ZSH_PATH"
    # Treat EOF as declining the shell change, not an installation failure.
    read -r _reply || _reply=n
    case "${_reply:-y}" in
      [Nn]*) echo "   skipped — run 'chsh -s $ZSH_PATH' when ready" ;;
      *)     chsh -s "$ZSH_PATH" && echo "   ✓ login shell set (takes effect on next login)" \
               || echo "   ✗ chsh failed — run 'chsh -s $ZSH_PATH' manually" ;;
    esac
  else
    echo "==> Non-interactive: login shell left as ${CURRENT_SHELL:-unknown}"
    echo "   run: chsh -s $ZSH_PATH"
  fi
elif [ -n "$ZSH_PATH" ]; then
  # NEXT_STEP_FIRST already told them to log out and back in — it is printed from
  # inside finish_install, before we know how this turned out — so say plainly
  # that it no longer applies rather than leaving two contradictory messages.
  echo ""
  echo "!! Login shell left as ${CURRENT_SHELL:-unknown}: the install is incomplete, and" >&2
  echo "   switching to zsh now would just hand you a shell with no config to load." >&2
  echo "   Ignore the log-out-and-back-in step above. Fix the ✗ lines, re-run this" >&2
  echo "   script, or set the shell yourself once it passes:" >&2
  echo "     chsh -s $ZSH_PATH" >&2
fi

exit "$INSTALL_RC"
