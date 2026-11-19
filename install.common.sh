#!/usr/bin/env bash
# Shared bootstrap steps for install.sh (macOS) and install.linux.sh (Linux).
#
# Source this file from either installer. Keep platform-specific steps in the callers.
#
# Contract — the caller must set:
#   DOTFILES   absolute path to the repo (resolved from the script's own location)
# Optional:
#   LOG        path to a package-manager log, mentioned in the closing message
#
# Sourcing this file runs the root check below immediately, so source it early —
# after the caller's platform guard, before anything that touches $HOME.

# Run as your normal user. Root installation targets the wrong home and login shell.
# Both installers call sudo themselves for package steps. AUR builds cannot run as root.
if [ "$(id -u)" -eq 0 ] && [ -z "${DOTFILES_ALLOW_ROOT:-}" ]; then
  _self="$(basename -- "${0:-install.sh}")"
  echo "!! Do not run this script with sudo or as root." >&2
  echo "   \$HOME would be $HOME, so chezmoi, terminfo and the backup directory" >&2
  echo "   would all target the wrong account." >&2
  echo "" >&2
  echo "   Run it as your normal user instead:" >&2
  echo "     ./$_self" >&2
  echo "" >&2
  echo "   (It calls sudo itself for the package installs.)" >&2
  echo "   Genuinely provisioning a root account? DOTFILES_ALLOW_ROOT=1 overrides." >&2
  unset _self
  # Return so callers can catch failure without terminating their shell.
  return 1
fi

# Where anything chezmoi would overwrite gets moved instead of clobbered.
# Derived from $HOME, so it must come after the root check above.
: "${BACKUP:=$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)}"

# Optional platform-specific first entry in the closing "Next:" list.
: "${NEXT_STEP_FIRST:=}"

# Both installers record package failures here, space-separated, for verify_install's exit status.
: "${FAILED_PKGS:=}"

# Accepted binary names for both installers, primary first and space-separated.
# Homebrew uses 7zz, Linux uses 7z. ImageMagick 6 provides convert, not magick.
# Debian renames fd/bat to fdfind/batcat. wl-clipboard provides wl-copy.
# Tools whose binary matches their package name need no entry.
tool_bins() {
  case "$1" in
    neovim)       echo "nvim" ;;
    ripgrep)      echo "rg" ;;
    git-delta)    echo "delta" ;;
    worktrunk)    echo "wt" ;;
    sevenzip)     echo "7zz 7z" ;;
    poppler)      echo "pdftoppm" ;;
    imagemagick)  echo "magick convert" ;;
    ncurses)      echo "tic" ;;
    fontconfig)   echo "fc-cache" ;;
    fd)           echo "fd fdfind" ;;
    bat)          echo "bat batcat" ;;
    wl-clipboard) echo "wl-copy" ;;
    *)            echo "$1" ;;
  esac
}

# Return one primary name for release extraction and version queries.
bin_name() {
  local names; names="$(tool_bins "$1")"
  printf '%s\n' "${names%% *}"
}

# Accept any binary name listed for this tool.
have_tool() {
  local b
  for b in $(tool_bins "$1"); do
    command -v "$b" >/dev/null 2>&1 && return 0
  done
  return 1
}

# Move every existing target that `chezmoi apply` would change into $BACKUP, then
# apply. Old Stow symlinks show up as changes too, so a Stow machine migrates here.
chezmoi_with_backup() {
  local status rel
  status="$(chezmoi --source "$DOTFILES" status --path-style relative)" || return 1
  # Status lines are "XY path" and sorted, so a parent moves before its children.
  while IFS= read -r rel; do
    rel="${rel:3}"
    [ -n "$rel" ] || continue
    [ -e "$HOME/$rel" ] || [ -L "$HOME/$rel" ] || continue
    mkdir -p "$BACKUP/$(dirname "$rel")"
    mv "$HOME/$rel" "$BACKUP/$rel"
    echo "   ↳ backed up ~/$rel → $BACKUP/$rel"
  done <<< "$status"
  chezmoi --source "$DOTFILES" apply --force
}

# Everything from chezmoi to the sesh import file: identical on both platforms
# because it only touches this repo and $HOME.
#
# Returns non-zero if a step that verify_install can also see went wrong (chezmoi),
# so finish_install can fold it into the exit status. Steps whose failure is only
# a degradation — a missing tmux theme, no undercurl — warn and return 0.
run_shared_tail() {
  local rc=0
  echo ""
  # Record deploy failures, but continue so verification can report everything.
  echo "==> Applying dotfiles with chezmoi"
  chezmoi_with_backup || rc=1
  # Private-module credentials stay in ~/.netrc and the untracked ~/.zshrc.local.

  ## terminfo/ sits outside home/, so chezmoi does not deploy it: it is compiled into ~/.terminfo.
  ## Adds an xterm-256color variant carrying Smulx/Setulc so neovim emits undercurl
  ## inside herdr panes (see the TERM swap in home/dot_zshrc).
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
    # An offline fetch must not abort the run before verification. Git prints
    # the failure and verify_install checks for the TPM directory.
    git clone https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm" \
      || echo "   ! TPM clone failed (offline?) — prefix+I will not work until it is installed"
  else
    echo "   ✓ already present"
  fi
  # Install plugins on a fresh machine, including the theme.
  if [ -x "$HOME/.config/tmux/plugins/tpm/bin/install_plugins" ]; then
    "$HOME/.config/tmux/plugins/tpm/bin/install_plugins" \
      || { echo "   ! TPM could not install all plugins (offline?)" >&2; rc=1; }
  fi

  # sesh/sesh.toml imports a machine-specific session file; sesh errors if the
  # import target is missing, so guarantee it exists (empty is fine). Put work/
  # client project sessions here — it stays untracked, outside the dotfiles repo.
  echo "==> Ensuring machine-specific sesh session file exists"
  [ -f "$HOME/.config/sesh.local.toml" ] || touch "$HOME/.config/sesh.local.toml"

  return "$rc"
}

# Report installed tools and links, not just package-manager success.
verify_install() {
  echo ""
  echo "==> Verifying"
  local _fail=0 tool pkg

  for tool in zsh tmux chezmoi neovim ripgrep fzf zoxide bat fd gh lazygit \
              git-delta starship atuin yazi carapace sesh herdr worktrunk mise jq; do
    have_tool "$tool" || { echo "   ✗ missing binary: $(bin_name "$tool") ($tool)"; _fail=1; }
  done

  # Missing preview backends only warn, since yazi works without previews.
  for tool in ffmpeg sevenzip poppler imagemagick; do
    have_tool "$tool" || echo "   ! yazi preview backend missing: $tool (previews only)"
  done

  # Missing script linting only warns, since runtime configuration does not need it.
  have_tool shellcheck || echo "   ! shellcheck missing (lints these install scripts; check.sh C8)"

  # Include recorded failures that binary checks cannot detect, such as the font.
  for pkg in ${FAILED_PKGS-}; do
    echo "   ✗ package missing or unusable: $pkg"; _fail=1
  done

  # chezmoi verify covers every managed file, so a newly added config needs no entry here.
  if have_tool chezmoi && ! chezmoi --source "$DOTFILES" verify >/dev/null 2>&1; then
    echo "   ✗ deployed config differs from the repo (see: chezmoi diff)"; _fail=1
  fi

  [ -d "$HOME/.config/tmux/plugins/tpm" ] || { echo "   ✗ TPM not installed"; _fail=1; }
  [ -f "$HOME/.config/tmux/plugins/tmux/catppuccin.tmux" ] \
    || { echo "   ✗ Catppuccin tmux plugin missing (run prefix+I)"; _fail=1; }
  [ -f "$HOME/.config/sesh.local.toml" ]  || { echo "   ✗ sesh.local.toml missing"; _fail=1; }
  infocmp xterm-256color-undercurl >/dev/null 2>&1 \
    || echo "   ! terminfo entry xterm-256color-undercurl not compiled (undercurl only)"

  if [ "$_fail" -eq 0 ]; then
    echo "   ✓ all checks passed"
  else
    echo "   (see the manual-install section above for anything missing)"
  fi

  [ -d "$BACKUP" ] && echo "" && echo "==> Files moved aside are in $BACKUP"
  return "$_fail"
}

# Always print next steps, but return failure if shared steps or verification fail.
finish_install() {
  local rc=0
  # Testing the return status disables errexit inside the tail so verification always runs.
  run_shared_tail || rc=1
  verify_install || rc=1
  print_next_steps
  if [ "$rc" -ne 0 ]; then
    echo "" >&2
    echo "!! The install is INCOMPLETE — see the ✗ lines under 'Verifying' above." >&2
  fi
  return "$rc"
}

# Closing message. Set NEXT_STEP_FIRST beforehand to prepend a platform-specific
# step — Linux uses it for the login-shell re-login.
#
# Keep machine-specific identity and includeIf rules in ~/.gitconfig, which takes precedence over the deployed Git configuration.
print_next_steps() {
  local n=1 step
  echo ""
  echo "Done!${LOG:+ Log: $LOG}"
  echo "Next:"
  for step in \
    ${NEXT_STEP_FIRST:+"$NEXT_STEP_FIRST"} \
    "Restart your terminal so the new shell config is loaded." \
    "In tmux, press prefix+I to retry any plugins that failed to install." \
    "Set your git identity in ~/.gitconfig — see the git identity section in README.md." \
    "Authenticate your forge CLI ('gh auth login' or 'glab auth login') for PR/MR lookup." \
    "Pick language runtimes: mise use -g node@lts java@corretto-25 go@latest"
  do
    printf '  %d. %s\n' "$n" "$step"
    n=$((n + 1))
  done
}
