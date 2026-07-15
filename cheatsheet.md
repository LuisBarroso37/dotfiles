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
| Diff current file | `<leader>gd` |

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
