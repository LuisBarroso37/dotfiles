#!/usr/bin/env bash
set -euo pipefail

# Resolve the repo from this script's own location, so the bootstrap works from a
# clone anywhere — not just ~/dotfiles.
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# This script is macOS/Homebrew-only. On Linux, hand off to the native-package-
# manager bootstrap so nobody accidentally installs Homebrew-on-Linux.
if [ "$(uname -s)" != "Darwin" ]; then
  echo "install.sh is for macOS. On Linux, run ./install.linux.sh instead." >&2
  exit 1
fi

# Everything after the package step (submodules, stow, herdr, terminfo, TPM,
# sesh file, verification) is identical on both platforms and lives here, run by
# finish_install at the bottom. Sourced before anything touches $HOME: it runs
# the refuse-to-run-as-root check at source time and derives $BACKUP from $HOME.
# shellcheck source=install.common.sh
source "$DOTFILES/install.common.sh"

echo "==> Installing Homebrew (if missing)"
if ! command -v brew &>/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# The installer does not put brew on PATH for the *current* shell, and on Apple
# Silicon /opt/homebrew/bin isn't on the default PATH at all — so the very next
# `brew install` would die with "command not found" on a fresh Mac. Load the
# environment explicitly, trying both prefixes.
if ! command -v brew &>/dev/null; then
  for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$_brew" ] && { eval "$("$_brew" shellenv)"; break; }
  done
  unset _brew
fi
command -v brew &>/dev/null || { echo "install.sh: brew not found after install" >&2; exit 1; }

echo "==> Installing packages"

# An array rather than one long `brew install` line, so the failure path below can
# retry the formulae one at a time and name the one that broke.
#
# jq is NOT optional: zsh/.zshrc's _herdr_ws_at / wth / wthr parse `herdr
# workspace list` through it. herdr likewise — the tracked .zshrc defines wth and
# wthr against it, so a machine without the binary gets dead functions.
#
# The last four are yazi's preview backends, previously left to install.local.sh
# and therefore absent from every rebuild:
#   ffmpeg       → video thumbnails/preview
#   sevenzip     → archive previews
#   poppler      → PDF preview
#   imagemagick  → AVIF/HEIC/JXL image support
# Install the plain formulae, not the `-full` variants: those pull ~85 extra
# transitive deps (whisper-cpp, tesseract, vulkan-*, ghostscript) for previews
# that work fine without them.
#
# Machine-specific toolchains (embedded: arm-none-eabi-gdb, clang-format; JDKs;
# anything else) belong in install.local.sh, sourced at the bottom.
_formulae=(
  neovim
  tmux
  sesh
  starship
  atuin
  zoxide
  bat
  fzf
  fd
  ripgrep
  carapace
  stow
  lazygit
  gh
  git-delta
  yazi
  mise
  jq
  herdr
  shellcheck
  ffmpeg
  sevenzip
  poppler
  imagemagick
)

# Formulae, deliberately NOT on the fatal path — for exactly the reason spelled
# out for the casks below.
#
# This was a single unguarded `brew install`, so any one formula failing (a bottle
# download blip, a source build that hasn't caught up with a just-released macOS —
# most likely on the four heavyweight preview backends at the end) took the whole
# script down at this line under `set -e`: nothing stowed, no terminfo, no TPM, no
# sesh.local.toml, no verification, and not even an error banner. The run simply
# ended. The config half of the bootstrap does not depend on any of these being
# present, so it gets to run regardless.
#
# The retry loop is not just for the error message: brew stops at the first
# formula it cannot install, so a failure in the middle of the list means the rest
# were never even attempted. Installing them individually picks those up. A
# formula whose binary is present afterwards is not recorded — brew exits non-zero
# for harmless reasons too (an already-installed keg it won't relink, say), and a
# working tool must not be reported as missing.
if ! brew install "${_formulae[@]}"; then
  echo "!! 'brew install' did not complete — retrying formula by formula to find out what failed." >&2
  for _formula in "${_formulae[@]}"; do
    brew install "$_formula" || have_tool "$_formula" || {
      FAILED_PKGS+=" $_formula"
      echo "!! formula '$_formula' did not install — continuing without it." >&2
    }
  done
  unset _formula
fi
unset _formulae

# GUI apps, deliberately NOT on the fatal path.
#
# `brew install --cask ghostty` exits non-zero when /Applications/Ghostty.app
# already exists outside brew's control — which is the normal order of events,
# since you need a terminal before you can clone this repo. Under `set -e` that
# aborted the whole script at this line, so nothing was ever stowed and the run
# ended with no error banner.
#
# --adopt makes brew take ownership of an identical existing app instead of
# refusing. If it still fails (say the installed app is a different version),
# warn and carry on: a terminal emulator or a font is not worth abandoning the
# config bootstrap for, and the verification at the end reports the real state.
#
# Tolerating the failure is right; forgetting about it was not. Nothing re-checked
# these afterwards, so a font-jetbrains-mono-nerd-font that never landed still
# ended in "✓ all checks passed" and exit 0 while the prompt, tmux status line and
# yazi UI were full of tofu — a font has no binary for verify_install to look for.
# Recording it in FAILED_PKGS is how verification learns about it.
for _cask in ghostty font-jetbrains-mono-nerd-font karabiner-elements rectangle; do
  brew install --cask --adopt "$_cask" || {
    FAILED_PKGS+=" $_cask"
    echo "!! cask '$_cask' did not install — continuing without it." >&2
  }
done
unset _cask

# Karabiner-Elements: symlink the whole ~/.config/karabiner DIRECTORY, not the
# karabiner.json inside it.
#
# This used to link the file, on the theory that the directory had to stay real
# because Karabiner writes runtime state (automatic_backups/, assets/, log/)
# into it. That link does not survive: Karabiner saves by writing a temp file
# and rename(2)-ing it over karabiner.json, which replaces the symlink with a
# fresh regular file. install.sh left a correct link, then the first change made
# in the Karabiner UI silently orphaned the repo copy — edits stopped reaching
# git and check.sh's "→ repo" assertion had already passed on the way out.
#
# A directory symlink is outside that blast radius: rename(2) resolves the
# directory component of the destination, so the new inode lands inside the repo
# and the link itself is never touched. Confirmed by triggering a real Karabiner
# write against both layouts. The runtime state now lives in the repo, where
# .gitignore excludes it.
echo "==> Wiring karabiner config"
mkdir -p "$DOTFILES/macos/karabiner"
mkdir -p "$HOME/.config"
# A pre-existing real directory holds this machine's own config and runtime
# state — move it aside rather than rm -rf it, so a bad guess here is recoverable.
#
# _karabiner_ok gates the ln below, and that gate is the whole point. This was an
# `if … mv … && echo …; fi` with nothing downstream checking it: a failed mv (a
# read-only backup volume, a stale ~/.dotfiles-backup owned by another user) just
# short-circuited the && and fell through to the ln, which then ran against a
# still-real directory. `ln -sfn` does NOT refuse that — -n only declines to
# dereference a symlink-to-directory — so it created a NESTED link at
# ~/.config/karabiner/karabiner, exited 0, recorded nothing in FAILED_PKGS, and
# left Karabiner reading its own untouched config while the run reported success.
_karabiner_ok=1
if [ -d "$HOME/.config/karabiner" ] && [ ! -L "$HOME/.config/karabiner" ]; then
  mkdir -p "$BACKUP"
  if mv "$HOME/.config/karabiner" "$BACKUP/karabiner"; then
    echo "   ↳ backed up $HOME/.config/karabiner → $BACKUP/karabiner"
  else
    _karabiner_ok=0
    FAILED_PKGS+=" karabiner-config"
    echo "!! could not move $HOME/.config/karabiner → $BACKUP/karabiner" >&2
    echo "   leaving the existing directory alone — linking over it would nest" >&2
    echo "   a symlink inside it rather than replace it." >&2
  fi
fi
# -n so a re-run replaces the existing link instead of dropping a nested
# "karabiner" link inside the directory it already points at.
if [ "$_karabiner_ok" -eq 1 ]; then
  ln -sfn "$DOTFILES/macos/karabiner" "$HOME/.config/karabiner" \
    || { FAILED_PKGS+=" karabiner-config"; echo "!! failed to link karabiner config dir" >&2; }
fi
unset _karabiner_ok

# Rectangle: RectangleConfig.json is Rectangle's own export format, not a standard
# plist — `defaults import` does not apply.
#
# This used to run `open -g "rectangle://import?url=..."`. That URL does nothing.
# Rectangle's scheme handler only understands the hosts `execute-action` and
# `execute-task` (ignore-app/unignore-app) and drops everything else on its
# `default:` branch — there has never been an `import` host. The failure was
# invisible from both sides: `open` exits 0 because a handler *is* registered for
# rectangle://, and the call still launched the app, so an install looked like it
# had worked while Rectangle sat on stock defaults. Caught by diffing
# `defaults read com.knollsoft.Rectangle` against this repo's config — none of the
# tracked keys were in the domain.
#
# The supported non-GUI path is the Application Support drop: Rectangle calls
# Defaults.loadFromSupportDir() as the first line of applicationDidFinishLaunching
# and imports ~/Library/Application Support/Rectangle/RectangleConfig.json if one
# is there. Three constraints fall out of that code path:
#   - it must be a real file. Rectangle treats a symlink (or a world-writable
#     file) as tampering: it refuses the import, deletes the file and alerts. So
#     cp, not ln -s, plus an explicit chmod 644 in case of a loose umask. This is
#     the one config in the repo that deliberately does NOT get symlinked.
#   - it is read at launch only. The --adopt cask install above may well have left
#     Rectangle running, and that instance would never look at the file — quit it
#     first and wait for the process to actually go away before relaunching.
#   - it prompts "Apply Rectangle configuration?" first, and Rectangle's NSAlert
#     does not call NSApp.activate. Under `open -g` that modal would block launch
#     from the background with nothing on screen to explain the hang, so launch in
#     the foreground and say up front that a prompt is coming.
# On apply Rectangle renames the file to RectangleConfig<timestamp>.json, so the
# drop is self-consuming: a re-run copies it again and re-prompts. A file still
# sitting there afterwards means the import never happened — check.sh asserts on
# exactly that.
echo "==> Importing Rectangle config"
# Gate on the cask's own accounting rather than probing /Applications: if the cask
# failed, FAILED_PKGS already carries it and verify_install will report it, so
# this step just steps aside instead of adding a second error for one root cause.
case " ${FAILED_PKGS-} " in
  *" rectangle "*)
    echo "   ↳ rectangle cask unavailable — skipping config import." >&2
    ;;
  *)
    _rect_support="$HOME/Library/Application Support/Rectangle"
    # Only quit if it is actually up: `quit app` on a non-running app makes
    # AppleScript launch it just to close it again.
    if pgrep -xq Rectangle; then
      osascript -e 'quit app "Rectangle"' >/dev/null 2>&1 || killall Rectangle 2>/dev/null || true
      # Bounded — never wedge the install on an app that will not die. If it is
      # still up after this, the relaunch below is a no-op and the leftover file
      # is picked up by the next launch (or flagged by check.sh).
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -xq Rectangle || break
        sleep 0.5
      done
    fi
    mkdir -p "$_rect_support"
    # || true on each step: under `set -e` an unguarded failure here aborts before
    # finish_install runs — nothing stowed, no verification, no error banner.
    cp -f "$DOTFILES/macos/rectangle/RectangleConfig.json" "$_rect_support/RectangleConfig.json" \
      && chmod 644 "$_rect_support/RectangleConfig.json" \
      && echo "   ↳ confirm the \"Apply Rectangle configuration?\" prompt when Rectangle opens" \
      && { open -a Rectangle || true; } \
      || { FAILED_PKGS+=" rectangle-config"; echo "!! failed to stage Rectangle config" >&2; }
    unset _rect_support
    ;;
esac

# Optional per-machine install steps (extra packages, yazi's preview deps, etc.)
# live in an untracked install.local.sh next to this script — sourced here if it
# exists, so this tracked script stays portable. It's gitignored + stowignored.
if [ -f "$DOTFILES/install.local.sh" ]; then
  echo "==> Running install.local.sh (machine-specific)"
  # shellcheck source=/dev/null
  # || true: failures inside install.local.sh must not abort before finish_install
  # runs — without this, set -e would skip stow, terminfo, TPM, and verify_install.
  source "$DOTFILES/install.local.sh" || true
fi

finish_install
