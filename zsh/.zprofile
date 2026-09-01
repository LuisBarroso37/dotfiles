# Set PATH, MANPATH, etc., for Homebrew. Probe the known prefixes rather than
# hardcoding one: this file is stowed on Linux too (install.linux.sh), and on an
# Intel Mac brew lives under /usr/local. A hardcoded ARM path made every login
# shell on those machines print "no such file or directory".
for _brew in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
  [[ -x "$_brew" ]] && { eval "$("$_brew" shellenv)"; break; }
done
unset _brew

# PATH entries live here, next to brew's, not in .zshrc. .zshrc runs for
# *interactive* shells only, so these were established purely as a side effect of
# opening a prompt: `zsh script.sh` got nothing, and neither did anything else
# whose ancestry never went through an interactive shell. Setting them once per
# login shell and exporting them means every child inherits them.
#
# Ordering note: mise is activated from .zshrc, i.e. *after* this file, so mise's
# entries are prepended on top of everything below and win — which is what we
# want. When ~/go/bin was prepended in .zshrc *after* `mise activate`, it shadowed
# mise's go and pinned you to whatever `go install` last left there.
export PATH="$HOME/.local/bin:$PATH"

# Language-tool bin dirs (portable, guarded no-ops when absent). The toolchains
# come from mise (go) and rustup (rust); these just expose the CLIs those tools
# install: `go install` → ~/go/bin, `cargo install` → ~/.cargo/bin.
[ -d "$HOME/go/bin" ] && export PATH="$HOME/go/bin:$PATH"
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# `[ … ] && …` above leaves a non-zero status behind on a machine that has
# neither directory, which would become this file's exit status. Reset it.
true
