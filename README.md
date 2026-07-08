# dotfiles

My personal dev environment — terminal, editor, shell, and CLI tools.

## What's inside

| Tool | Config path | Purpose |
|------|-------------|---------|
| [Neovim](https://neovim.io) + [LazyVim](https://lazyvim.org) | `.config/nvim/` | Editor |
| [tmux](https://github.com/tmux/tmux) | `.config/tmux/tmux.conf` | Terminal multiplexer |
| [sesh](https://github.com/joshmedeski/sesh) | `.config/sesh/sesh.toml` | tmux session manager |
| [Ghostty](https://ghostty.org) | `.config/ghostty/` | Terminal emulator |
| [fish](https://fishshell.com) | `.config/fish/` | Shell |
| [Starship](https://starship.rs) | `.config/starship.toml` | Shell prompt |
| [Atuin](https://atuin.sh) | `.config/atuin/config.toml` | Shell history search |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | — | Smarter `cd` |
| [bat](https://github.com/sharkdp/bat) | — | Better `cat` |
| [fzf](https://github.com/junegunn/fzf) | — | Fuzzy finder |
| [fd](https://github.com/sharkdp/fd) | — | Better `find` |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | — | Better `grep` |

---

## Key idea

The problem with dotfiles is that tools expect their configs at fixed paths (e.g. `~/.config/nvim/`), but you want those files tracked in a git repo.

The solution is [GNU Stow](https://www.gnu.org/software/stow/) — a symlink manager. Your real config files live inside `~/dotfiles/`, and Stow creates symlinks at the locations tools expect, pointing back into the repo:

```
~/dotfiles/nvim/.config/nvim/   ──►  ~/.config/nvim/   (symlink)
~/dotfiles/tmux/.config/tmux/   ──►  ~/.config/tmux/   (symlink)
```

You edit files at the paths you already know (`~/.config/nvim/`, etc.) — they just happen to be symlinks. Git sees the real files inside `~/dotfiles/`, so you commit and push changes like any other repo. **Stow is the only required tool that isn't a terminal utility** — everything else is optional depending on what you use.

---

## Fresh machine setup

### 1. Clone the repo

```sh
git clone https://github.com/<your-username>/dotfiles.git ~/dotfiles
```

### 2. Run the install script

```sh
cd ~/dotfiles
chmod +x install.sh
./install.sh
```

This will:
- Install [Homebrew](https://brew.sh) (if missing)
- Install all tools listed above via `brew install`
- Install **GNU Stow** (`brew install stow`) — required to create the symlinks
- Use Stow to symlink all configs to their correct locations under `~/`
- Set fish as the default shell

### 3. Restart your terminal

All configs will be in place and your shell, editor, and tools will pick them up automatically.

---

## How Stow works in practice

Each tool has its own subdirectory in this repo. Inside it, the folder structure mirrors `~/` exactly:

```
dotfiles/
  nvim/
    .config/
      nvim/          ← actual config files here
  tmux/
    .config/
      tmux/
        tmux.conf
  starship/
    .config/
      starship.toml
```

Running `stow nvim` from inside `~/dotfiles/` tells Stow: "look inside `nvim/`, and for every file and folder in there, create a symlink one level up (in `~/`) at the same relative path."

Result: `~/.config/nvim` becomes a symlink to `~/dotfiles/nvim/.config/nvim`.

To add a new tool to the repo:

1. Create its package folder: `mkdir -p ~/dotfiles/<tool>/.config/<tool>/`
2. Move the config there: `mv ~/.config/<tool>/ ~/dotfiles/<tool>/.config/`
3. Run stow: `cd ~/dotfiles && stow <tool>`

---

## First-time migration (existing machine only)

If you already have configs on your current machine and want to move them into this repo, run the migration script instead of the install script:

```sh
cd ~/dotfiles
chmod +x migrate.sh
./migrate.sh
```

This will:
1. Move each existing config from `~/.config/<tool>/` into `~/dotfiles/<tool>/.config/<tool>/`
2. Install Stow if missing
3. Run Stow for each package to put the symlinks back in place

After that, push to GitHub:

```sh
cd ~/dotfiles
git init
git add .
git commit -m "initial dotfiles"
git remote add origin git@github.com:<your-username>/dotfiles.git
git push -u origin main
```

From this point on, any change you make to your configs is just a `git push` away from being synced everywhere.
