# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Boonkeeper** is a World of Warcraft **Classic Era** addon written in **Lua**. It shows how much
buff room is left on the people you are about to heal, so a reflex Renew never knocks somebody's
world buff off. Origin: a request from Krydon [MLWD], healing Naxxramas without raid frames.

- **Stack:** Lua 5.1 (WoW runtime), Blizzard FrameXML API. No XML, no libraries, no build step — the
  game compiles the Lua at load and you iterate with `/reload`.
- **Manifest:** `Boonkeeper.toc`, `## Interface: 11509` (Classic Era). Era only on purpose: the 32/16
  caps and the world-buff economy that make this addon worth having are Classic facts. Other
  flavours arrive as extra `.toc` files over the same file list, never as a fork — the flavour branch
  is confined to `BoonkeeperCompat.lua`.
- **SavedVariables:** `BoonkeeperDB`.

## ⭐ The one thing this addon must never do

**Never show a number it cannot stand behind.** Blizzard only serves full aura data for you and your
party/raid members, and how much of another unit's list actually arrives is a question the
documentation does not settle. A truncated list reported as a count is a confident lie at the exact
moment somebody is deciding whether to cast — which is worse than no addon. An unreadable unit
returns `nil` from `BoonkeeperScan`, `Core.Assess` reports `known = false`, and the display shows
`?`. Keep that path intact through every change.

## The Process — NON-NEGOTIABLE

RED → GREEN → REVIEW → COMMIT, one item per commit.

The deciding is pure, so most of the cycle runs offline:

1. **RED** — write the failing test in `Tests/` first (`pwsh -File Tests/run-all.ps1`), or, for
   client-only behaviour, state the expected in-game behaviour and confirm it does NOT happen yet.
2. **GREEN** — the minimum Lua to make it pass.
3. **REVIEW** the diff, fix the findings, re-verify green.
4. **COMMIT** — one behaviour per commit. Then propose the next item and wait.

Pull anything that makes a decision into `BoonkeeperCore.lua` (or another pure module) so it can be
exercised outside the client. Frame and event wiring stays thin — that part is only ever
compile-verified by `Tests/load_test.lua` until somebody logs in.

## Common Commands

```
pwsh -File Tests/run-all.ps1     # every pure-logic test; the gate
lua Tests/core_test.lua          # one file (run from the project root)
./deploy.ps1                     # copy into the Classic Era AddOns folder
/reload                          # in the client
/boon probe                      # dump what aura data this client actually gives us
```

- **Errors:** `/console scriptErrors 1`, or an error addon (BugSack), while developing.

## Code Style

- Locals over globals (`local function ...`); only expose globals the `.toc` must reference by name,
  and prefix any unavoidable global with the addon name.
- 4 spaces, ~110 columns, small functions.
- **English** for all strings, comments and docs. **UTF-8**, **LF** line endings.
- Comments say WHY. A comment that restates the line above it is noise; a comment naming the failure
  a line prevents is the reason the line survives the next refactor.

## Project Document Layout

`Process/` (Backlog.md, Bugs.md, Archive.md, ship-log.json), `Research/`, `Design/` — all gitignored,
because this repo is public. The addon's own Lua and `.toc` live at the root so the game can load the
folder directly.

## Standing orders

- **Eye-verify in the WoW client from more than one state — a single screenshot is not sign-off.**
  Check the changed UI under different conditions (unit readable vs not, near cap vs empty, different
  UI scale) with a deliberate visual-defect scan before calling it verified.
- **Re-read this `CLAUDE.md` periodically** — in a long session, or after a context compaction, so
  the Process and the standing rules do not drift out of context.
- **The agent commits; the maintainer always pushes.** Never run `git push` / `gh repo create --push`.
  Repo creation, making a repo public, and history rewrites stay confirm-first.
