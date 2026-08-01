# Dev Cheatsheet

## tmux

> Prefix is `Ctrl+b` (tmux's default). `Ctrl+a` belongs to **herdr** — tmux
> deliberately yields it, because herdr has no send-prefix action and a tmux
> session started inside a herdr pane would otherwise be unreachable.

### Splits & Panes

| Action | Key |
|--------|-----|
| Split vertically (pane right) | `Ctrl+b \|` |
| Split horizontally (pane below) | `Ctrl+b -` |
| Switch pane | `Ctrl+b h/j/k/l` |
| Close current pane (no prompt) | `Ctrl+b x` |
| Zoom pane (toggle fullscreen) | `Ctrl+b z` |
| Resize pane | `Ctrl+b H/J/K/L` (repeatable) |

### Windows (tabs)

| Action | Key |
|--------|-----|
| New window (in current path) | `Ctrl+b c` |
| Next window | `Ctrl+b n` |
| Previous window | `Ctrl+b p` |
| Pick window by number | `Ctrl+b 1–9` |
| Rename window | `Ctrl+b ,` |
| Close window | `Ctrl+b &` |

### Sessions

| Action | Key |
|--------|-----|
| Open session picker (sesh + fzf) | `Ctrl+b T` |
| Switch to last session | `Ctrl+b S` |
| New session | `tmux new -s name` |
| Detach | `Ctrl+b d` |
| List sessions | `tmux ls` |
| Attach to session | `tmux attach -t name` |

> `Ctrl+b S`, not the stock `Ctrl+b L` — `L` is rebound to "resize pane right".
> Worth having with one session per worktree and `detach-on-destroy off`.
>
> Outside tmux, `s` (a zsh function) opens the same sesh picker with plain fzf,
> so it works before a tmux server exists.

---

## Git worktrees (git + tmux + sesh)

> Worktrees are **nested directories** named `<parent>/<repo>/<branch-slug>` (e.g.
> `into.care/portal/ICP-1234-desc`), where the slug is the branch with `/` → `-`.
> Each gets a tmux session named `<repo>/<branch-slug>` (e.g.
> `portal/ICP-1234-desc`) — slashes are safe because every `tmux -t` call uses the
> `=` exact-match prefix. Managed by the `wtc` / `wtr` zsh functions over plain
> `git worktree`; `wth` / `wthr` are the herdr-backed twins. `sesh` (`Ctrl+b T`)
> is the picker for hopping between tmux sessions.

### Mental model

- The main clone (`portal`, `intocare`) is **itself a worktree**, pinned to a branch — keep it on `main` so new worktrees branch off the right base.
- A branch can be checked out in **only one worktree at a time**.
- `git worktree` **never changes your shell's cwd**, and `wtr` **refuses to delete the session you're in** — so the old drift/self-kill surprises can't happen.

### Workflow

| Action | Command |
|--------|---------|
| Start a ticket (create worktree + enter its session) | `wtc ICP-1234-desc` — run from anywhere inside the repo |
| Hop between worktrees | `Ctrl+b T` (sesh picker) → attach to its session |
| List worktrees | `git worktree list` |
| Rebase current branch onto latest main | `wtrebase` — fetches, rebases onto `origin/<main>` (auto-stashes), and fast-forwards the main worktree too if it's clean & on main |
| Remove a worktree (+ session, + branch if merged) | `wtr ICP-1234-desc` — from your **main** session, not from inside it |
| Remove the worktree you're near | `wtr` (no arg → current branch) — must be run from **another** session |
| Bulk-delete branches whose PRs have merged | `gh poi` |

- ✅ `wtc` drops you straight into the new worktree's session (switches client if already in tmux, attaches if not).
- ✅ `wtr` from your base (`main`) session; it kills the session and deletes the branch with a safe `git branch -d`. Squash/rebase-merged branches have no ancestry to check, so `-d` refuses them and `wtr` keeps them — run `gh poi` to sweep those up.
- ✅ **`gh poi`** ([seachicken/gh-poi](https://github.com/seachicken/gh-poi), `gh extension install seachicken/gh-poi`) is the branch cleanup. It asks the **GitHub API** whether each branch's PR merged, so squash and rebase merges are detected definitively rather than guessed from "the upstream disappeared". It protects the default branch and anything with unpushed commits. `gh poi --dry-run` to preview.
- ❌ `wtr` while standing inside the worktree/session you're deleting — it refuses, in tmux **and** outside it.

### herdr variants

`wth` / `wthr` mirror `wtc` / `wtr` against herdr workspaces instead of tmux
sessions, using the same path convention. Both require `jq`. `--force` discards
a dirty checkout and works on either side (`wtr --force`, `wthr --force`).

herdr's own prefix is `Ctrl+a` (tmux deliberately yields it — see the top of
this file):

| Action | Key |
|--------|-----|
| Workspace picker | `Ctrl+a w` |
| Previous / next workspace | `Ctrl+a k` / `Ctrl+a j` |
| Previous / next agent | `Ctrl+a K` / `Ctrl+a J` |

> Don't close a repo-parent workspace to tidy up — it cascades and closes every
> linked-worktree workspace under it.

### Daily workflow (from opening Ghostty)

> **Mental model:** `sesh` / `Ctrl+b T` = pick a main clone + hop between anything · `wtc` = start/enter a ticket worktree · `wtr` = tear one down · `wtrebase` = stay on top of main. Sessions do auto-restore across reboots (see the note at the end), but these commands rebuild any of them deterministically.

1. **Open Ghostty** → plain shell, no tmux yet. Jump into a project with **`Ctrl+b T`** → pick `portal` / `intocare` / `dotfiles` (or `sesh connect portal`). This starts tmux fresh and drops you in that repo's main-clone session. Keep main clones on `main`.
2. **Start a ticket** — from anywhere inside the repo: `wtc ICP-1234-desc`. Creates (or reuses) the worktree and drops you into its `<repo>/ICP-1234-desc` session.
3. **Hop around** — `Ctrl+b T` anytime to switch sessions; `Ctrl+b d` to detach (session keeps running).
4. **Stay current** — from inside a ticket session: `wtrebase` (rebase onto `origin/main`, auto-stash, fast-forward main clone too).
5. **Finish a ticket** — once merged, from a **different** session (e.g. your main clone, not from inside the worktree): `wtr ICP-1234-desc`. Removes worktree + session, deletes the branch only if merged.

> **Session resurrection is ON.** `tmux-continuum` auto-saves every 15 min and
> `@continuum-restore 'on'` (see `tmux/tmux.conf`) reopens the last save when the
> tmux server starts fresh. Manual controls: save `Ctrl+b Ctrl+s`, restore
> `Ctrl+b Ctrl+r`.
>
> A session torn down by `wtr` does **not** come back: `wtr` re-runs resurrect's
> `save.sh` after killing it, so the snapshot no longer lists a session pointing
> at a deleted directory.

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
| Same, partial match (no word boundaries) | `g*` |
| Jump to the matching bracket | `%` |
| Flash jump (leap anywhere on screen) | `s` then 2 chars |
| Back / forward (jump list) | `Ctrl+o` / `Ctrl+i` |
| Open link / path under cursor in system handler | `gx` |
| Open the file whose path is under the cursor | `gf` |

**Marks** — drop a bookmark, come back to it later:

| Action | Key |
|--------|-----|
| Mark, file-local | `m` + **lowercase** letter (e.g. `ma`) |
| Mark, reachable from any file | `m` + **UPPERCASE** letter (e.g. `mA`) |
| Jump back, exact line & column | `` ` `` + the letter (`` `a ``) |
| Jump back, first non-blank of the line | `'` + the letter (`'a`) |
| List all marks | `:marks` |

### File & Buffer Navigation

| Action | Key |
|--------|-----|
| Open file explorer tree (snacks) | `<leader>e` |
| Focus file explorer | `<leader>E` |
| mini.files browser (current file) | `<leader>fm` |
| mini.files browser (cwd) | `<leader>fM` |
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
| Clear search highlight | `Esc` (or `<leader>ur` to also redraw) |
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

The longhand version of the same thing, if `cgn` slips your mind: `*` `N`
(`*` jumps ahead, `N` comes back to where you started) → `ciw` + replacement +
`Escape` → then `n` `.` `n` `.` … `n` moves to the next match, `.` re-runs the
change. `cgn` is the shorter form because it folds the `n` into the repeat.

Or delete all at once after `*`:
- `:%s///g` — empty pattern reuses the `*` search, replaces all with nothing

**Refactor across every file in the project**, when `<leader>sr` (grug-far)
isn't what you want:

```vim
:vim /pattern/ **        " :vimgrep — populate the quickfix list from every file under cwd
:copen                   " inspect the hits before touching anything
:cdo s/old/new/ge | update
```

- `:cdo` runs the command once **per quickfix entry**, not per file.
- The **`e`** flag matters because of that. Two matches on the same line are two
  entries; the first `s/…/…/g` already fixes both, so the second entry's `:s`
  finds nothing, raises `E486: Pattern not found`, and aborts every remaining
  entry. `e` swallows that and lets the run finish.
- `| update` writes each buffer as it goes. **`:cdo` alone does not save
  anything** — the substitution happens in memory and the file on disk is
  unchanged.
- `:cfdo` is the per-*file* variant, which is what you want with `%s`:
  `:cfdo %s/old/new/ge | update`.

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
| Reselect the last visual selection | `gv` |
| Move current line or selection down / up | `Alt+j` / `Alt+k` (Mac: `Option+j` / `Option+k`) |
| Join line below onto this one (with a space) | `J` |
| Join with **no** space inserted | `gJ` |
| Paste **before** the cursor | `P` (after is `p`) |
| Re-indent the whole file | `gg=G` |
| Delete the word behind the cursor, in insert mode | `Ctrl+w` |

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
| Paste the 3rd-most-recent **delete** | `"3p` |
| Yank to the **system** clipboard | `"+y` (e.g. `"+yy`, or `"+y` over a visual selection) |
| Paste from the system clipboard | `"+p` |
| Paste over selection, keep your yank | `<leader>p` (visual) |
| Delete without saving to a register (black hole) | `<leader>d` |
| Explicit black-hole delete | `"_d` (e.g. `"_dd`) |
| Yank current file's relative path to clipboard | `<leader>yp` |
| Yank current file's absolute path to clipboard | `<leader>yP` |
| See what every register holds | `:registers` |

> `"1`–`"9` are the **delete ring**, newest first — `"1p` is your last delete,
> `"3p` the one two before that. Yanks never enter it; they go to `"0`.
> Caveat: only deletes of a line or more land in the ring. A *small* delete
> (`dw`, `x`, `de` — anything inside one line) goes to `"-` instead, so
> `"-p` is the one you want after a `dw`.

**Macros** — record a sequence of edits once, replay it:

| Action | Key |
|--------|-----|
| Start recording into register `h` | `qh` … then do the edits … then `q` |
| Replay it once | `@h` |
| Replay it 20 times | `20@h` |
| Replay whatever you last replayed | `@@` |
| Inspect / edit a recorded macro | `"hp` pastes it onto a line; edit it, then `0"hy$` puts it back |

> Pick any lowercase letter as the register — `h` is just a habit. Recording
> into an UPPERCASE letter (`qH`) **appends** to that macro instead of replacing it.

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
| Diff current file (hunks picker) | `<leader>gd` |
| **Diff file vs merge-base with main** (editable) | `<leader>gr` |
| Diff file vs index (editable) | `<leader>ghd` |
| Diff file vs `HEAD~` (editable) | `<leader>ghD` |
| History: current file | `<leader>gf` |
| History: whole repo | `<leader>gl` |
| Blame current line | `<leader>gb` |
| Toggle deleted lines inline (gitsigns) | `<leader>gtd` |
| Toggle word diff (gitsigns) | `<leader>gtw` |

> The three diff mappings open Neovim's **native** side-by-side diff (gitsigns
> `diffthis`): the left window is the base and is read-only, the right window is
> your real buffer — so you can **edit against the diff** and `:w` as usual.
> `]c` / `[c` jump hunks, `do` / `dp` obtain/put a change, `:q` on the left
> window closes the diff. For a read-only whole-branch review, use
> `git diff main...HEAD` in the shell (delta renders it side-by-side) or a
> fullscreen Lazygit diff.

### Misc

| Action | Key |
|--------|-----|
| Command palette | `<leader>:` |
| Open terminal (root dir / cwd) | `<leader>ft` / `<leader>fT` |
| Toggle terminal | `Ctrl+/` |
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
| Scroll diff up / down (without focusing it) | `K` / `J` or `Ctrl+u` / `Ctrl+d` |
| **Focus the diff panel** | `0` |
| **Zoom** — cycle normal → half → fullscreen | `+` (`_` reverses) |
| Next / prev hunk | `]` / `[` |
| Toggle side-by-side ↔ unified | `\|` (cycles delta pagers; `\` reverse) |
| Open file in Neovim | `e` |

> Zoom only enlarges the **focused** panel: press `0` first, then `+`. With a
> side panel focused instead, half-screen *shrinks* the diff and fullscreen
> hides it entirely. `Esc` returns to the side panel — press `_` back to normal
> first, or the diff will be hidden.

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
| Pull | `p` |
| Push | `P` (offers force-push if the remote has diverged) |
| Fetch | `f` |
