# Dev Cheatsheet

## tmux

> Prefix is `Ctrl+a` (remapped from default `Ctrl+b`).

### Splits & Panes

| Action | Key |
|--------|-----|
| Split vertically (pane right) | `Ctrl+a \|` |
| Split horizontally (pane below) | `Ctrl+a -` |
| Switch pane | `Ctrl+a h/j/k/l` |
| Close current pane (no prompt) | `Ctrl+a x` |
| Zoom pane (toggle fullscreen) | `Ctrl+a z` |
| Resize pane | `Ctrl+a H/J/K/L` (repeatable) |

### Windows (tabs)

| Action | Key |
|--------|-----|
| New window (in current path) | `Ctrl+a c` |
| Next window | `Ctrl+a n` |
| Previous window | `Ctrl+a p` |
| Pick window by number | `Ctrl+a 1–9` |
| Rename window | `Ctrl+a ,` |
| Close window | `Ctrl+a &` |

### Sessions

| Action | Key |
|--------|-----|
| Open session picker (sesh + fzf) | `Ctrl+a T` |
| New session | `tmux new -s name` |
| Detach | `Ctrl+a d` |
| List sessions | `tmux ls` |
| Attach to session | `tmux attach -t name` |

---

## Git worktrees (git + tmux + sesh)

> Worktrees are **sibling directories** named `<repo>.<branch>` (e.g.
> `portal.ICP-1234-desc` next to `portal`); each gets a tmux session named
> `<repo>-<branch>` (e.g. `portal-ICP-1234-desc` — hyphens, since `.` breaks tmux
> `-t` targets). Managed by the `wtc` / `wtr` zsh functions over plain `git worktree`.
> `sesh` (`Ctrl+a T`) is the picker for hopping between them.

### Mental model

- The main clone (`portal`, `intocare`) is **itself a worktree**, pinned to a branch — keep it on `main` so new worktrees branch off the right base.
- A branch can be checked out in **only one worktree at a time**.
- `git worktree` **never changes your shell's cwd**, and `wtr` **refuses to delete the session you're in** — so the old drift/self-kill surprises can't happen.

### Workflow

| Action | Command |
|--------|---------|
| Start a ticket (create worktree + enter its session) | `wtc ICP-1234-desc` — run from anywhere inside the repo |
| Hop between worktrees | `Ctrl+a T` (sesh picker) → attach to its session |
| List worktrees | `git worktree list` |
| Rebase current branch onto latest main | `wtrebase` — fetches, rebases onto `origin/<main>` (auto-stashes), and fast-forwards the main worktree too if it's clean & on main |
| Remove a worktree (+ session, + branch if merged) | `wtr ICP-1234-desc` — from your **main** session, not from inside it |
| Remove the worktree you're near | `wtr` (no arg → current branch) — must be run from **another** session |

- ✅ `wtc` drops you straight into the new worktree's session (switches client if already in tmux, attaches if not).
- ✅ `wtr` from your base (`main`) session; it kills the session and deletes the branch **only if merged** (unmerged branches are kept).
- ❌ `wtr` while standing inside the worktree/session you're deleting — it refuses.

### Daily workflow (from opening Ghostty)

> **Mental model:** `sesh` / `Ctrl+a T` = pick a main clone + hop between anything · `wtc` = start/enter a ticket worktree · `wtr` = tear one down · `wtrebase` = stay on top of main. Sessions don't auto-restore (see note below) — you rebuild them deterministically with these commands.

1. **Open Ghostty** → plain shell, no tmux yet. Jump into a project with **`Ctrl+a T`** → pick `portal` / `intocare` / `dotfiles` (or `sesh connect portal`). This starts tmux fresh and drops you in that repo's main-clone session. Keep main clones on `main`.
2. **Start a ticket** — from anywhere inside the repo: `wtc ICP-1234-desc`. Creates (or reuses) the worktree and drops you into its `<repo>-ICP-1234-desc` session.
3. **Hop around** — `Ctrl+a T` anytime to switch sessions; `Ctrl+a d` to detach (session keeps running).
4. **Stay current** — from inside a ticket session: `wtrebase` (rebase onto `origin/main`, auto-stash, fast-forward main clone too).
5. **Finish a ticket** — once merged, from a **different** session (e.g. your main clone, not from inside the worktree): `wtr ICP-1234-desc`. Removes worktree + session, deletes the branch only if merged.

> **Session resurrection is off.** `tmux-continuum` still auto-saves every 15 min, but nothing reopens on server start — rebuild with `sesh`/`wtc` instead. Want a specific layout back? Save with `Ctrl+a Ctrl+s`, restore manually with `Ctrl+a Ctrl+r`.

---

## LazyVim / Neovim

> `<leader>` is `Space` in LazyVim.

### Movement

| Action | Key |
|--------|-----|
| Beginning of line | `0` |
| First non-whitespace of line | `^` |
| End of line | `$` |
| Down / up half page | `Ctrl+d` / `Ctrl+u` |
| Top / bottom of file | `gg` / `G` |
| Go to line | `50G` or `:50` |
| Next / prev word | `w` / `b` |
| Next / prev WORD (whitespace-delimited) | `W` / `B` |
| Next occurrence of word under cursor | `*` |
| Flash jump (leap anywhere on screen) | `s` then 2 chars |
| Back / forward (jump list) | `Ctrl+o` / `Ctrl+i` |

### File & Buffer Navigation

| Action | Key |
|--------|-----|
| Open file explorer (Neo-tree) | `<leader>e` |
| Focus file explorer | `<leader>E` |
| Find file (fuzzy) | `<leader><space>` or `<leader>ff` |
| Recent files | `<leader>fr` |
| Switch between open buffers | `<leader>,` |
| Next / prev buffer | `]b` / `[b` |
| Close current buffer | `<leader>bd` |
| Close other buffers | `<leader>bo` |

### Search & Replace

| Action | Key / Command |
|--------|---------------|
| Search in current file | `/` then type |
| Next / previous match | `n` / `N` |
| Clear search highlight | `<leader>nh` or `Esc` |
| Search word under cursor (highlight all) | `*` |
| Search text in project (grep) | `<leader>sg` |
| Search word under cursor in project | `<leader>sw` |
| Project-wide find & replace | `<leader>sr` (via **grug-far**) |
| Replace in current file | `:%s/old/new/g` |
| Replace with confirmation | `:%s/old/new/gc` |
| Replace in selection | `:'<,'>s/old/new/g` |

**Find & replace all occurrences of a word in file:**
1. Cursor on the word
2. `*` — highlights all occurrences
3. `cgn` — change first match, type replacement (or nothing to delete), then `Escape`
4. `.` — repeat for each occurrence

Or delete all at once after `*`:
- `:%s///g` — empty pattern reuses the `*` search, replaces all with nothing

### Editing & Text Objects

> `i` = inner (excludes delimiters), `a` = around (includes delimiters). Works with `v`, `d`, `c`, `y`, etc.

| Action | Key |
|--------|-----|
| Yank word under cursor | `yiw` |
| Yank word + surrounding space | `yaw` |
| Select / delete / change / yank inside `{}` | `vi{` / `di{` / `ci{` / `yi{` |
| Select inside `()` | `vi(` |
| Select inside `[]` | `vi[` |
| Select inside `""` | `vi"` |
| Select inside `''` | `vi'` |
| Select inside ` `` ` | `` vi` `` |
| Select inside `<tag>` | `vit` |
| Select current word | `viw` |
| Select current paragraph | `vip` |
| Select around `{}` (incl. braces) | `va{` |
| Change inside `()` | `ci(` |
| Yank inside `[]` | `yi[` |
| Undo / redo | `u` / `Ctrl+r` |
| Select lines (line-visual mode) | `V` then `j`/`k` to extend |
| Move current line or selection down / up | `Alt+j` / `Alt+k` (Mac: `Option+j` / `Option+k`) |

**Delete a line range:**

| Action | Key / Command |
|--------|---------------|
| Delete lines 38–43 | `:38,43d` |
| Go to line 38, delete 6 lines | `38G` then `6dd` |
| Visual select range then delete | `38G` → `V` → `43G` → `d` |

**Registers (yank vs delete):**

> In Vim `d`/`dd`/`x`/`c` are *cut* — they overwrite the unnamed register `"`. Your
> last **yank** is kept separately in `"0`, which deletes never touch.

| Action | Key / Command |
|--------|---------------|
| Paste your last yank (ignores any deletes) | `"0p` |
| Paste over selection, keep your yank | `<leader>p` (visual) |
| Delete without saving to a register (black hole) | `<leader>d` |
| Explicit black-hole delete | `"_d` (e.g. `"_dd`) |

### LSP

| Action | Key |
|--------|-----|
| Go to definition | `gd` |
| Go to declaration | `gD` |
| Go to implementation | `gI` |
| Go to type definition | `gy` |
| Find all references | `gr` |
| Back / forward (jump list) | `Ctrl+o` / `Ctrl+i` |
| Hover docs / type info / possible values | `K` |
| Signature help | `gK` |
| Show diagnostic error popup (red squiggly) | `<leader>cd` |
| All diagnostics | `<leader>xx` |
| Close any popup / float | `q` or `Escape` |
| Code actions (e.g. add import for symbol under cursor) | `<leader>ca` |
| Rename symbol | `<leader>cr` |
| Format file | `<leader>cf` |

### Splits & Windows

| Action | Key |
|--------|-----|
| Split horizontally | `<leader>-` |
| Split vertically | `<leader>\|` |
| Move between splits | `Ctrl+h/j/k/l` |
| Close split | `<leader>wd` |
| Close all splits except current | `<leader>wo` |
| Equalize splits | `<leader>w=` |

### Git

| Action | Key |
|--------|-----|
| Open Lazygit | `<leader>gg` |
| Diff current file (hunks) | `<leader>gd` |
| **Review branch vs main** (tracked, pre-push) | `<leader>gr` |
| Uncommitted changes, incl. untracked (pre-commit) | `<leader>gv` |
| Close Diffview | `<leader>gV` |
| History: file (follows renames) | `<leader>gH` |
| History: selected range (visual mode) | `<leader>gH` |
| History: current line | `<leader>gl` |
| History: whole repo | `<leader>gA` |
| Toggle deleted lines inline (gitsigns) | `<leader>gtd` |
| Toggle word diff (gitsigns) | `<leader>gtw` |

> The Diffview mappings open in their own tab — see the **Diffview** section
> below for navigating inside it.

### Misc

| Action | Key |
|--------|-----|
| Command palette | `<leader>:` |
| Open terminal | `<leader>ft` or `Ctrl+\`` |
| Toggle word wrap | `<leader>uw` |
| Save | `:w` or `Ctrl+S` (works in normal, insert, visual) |
| Quit | `:q` |
| Save & quit | `:wq` |

---

## Lazygit

> Open from LazyVim with `<leader>gg`. Press `?` inside any panel for full keybinding help.

### Navigation

| Action | Key |
|--------|-----|
| Move between panels | `Tab` / `Shift+Tab` |
| Scroll up / down | `↑` / `↓` or `k` / `j` |
| Switch to files panel | `2` |
| Switch to branches panel | `3` |
| Switch to commits panel | `4` |
| Quit | `q` |

### Files & Staging

| Action | Key |
|--------|-----|
| Stage / unstage file | `Space` |
| Stage all files | `a` |
| Open diff for file | `Enter` |
| Stage / unstage hunk (in diff) | `Space` |
| Discard changes to file | `d` |

### Diff View

| Action | Key |
|--------|-----|
| Open file diff (side-by-side by default) | `Enter` on a file |
| Scroll diff left / right | `H` / `L` |
| Next / prev hunk | `]` / `[` |
| Toggle side-by-side ↔ unified | `\|` (cycles delta pagers; `\` reverse) |
| Open file in Neovim | `e` |

### Commits

| Action | Key |
|--------|-----|
| Commit staged changes | `c` |
| Commit with verbose diff | `C` |
| Amend last commit | `A` |
| Reword commit message | `r` |
| View commit diff | `Enter` on a commit |
| Squash into previous commit | `s` |
| Drop commit | `d` |

### Branches

| Action | Key |
|--------|-----|
| Checkout branch | `Space` |
| New branch | `n` |
| Delete branch | `d` |
| Merge into current | `M` |
| Rebase current onto branch | `r` |
| View branch log | `Enter` |

### Remote

| Action | Key |
|--------|-----|
| Push | `P` |
| Pull | `p` |
| Force push | `shift+P` |

---

## Diffview

> Neovim git-review UI (file panel + side-by-side diffs). Independent of Lazygit
> — use Lazygit to stage/commit, Diffview to review. Open with the `<leader>g`
> mappings below; press `g?` inside any panel for full help.

### When to use which

| Goal | Mapping | Shows |
|------|---------|-------|
| Review the whole branch before pushing / for a PR | `<leader>gr` | Working tree vs merge-base with `main`: committed + staged + unstaged **tracked** changes. **No untracked files** (git can't diff those against a commit). |
| Review before committing | `<leader>gv` | Working tree vs index: unstaged + staged + **untracked new files** (the only view that includes new files). |
| Close the review | `<leader>gV` | — |

### History (shows the actual diff at each change, like `git log -L`)

| Action | Mapping |
|--------|---------|
| File history (follows renames) | `<leader>gH` (normal) |
| History of a selected range | `<leader>gH` (visual) |
| History of the current line | `<leader>gl` |
| Whole-repo history | `<leader>gA` |

### Navigating the file panel

| Action | Key |
|--------|-----|
| Next / prev file entry (move cursor) | `j` / `k` |
| Open diff for selected entry | `<Enter>` / `o` / `l` |
| Open diff for **next / prev** file | `<Tab>` / `<Shift+Tab>` |
| First / last file | `[F` / `]F` |
| Stage / unstage entry | `-` or `s` |
| Stage all / unstage all | `S` / `U` |
| Restore entry (discard changes) | `X` |
| Toggle list ↔ tree view | `i` |
| Refresh | `R` |
| Open commit log panel | `L` |
| Open the file (leave the diff) | `gf` |
| Open file in new split / tab | `Ctrl+w Ctrl+f` / `Ctrl+w gf` |
| Focus file panel | `<leader>e` |
| Help (all keymaps) | `g?` |

### Inside the diff windows

| Action | Key |
|--------|-----|
| Next / prev changed hunk | `]c` / `[c` |
| Switch between base (left) & working (right) | `Ctrl+w h` / `Ctrl+w l` |
| Next / prev file | `<Tab>` / `<Shift+Tab>` |
| Focus / toggle file panel | `<leader>e` / `<leader>b` |

### File-history panel

| Action | Key |
|--------|-----|
| Next / prev commit entry | `j` / `k` |
| Open diff for the commit | `<Enter>` / `o` |
| Open commit details | `L` |
| Copy commit hash | `y` |
