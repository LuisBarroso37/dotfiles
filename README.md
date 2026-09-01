# dotfiles

My personal dev environment — terminal, editor, shell, and CLI tools.

## What's inside

| Tool | Config path | Purpose |
|------|-------------|---------|
| [Neovim](https://neovim.io) + [LazyVim](https://lazyvim.org) | `.config/nvim/` | Editor |
| [tmux](https://github.com/tmux/tmux) | `.config/tmux/tmux.conf` | Terminal multiplexer |
| [sesh](https://github.com/joshmedeski/sesh) | `.config/sesh/sesh.toml` | tmux session manager |
| [Ghostty](https://ghostty.org) | `.config/ghostty/` | Terminal emulator |
| [Zsh](https://zsh.sourceforge.io) | `.zshrc`, `.zprofile`, `.zshenv` | Shell |
| [Starship](https://starship.rs) | `.config/starship.toml` | Shell prompt |
| [Atuin](https://atuin.sh) | `.config/atuin/config.toml` | Shell history search |
| [lazygit](https://github.com/jesseduffield/lazygit) | `.config/lazygit/config.yml` | Terminal git UI |
| [yazi](https://github.com/sxyazi/yazi) | `.config/yazi/` | Terminal file manager |
| [delta](https://github.com/dandavison/delta) | `.config/git/config` | Syntax-highlighting git diff pager |
| [gh](https://cli.github.com) | — | GitHub CLI |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | — | Smarter `cd` |
| [bat](https://github.com/sharkdp/bat) | — | Better `cat` |
| [fzf](https://github.com/junegunn/fzf) | — | Fuzzy finder |
| [fd](https://github.com/sharkdp/fd) | — | Better `find` |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | — | Better `grep` |
| [carapace](https://carapace.sh) | — | Multi-shell completion engine |
| [mise](https://mise.jdx.dev) | `~/.config/mise/config.toml` (untracked) | Runtime version manager |
| [herdr](https://herdr.dev) | `.config/herdr/config.toml` | Agent workspace multiplexer |
| [jq](https://jqlang.github.io/jq/) | — | JSON processor — required by `wth`/`wthr` |
| [karabiner-elements](https://karabiner-elements.pqrs.org) | `macos/karabiner/karabiner.json` | macOS only — keyboard remapping |
| [rectangle](https://rectangleapp.com) | `macos/rectangle/RectangleConfig.json` | macOS only — window manager |

---

## Key idea

Tools expect their configs at fixed paths (e.g. `~/.config/nvim/`), but you want those files tracked in a git repo. [GNU Stow](https://www.gnu.org/software/stow/) — a symlink manager — bridges the two: your real files live in `~/dotfiles/`, and Stow symlinks them into place:

```
~/dotfiles/nvim/   ──►  ~/.config/nvim/   (symlink)
~/dotfiles/tmux/   ──►  ~/.config/tmux/   (symlink)
```

You edit files at the paths tools already expect — they just happen to be symlinks. Git sees the real files inside `~/dotfiles/`.

---

## Fresh machine setup

### 1. Clone the repo

```sh
git clone https://github.com/<your-username>/dotfiles.git ~/dotfiles
```

### 2. Run the install script

**macOS**:

```sh
cd ~/dotfiles
chmod +x install.sh
./install.sh
```

**Linux** (`pacman`, `apt`, or `dnf` — Arch/Manjaro/CachyOS, Debian/Ubuntu/Mint, Fedora/RHEL/Rocky; 64-bit only):

```sh
cd ~/dotfiles
chmod +x install.linux.sh
./install.linux.sh      # NOT with sudo — it escalates on its own
```

Both scripts install every tool above, install Stow and symlink all configs,
install mise (with no language runtimes pinned — a fresh clone is
language-free), set up tmux/sesh plugin machinery, and finish with a
verification pass. Shared post-install steps live in `install.common.sh`,
sourced by both. An optional untracked `install.local.sh` next to them can
hold per-machine toolchains.

### 3. Restart your terminal

### 4. Recreate your git identity

`~/.gitconfig` is untracked (it overrides the tracked `.config/git/config`) and
isn't created by this repo, so write it by hand. Give it your default
identity, then add an `includeIf` per directory that needs a different one
(e.g. work repos under a folder that isn't this one) — bundle a different SSH
key into the same override with `core.sshCommand`:

```sh
cat > ~/.gitconfig <<'EOF'
[user]
	name = Your Name
	email = you@example.com

[includeIf "gitdir:~/work-projects/"]
	path = ~/.gitconfig-work
EOF

cat > ~/.gitconfig-work <<'EOF'
[user]
	name = Your Work Name
	email = you@work.example

[core]
	sshCommand = ssh -i ~/.ssh/id_ed25519_work -o IdentitiesOnly=yes
EOF
```

### 5. Set up private-registry tokens (optional)

Only needed for `npm`, `terraform`, or `go` against a private, token-gated
registry. This repo ships no tokens or vault names — that lives in an
untracked `opread` shell function in `~/.zshrc.local` (worked example in
[cheatsheet.md](cheatsheet.md#gitlab-tokens-opread)), fetched on demand rather
than at shell startup.

---

## Updating an existing machine

```sh
cd ~/dotfiles
git pull && ./install.sh      # or ./install.linux.sh
```

Re-running the install script *is* the update path — every step is
idempotent. Don't stop at `git pull`: config changes regularly come with a
package step.

---

## How Stow works in practice

Each tool has its own subdirectory at the repo root; `.stowrc` sets the stow
target to `~/.config`, so `stow .` creates a directory-level symlink per
package:

```
dotfiles/
  nvim/          →  ~/.config/nvim  (symlink)
  tmux/          →  ~/.config/tmux  (symlink)
  starship.toml  →  ~/.config/starship.toml
```

`README.md`, `cheatsheet.md`, and the `install*.sh` scripts are excluded via
`.stowrc` ignore rules.

**Zsh is a special case** — its dotfiles live in `~`, not `~/.config/`, so
it's stowed separately:

```sh
stow .                     # all ~/.config packages
stow --target="$HOME" zsh  # zsh dotfiles → ~
```

**Three more packages are excluded from `stow .`** because a symlink is the
wrong shape for them:

- `macos/` — `install.sh` wires both by hand: `karabiner/` as a whole
  directory (Karabiner's `rename(2)` save would orphan a file-level symlink),
  `rectangle/RectangleConfig.json` as a copy (Rectangle refuses a symlinked
  config). Rectangle edits made in-app don't flow back to the repo —
  re-export over the tracked file when you change a shortcut.
- `herdr/` — writes runtime state into `~/.config/herdr`, so it must stay a
  real directory; `install.common.sh` links only `config.toml` into it.
- `terminfo/` — compiled into `~/.terminfo` with `tic`, not symlinked; carries
  an `xterm-256color` variant for undercurl support inside herdr panes.

**Machine-specific config** lives in `~/.zshrc.local` (untracked, sourced last
by `.zshrc`) — put anything you don't want on every machine there (embedded
toolchains, Docker hosts, SDKMAN). **Language runtimes** follow the same
split via [mise](https://mise.jdx.dev): the tracked `.zshrc` only activates
mise; actual versions live in an untracked `~/.config/mise/config.toml`:

```sh
mise use -g node@lts go@latest java@corretto-25
```

**Neovim is tuned for JS/TS/web** (`vtsls`, ESLint LSP, `prettier` via
conform), but each piece self-gates on the project actually having a config
for it, so it's inert on non-JS machines. Anything shaped by one codebase
(LSP heap sizes, per-repo lint autocmds) belongs in that repo's own
`.nvim.lua`, loaded via `vim.o.exrc`.

To add a new tool to the repo:

1. `mkdir ~/dotfiles/<tool>/`
2. `mv ~/.config/<tool>/ ~/dotfiles/<tool>/`
3. `cd ~/dotfiles && stow .`
