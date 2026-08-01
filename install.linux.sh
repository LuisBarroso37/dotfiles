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
# 64-bit only — x86_64 and aarch64. Raspbian was listed on the apt line until it
# was pointed out that a 32-bit userland (armv7l/armhf) gets no GitHub-release
# fallback whatsoever: gh_release_install returns 1 for every arch that isn't
# x86_64 or aarch64, and eight of the tools below are in no apt repo at all —
# herdr among them, which .zshrc hard-depends on. 64-bit Raspberry Pi OS is
# Debian and takes the apt path unchanged; the 32-bit image is not supported.
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
#      and no atuin either, and Fedora additionally lacks lazygit/starship, none
#      of which have an AUR to fall back on. The same fallback also replaces a
#      packaged tool that is too OLD to work with this repo's configs (neovim,
#      fzf — see min_version), because "installed" and "usable" are not the same
#      claim. Downloads are sha256-verified whenever upstream publishes a sum.
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

MISSING=()     # tools no repo could provide → reported at the end with a recipe
UNVERIFIED=()  # GitHub-release downloads no upstream checksum covered → also reported

# GitHub allows 60 API requests/hour per unauthenticated IP, and the release
# fallback spends one per unpackaged tool — so a Debian or Fedora run costs ~8,
# and a few re-runs (or a shared/NAT'd address) exhausts it. A token lifts the
# ceiling to 5000, so use one if the environment or an authenticated gh has it.
GH_API_AUTH=()
_gh_tok="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
if [ -z "$_gh_tok" ] && command -v gh >/dev/null 2>&1; then
  _gh_tok="$(gh auth token 2>/dev/null || true)"
fi
[ -n "$_gh_tok" ] && GH_API_AUTH=(-H "Authorization: Bearer $_gh_tok")
unset _gh_tok
GH_RATE_LIMITED=0   # set when the API refuses us, so the report can say so

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
  # May return MORE than one package (see ncurses) — install_tool word-splits it
  # on purpose, so nothing here may contain a space inside a single package name.
  case "$1" in
    fd)          case "$PM" in apt|dnf) echo "fd-find" ;; *) echo "fd" ;; esac ;;
    # Arch ships GitHub's CLI as github-cli, not gh.
    gh)          case "$PM" in pacman) echo "github-cli" ;; *) echo "gh" ;; esac ;;
    # dnf takes the same 7zip package as Arch, NOT p7zip: Fedora's p7zip only
    # ever installed /usr/bin/7za, never the 7z that yazi (and bin_name) look
    # for, and it is dropped from the distro entirely in f44+. apt keeps
    # p7zip-full — transitional on Debian 13, where it pulls 7zip — because on
    # every apt release it ends up providing /usr/bin/7z.
    sevenzip)    case "$PM" in apt) echo "p7zip-full" ;; *) echo "7zip" ;; esac ;;
    poppler)     case "$PM" in pacman) echo "poppler" ;; *) echo "poppler-utils" ;; esac ;;
    imagemagick) case "$PM" in dnf) echo "ImageMagick" ;; *) echo "imagemagick" ;; esac ;;
    shellcheck)  case "$PM" in dnf) echo "ShellCheck" ;; *) echo "shellcheck" ;; esac ;;
    # Fedora has no package called ffmpeg at all: it ships ffmpeg-free, the
    # patent-clean rebuild, which does NOT declare `Provides: ffmpeg`. Asking dnf
    # for "ffmpeg" therefore failed outright and every Fedora box came up with
    # yazi unable to preview video.
    ffmpeg)      case "$PM" in dnf) echo "ffmpeg-free" ;; *) echo "ffmpeg" ;; esac ;;
    # ncurses-bin supplies tic, used to compile terminfo/ below. ncurses-term is
    # the second half and just as load-bearing: it carries the tmux-256color
    # entry that tmux.conf sets as default-terminal, and without it everything
    # started inside tmux fails its terminal lookup — nvim greets you with
    # "E558: Terminal entry not found in terminfo". Only apt splits the two.
    ncurses)     case "$PM" in apt) echo "ncurses-bin ncurses-term" ;; *) echo "ncurses" ;; esac ;;
    *)           echo "$1" ;;
  esac
}

# Linux-only extension of install.common.sh's bin_name. wl-clipboard installs
# wl-copy/wl-paste rather than anything called wl-clipboard, and both clipboard
# providers are Linux-only concerns (macOS has pbcopy built in), so they have no
# business in the mapping install.sh shares.
tool_bin() {
  case "$1" in
    wl-clipboard) echo "wl-copy" ;;
    *)            bin_name "$1" ;;
  esac
}

# Binaries that ALSO count as "this tool is present", because the package really
# did install the tool, just under another name:
#   fd, bat      Debian renames the executables (fdfind, batcat) to avoid
#                clashing with fdclone and bacula. Step 4 symlinks them back, but
#                that runs after the install loop, so without this the loop would
#                call both tools missing and fetch a second copy from GitHub.
#   imagemagick  apt's `imagemagick` is still ImageMagick 6 on Debian ≤ 12 and
#                Ubuntu ≤ 24.04, and IM6 has NO `magick` binary whatsoever — only
#                convert-im6.q16 and friends, reachable as `convert`. Testing for
#                `magick` alone meant apt exited 0 while every check here still
#                considered the tool absent. See tool_note: convert is accepted as
#                evidence the package landed, but it is NOT treated as equivalent.
alt_bins() {
  case "$1" in
    fd)          echo "fdfind" ;;
    bat)         echo "batcat" ;;
    imagemagick) echo "convert" ;;
    *)           : ;;
  esac
}

# A caveat appended to the ✓ line when what we found is not the whole tool. yazi's
# HEIC/AVIF/JXL preview command is literally `magick`, so an IM6 machine must be
# told the previews are gone rather than shown a bare ✓ implying they work.
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
    # dnf refreshes implicitly on install, but RHEL/Rocky/AlmaLinux need EPEL
    # enabled before any of it is reachable: stow, fzf, bat, fd, ripgrep, zoxide
    # and atuin are ALL EPEL-only there, so without this even the stow step —
    # the one thing this whole script exists to do — was unobtainable. Fedora
    # has no epel-release package (it doesn't need one), so a failure here is
    # the normal case on Fedora and is deliberately ignored.
    $SUDO dnf install -y epel-release >>"$LOG" 2>&1 </dev/null || true ;;
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

# makepkg refuses to run as root, so AUR installs never take $SUDO — the helper
# escalates internally for the pacman step.
#
# --noconfirm alone is NOT enough to make yay non-interactive: when a previous
# run left files in /tmp/yay it still opens the "Packages to cleanBuild?" and
# "Diffs to show?" menus, which block forever behind the log redirect with no
# visible prompt. The --answer* flags pre-answer all four menus; </dev/null
# below is the backstop, turning any prompt we haven't anticipated into an
# immediate EOF failure rather than a hang.
#
# Only the two helpers detected above are handled, and that is exhaustive: $AUR
# is set to exactly "", "yay" or "paru" and the empty case returns before the
# case statement. A generic `*)` arm here was unreachable code pretending to
# support helpers this script never selects.
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
# The AUR covers sesh/carapace/herdr on Arch, but nothing equivalent exists on
# Debian or Fedora, where yazi, sesh, carapace, herdr and atuin — plus lazygit and
# starship on Fedora — are in no repo at all. All of them publish static Linux
# binaries on GitHub, so pull those into ~/.local/bin as a last resort before
# giving up on a tool. neovim and fzf are here for the other reason: they ARE
# packaged everywhere, just at versions this repo's configs cannot use (see
# min_version), so the release becomes the source when the repo's copy is too old.
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
    neovim)    echo "neovim/neovim" ;;
    fzf)       echo "junegunn/fzf" ;;
    atuin)     echo "atuinsh/atuin" ;;
    *)         return 1 ;;
  esac
}

# Binaries to lift out of the archive. Only tools shipping more than one (or
# under a name that isn't tool_bin) need an entry.
gh_release_bins() {
  case "$1" in
    yazi) echo "yazi ya" ;;   # ya is the plugin/package manager half
    *)    tool_bin "$1" ;;
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

  # Status captured alongside the body in one request. A 403/429 here is rate
  # limiting, not a missing tool, and -f collapsed the two into the same silent
  # failure — so an exhausted quota reported eight tools as unavailable and sent
  # you hand-installing things that would have worked an hour later. Hit while
  # testing this script in containers: 60 requests/hour goes quickly when each
  # run costs one per unpackaged tool.
  local resp code body
  resp="$(curl -sSL -w '\n%{http_code}' \
            ${GH_API_AUTH[@]+"${GH_API_AUTH[@]}"} \
            "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)" || return 1
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  case "$code" in
    200)     : ;;
    403|429) GH_RATE_LIMITED=1; return 1 ;;
    *)       return 1 ;;
  esac

  # Parsed with grep rather than jq: jq is itself one of the tools this may be
  # asked to install, so it cannot be a dependency of the installer.
  urls="$(printf '%s' "$body" \
          | grep -o '"browser_download_url": *"[^"]*"' \
          | sed 's/.*"\(https[^"]*\)"/\1/')"
  [ -n "$urls" ] || return 1

  # Drop distro packages, installers, checksums and signatures — we want the
  # portable archive or the bare binary, not something needing a package manager.
  #
  # The three extra exclusions each cost a real, silently-wrong install:
  #   android    zoxide publishes aarch64-linux-android, and it sorts FIRST in
  #              the release list. On aarch64 the arch filter matched it and the
  #              catch-all pick below took it — an Android NDK binary installed
  #              into ~/.local/bin on a Raspberry Pi.
  #   appimage   neovim ships nvim-linux-x86_64.appimage next to the tarball.
  #              Nothing here can unpack an AppImage (and it needs FUSE at
  #              runtime), so it must never win over the tarball.
  #   -server/   atuin's release carries atuin-server-* (the sync server, not the
  #   -update    shell client) and cargo-dist's *-update self-updater helper.
  #              Both match every other filter, and one of them sorts first.
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
  # Prefer glibc builds — all three supported distros are glibc — then musl,
  # since some projects (starship for a long while) ship Linux musl builds
  # exclusively and a static musl binary runs fine on glibc. The bare `.` pick is
  # the last resort, for projects that encode no libc at all in the asset name
  # (herdr-linux-x86_64, sesh_Linux_x86_64, nvim-linux-x86_64.tar.gz).
  #
  # The explicit unknown-linux-* steps exist because of aarch64: no aarch64 asset
  # anywhere contains "gnu" as a bare word for some projects, so `_pick gnu` came
  # back empty and control fell straight through to the catch-all — which is how
  # zoxide's aarch64-linux-android asset got picked on ARM.
  url="$(_pick 'unknown-linux-gnu')"
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
    sums_url="$(printf '%s\n' "$urls" \
      | grep -Ei '(checksums?|sha256sums?|sha256\.sum)[^/]*$' \
      | grep -Eiv '\.(sig|asc|pem)$' \
      | head -1)"
  fi

  tmp="$(mktemp -d)" || return 1
  if ! curl -fsSL -o "$tmp/asset" "$url"; then
    rm -rf "$tmp"
    return 1
  fi

  # Nothing verified these downloads before: whatever came back from the network
  # was installed into ~/.local/bin as an executable and, for herdr and carapace,
  # sourced into every interactive shell. Where upstream publishes a sum we now
  # insist on it and refuse to install on a mismatch. Where it publishes none
  # (herdr, sesh) we install anyway but record it in $UNVERIFIED, which is
  # reported at the end — refusing outright would leave .zshrc's hard dependency
  # on herdr unmet, which is a worse outcome than a warned-about download.
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
      # Matched on the filename FIELD, not as a substring of the line: a manifest
      # listing nvim-linux-x86_64.tar.gz.sha256sum above the tarball itself would
      # otherwise return the hash of the wrong file and fail a download that was
      # perfectly good. The subs strip sha256sum's binary-mode "*" marker and any
      # leading path.
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
      # yazi's release is the only .zip in the set, and this used to be a plain
      # `unzip … 2>/dev/null` with no guard: on a minimal image, where unzip is
      # itself one of the tools being installed, the command did not exist, the
      # error went to /dev/null and yazi was reported unavailable even though the
      # download had succeeded. unzip now comes earlier in the install loop, and
      # this says so out loud if it somehow still isn't there.
      if ! command -v unzip >/dev/null 2>&1; then
        echo "!! $tool: cannot extract $asset — unzip is not installed" >&2
        rm -rf "$tmp"
        return 1
      fi
      unzip -oq "$tmp/asset" -d "$tmp" ;;
    *)              mv "$tmp/asset" "$tmp/$(tool_bin "$tool")" ;;  # bare binary
  esac

  if [ "$tool" = neovim ]; then
    # neovim is the one release here that is NOT a self-contained binary: bin/nvim
    # locates its runtime relative to its own path ($prefix/share/nvim/runtime),
    # so lifting just the executable out of the tarball produces an nvim that
    # starts and then fails on everything builtin. Keep the extracted tree whole
    # under ~/.local/opt and put a symlink on PATH.
    f="$(find "$tmp" -type f -path '*/bin/nvim' -print -quit 2>/dev/null)"
    if [ -n "$f" ]; then
      root="$(dirname "$(dirname "$f")")"
      mkdir -p "$HOME/.local/opt"
      rm -rf "$HOME/.local/opt/nvim"
      mv "$root" "$HOME/.local/opt/nvim"
      ln -sfn "$HOME/.local/opt/nvim/bin/nvim" "$HOME/.local/bin/nvim"
      rc=0
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
# Some tools are packaged everywhere and still unusable, because this repo's
# configs need a version newer than the distro's. Existence checks alone printed
# a ✓ for those, they never reached $MISSING, and the "packaged version too old"
# hint at the bottom of this script was therefore dead text nobody could trigger.
#
# A floor here means: below this version the tool does not merely lose a feature,
# the configuration in this repo fails to load.
#   neovim  nvim/lazy-lock.json pins LazyVim at a commit that requires 0.11.2.
#           Debian 12 ships 0.7.2, Ubuntu 22.04 0.6.1, Debian 13 0.10.4 and even
#           Ubuntu 24.04 only 0.9.5 — every one of them below the floor, so the
#           editor config cannot be loaded at all.
#   fzf     zsh/.zshrc sources `fzf --zsh`, which only exists from 0.48, and sets
#           --color=selected-bg, which needs 0.42. Ubuntu 22.04 ships 0.29, where
#           the `source <(fzf --zsh)` line makes EVERY fzf call fail.
min_version() {
  case "$1" in
    neovim) echo "0.11.2" ;;
    fzf)    echo "0.48.0" ;;
    *)      : ;;
  esac
}

# First dotted number out of `<tool> --version`. Only ever called for tools that
# have a floor, so no assumption is made about tools that don't take --version.
tool_version() {
  local bin out
  bin="$(tool_bin "$1")"
  command -v "$bin" >/dev/null 2>&1 || return 1
  out="$("$bin" --version 2>/dev/null | head -1)" || return 1
  out="$(printf '%s\n' "$out" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
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
  local tool="$1" bin alt floor ver
  # bash caches command→path lookups, and this is called immediately after a
  # release install drops a NEWER copy into ~/.local/bin. Without clearing the
  # table, `command -v nvim` and `nvim --version` keep answering for the /usr/bin
  # build we just replaced, and the version floor below never lets go.
  hash -r 2>/dev/null || true
  bin="$(tool_bin "$tool")"
  if ! command -v "$bin" >/dev/null 2>&1; then
    for alt in $(alt_bins "$tool"); do
      command -v "$alt" >/dev/null 2>&1 && return 0
    done
    return 1
  fi
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
  bin="$(tool_bin "$tool")"
  floor="$(min_version "$tool")"
  printf '   %-13s ' "$tool"

  if tool_ok "$tool"; then
    echo "✓ already installed$(tool_note "$tool")"
    return 0
  fi

  # A tool that is installed but BELOW its floor must skip the package manager:
  # the repo has nothing newer, `apt-get install` would report "already the newest
  # version", exit 0, and we would print a ✓ for the very binary we just rejected.
  # Go straight to the upstream release instead.
  if [ -n "$floor" ] && command -v "$bin" >/dev/null 2>&1; then
    if { echo "### GitHub releases: $tool ($(tool_version "$tool" || echo '?') < $floor)"
         gh_release_install "$tool"; } >>"$LOG" 2>&1 && tool_ok "$tool"; then
      echo "✓ $(gh_release_repo "$tool") $(tool_version "$tool") (GitHub release → ~/.local/bin; packaged build too old)"
    else
      echo "✗ $(tool_version "$tool" || echo 'installed version') is older than the required $floor"
      MISSING+=("$tool")
    fi
    return 0
  fi

  # Every arm re-checks with tool_ok rather than trusting the package manager's
  # exit status: apt happily exits 0 for a package that installs no binary we can
  # find (see alt_bins on ImageMagick 6), and pm_install cannot know about a
  # version floor. $pkg is deliberately unquoted — pkg_name may return two
  # packages (ncurses on apt) and both have to reach the PM as separate arguments.
  # shellcheck disable=SC2086  # deliberate word splitting of the package list
  if { echo "### $PM: $tool ($pkg)"; pm_install $pkg; } >>"$LOG" 2>&1 && tool_ok "$tool"; then
    echo "✓ $pkg$(tool_note "$tool")"
  elif { echo "### AUR: $tool ($(aur_name "$tool"))"; aur_install "$(aur_name "$tool")"; } >>"$LOG" 2>&1 && tool_ok "$tool"; then
    echo "✓ $(aur_name "$tool") (AUR)"
  elif { echo "### GitHub releases: $tool"; gh_release_install "$tool"; } >>"$LOG" 2>&1 && tool_ok "$tool"; then
    echo "✓ $(gh_release_repo "$tool") (GitHub release → ~/.local/bin)"
  else
    echo "✗ not available"
    MISSING+=("$tool")
  fi
}

# ORDER MATTERS in the first line: git, curl and unzip are what the later entries
# are installed WITH (submodules, TPM clone, the mise installer, and every archive
# the GitHub-release fallback unpacks). unzip used to sit eight entries after yazi,
# whose release asset is the only .zip in the set — so on a minimal image yazi's
# download succeeded, the extraction found no unzip, its error went to /dev/null
# and yazi was reported unavailable for no visible reason.
#
# zsh is NOT optional and was the omission that made a fresh install look like it
# had done nothing: every config here is zsh-side, so without it (and without the
# chsh in step 10) you land back in bash and none of this is ever loaded.
# jq and herdr are likewise load-bearing — .zshrc's wth/wthr/_herdr_ws_at pipe
# `herdr workspace list` through jq.
# wl-clipboard and xclip are the Linux side of something macOS gets for free via
# pbcopy, which is exactly why their absence went unnoticed: tmux-yank
# (tmux.conf) and the yank-to-"+ keymaps (nvim/lua/config/keymaps.lua) both need
# an external clipboard provider, and cheatsheet.md documents them as working.
# Both are packaged on all three PMs; installing both covers Wayland and X11
# without having to guess which session type this machine boots into.
# The last four are yazi's preview backends (video / archive / PDF / HEIC-JXL),
# and were only in install.sh — every Linux rebuild came up without previews.
echo "==> Installing tools (best-effort; details in $LOG)"
for tool in \
  git curl unzip zsh tmux stow neovim ripgrep fzf zoxide bat fd \
  gh lazygit git-delta starship atuin yazi carapace sesh herdr \
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
  if curl -fsSL https://mise.run | sh >>"$LOG" 2>&1; then
    # Rebuilt element by element, because the old MISSING=("${MISSING[@]/mise}")
    # did NOT remove anything: ${arr[@]/pat} is a substitution, so it replaced
    # "mise" with the empty string and left the element in place. The array kept
    # its length, ${#MISSING[@]} stayed ≥ 1, and the "install these manually"
    # header printed with nothing under it — the awk NF filter that renders the
    # list swallowed the now-blank entry.
    _kept=()
    for _m in ${MISSING[@]+"${MISSING[@]}"}; do
      [ "$_m" = mise ] || _kept+=("$_m")
    done
    MISSING=(${_kept[@]+"${_kept[@]}"})
    unset _kept _m
    echo "   ✓ mise (mise.run → ~/.local/bin)"
  else
    echo "   ✗ mise — see $LOG"
  fi
fi

# ---------------------------------------------------------------------------
# 5. Decide about the login shell (the switch itself happens at the very end)
# ---------------------------------------------------------------------------
# Making zsh the login shell is the step whose absence caused "I installed it and
# nothing happened": the repo stows .zshrc/.zshenv/.zprofile, but a distro default
# account is on bash, so none of them are ever read.
#
# Only the DECISION is made here, because the switch has to come after the stow
# step — see step 10. All this does is work out whether there is anything to do,
# and set NEXT_STEP_FIRST so the closing message mentions the re-login.
ZSH_PATH=""
CURRENT_SHELL=""
if command -v zsh >/dev/null 2>&1; then
  ZSH_PATH="$(command -v zsh)"
  CURRENT_SHELL="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
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
    # Upstream folded the split crates into one: yazi-fm/yazi-cli stopped at
    # 26.5.6 while yazi-build is on 26.5.9, so the old two-crate recipe now
    # installs a stale yazi. --force because it overwrites whatever the earlier
    # split-crate recipe left in ~/.cargo/bin.
    yazi)      echo "cargo install --force yazi-build   (or GitHub releases)" ;;
    sesh)      echo "mise use -g go@latest && go install github.com/joshmedeski/sesh/v2@latest" ;;
    carapace)  echo "GitHub releases: https://github.com/carapace-sh/carapace-bin/releases" ;;
    herdr)     echo "REQUIRED by .zshrc's wth/wthr — https://github.com/herdrdev/herdr/releases" ;;
    jq)        echo "REQUIRED by .zshrc's wth/wthr — GitHub releases: jqlang/jq" ;;
    lazygit)   echo "go install github.com/jesseduffield/lazygit@latest   (or GitHub releases)" ;;
    git-delta) echo "cargo install git-delta   (or GitHub releases: dandavison/delta)" ;;
    gh)        echo "GitHub's repo: https://github.com/cli/cli/blob/trunk/docs/install_linux.md" ;;
    # Reachable at last: install_tool now checks nvim's version, not just its
    # existence, so a distro build below the LazyVim floor lands here instead of
    # printing a ✓. Every apt release ships one (Debian 12: 0.7.2, Ubuntu 24.04:
    # 0.9.5), and nvim/ cannot load on any of them.
    neovim)    echo "REQUIRED >= 0.11.2 by nvim/lazy-lock.json — GitHub releases (neovim/neovim)" ;;
    # Same story: .zshrc sources `fzf --zsh` (0.48+) and sets --color=selected-bg
    # (0.42+); Ubuntu 22.04's 0.29 makes every fzf call in the shell fail.
    fzf)       echo "REQUIRED >= 0.48 by .zshrc's 'fzf --zsh' — GitHub releases: junegunn/fzf" ;;
    zsh)       echo "REQUIRED — none of these dotfiles load without it" ;;
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

# Reported on the terminal, not just in $LOG: an unverified download is a thing
# the person running this is entitled to know about, and every one of these ends
# up as an executable on PATH (herdr and carapace are additionally sourced by
# every interactive shell). A mismatching checksum is not listed here — that
# refuses to install and shows up as a ✗ above.
if [ ${#UNVERIFIED[@]} -gt 0 ]; then
  echo ""
  echo "!! Installed WITHOUT checksum verification:"
  printf '   - %s\n' "${UNVERIFIED[@]}"
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
# NEXT_STEP_FIRST was set back in step 5, before this call, because
# finish_install is what prints the closing "Next:" list.
INSTALL_RC=0
finish_install || INSTALL_RC=1

# ---------------------------------------------------------------------------
# 10. Make zsh the login shell — deliberately the LAST thing this script does
# ---------------------------------------------------------------------------
# This used to run before the stow step, and that ordering was actively harmful:
# stow failing anywhere (a conflict it couldn't resolve, a read-only ~/.config)
# takes the script down through `set -e` with the login shell ALREADY switched, so
# the next login started zsh with nothing stowed — which drops you into zsh's
# zsh-newuser-install wizard instead of a shell, with no .zshrc to explain why.
# Bash with unstowed configs is a recoverable state; that is not.
#
# So: only switch once finish_install has confirmed the configs are actually in
# place, and if it hasn't, say plainly that the shell was left alone.
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
