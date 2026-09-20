# Handoff: Agent HUD — Terminal / TUI restyle

## Overview
Restyle the existing Agent HUD platform (macOS monitor for concurrent Claude Code agents) into the **terminal-like design** — frame `3a` in the attached prototype. Everything is monospace text on near-black, panes are 1px-bordered boxes with a title sitting on the top-left of the border, charts are made of block characters, and motion steps cell-by-cell instead of tweening. No gradients, no glow, no rounded chrome.

This is a **restyle of an existing app**: keep the current information architecture and data (agents, flow graph, lanes, stats, thought stream); replace the visual layer.

## About the design files
`Agent HUD.dc.html` + `support.js` is a live HTML prototype. Open it in a browser; pan/zoom the canvas. **Frame 3a** (id `#3a`, top section "3") is the target. Frames 1e / 2a show the same dashboard's regions and interactions in the original neon style — use them only to understand behavior (selection, popover, tabs), not for visuals. The HTML is a reference, not production code.

## Fidelity
High-fidelity: colors, type size, line height, character glyphs and pane geometry are final. Reproduce with real text rendering (a monospace font grid) — do not rasterize.

---

## Design tokens

### Color
- `bg` #0B0D10 — window and pane background (no panel fills; panes are outlines only)
- `border` #2B303A — 1px pane borders; also horizontal rules inside panes
- `border-outer` #23272F — window frame
- `ink` #E8E8E8 — primary text, agent names, numbers
- `ink-2` #C9CCD3 — thought-stream body text
- `mute` #7A8290 — pane titles, column headers, units, hints, axis labels
- `row-selected` #161B24 — selected table row background (full-width)
- `err-bg` #2A1216 — background behind an inline failed-tool token

Semantic activity (text/glyph/block color — identical meaning everywhere)
- thinking #D18BFF · reading/searching #5FD7FF · editing/writing #FFC145 · running #7CFF9E · error #FF6B6B · waiting/idle #5C6470 · subagent #4FE3C1
- "now" marker / live indicator: #5FD7FF (cyan) · live dot: #7CFF9E

Model text colors (used for agent names in the thought stream)
- fable-5.1 #E8E8E8 · opus-5 #8FB4FF · sonnet-5 #FFD98A · haiku-4.5 #9AA3B2

Chart fills: token-burn sparklines use series colors (input #5FD7FF, output #FFC145, cache-read #4FE3C1, thinking #D18BFF); model-mix, repo bars, heatmap #5FD7FF; tool bars #FFC145; cache-hit bar #4FE3C1.

### Type
One font: **JetBrains Mono** (fallback SF Mono / Menlo). Everything is 12px / 16px line-height, regular 400. Bold 700 only for the app name and the `×3` loop counter. Pane titles 12/600 in `mute`. No uppercase transforms, no letter-spacing — alignment comes from padding strings to fixed column widths (`padEnd` / `padStart`).

### Character set
- Borders: CSS 1px lines (not box-drawing) for panes; box-drawing inside content: `─ │ ┌ └ ├ ┐ ┘ ▶ ◀ ╌ ┃`
- Blocks: `█` lane segments · `▇` bars · `░` empty bar track · `░ ▒ ▓ █` heat levels · `▁▂▃▄▅▆▇█` sparklines
- Glyphs: `■` prompt/result · `◐` thinking · `⌕` read/search · `✎` edit · `▶` run · `✕` error · `◌` subagent · `▸` selected row · `●` live / particle
- Keyboard hints in brackets: `[f]low [b]rain [l]oops`, `[p] blur: off`

### Spacing
- Window: 1280×800, radius 8, 1px `border-outer`, padding 8px 12px, gap 8 between panes
- Pane: 1px `border`, padding 20px 10px 8px (20 top clears the title), `overflow: hidden`
- Pane title: absolute, left 8, top 0, line-height 16, padding 0 4, text `─ title ─`; optional right-aligned hint at right 8
- Lines: 16px; lanes 18px; heat rows 13px

---

## Layout (frame 3a, 1280×800)
Header line (16px): `agent-hud v0.4 ── 5 sessions ── 46.5k tok/min ── 3.12M today ── $41.27 ── loops 7 errors 12` left; `14:32:07 ● live` right. Bold app name; numbers `ink`, words `mute`; loops amber, errors red.

Body grid: columns `1fr 296px`; rows `118px 1fr 150px`; gap 8. Stats pane spans all three rows in column 2.
Footer: thoughts pane, 100px tall.

### ─ agents ─ (row 1, col 1)
Header row (mute): `  NAME         MODEL       STATUS     CTX          TOK       UP   HEARTBEAT`
One line per agent, padded columns: `▸`(cyan, selected only) · name padEnd 11 · model padEnd 10 (mute) · status padEnd 9 (activity color) · ctx bar 10 cells `█` filled / `░` empty (cyan <60%, amber <75%, red ≥75%) · tokens padStart 6 · elapsed padStart 7 · heartbeat 12 sparkline chars in activity color (flat `▁` when waiting). Selected row: bg `row-selected`.

### ─ flow · orbit-core · turn 7 ─ (row 2, col 1) · right hint `[f]low [b]rain [l]oops`
ASCII tree, one node per line, indent 2 cells per depth. Connectors `└─▶ ├─▶`; subagent branches use dashed `╌╌▶` in teal and merge back with a `┐ … ┘` return line; loops draw as a box return `──┐ / ▲ / └──┘` back to the Edit node with a bold red `×3` after the failed node. Node = glyph + tool name in activity color, then the argument in `ink`, then token count in `mute`. Failed tool: `✕ failed exit 1` red on `err-bg`. File chips: `[retry.py +42 −17]` — brackets/name amber, `+` green, `−` red. Result: `■ result done`.
Below a 1px rule: selected-node detail, 3 lines — `selected ▸ Bash · failed  pytest tests/test_retry.py -x  4.2s · 1.9k tok · exit 1 · iter 3/3`, the error message (mute), and the particle line `● ● ●` (green).

Sample tree (colors per rules above):
```
■ prompt fix flaky retry
  └─▶ ◐ thinking 8.4k
        ├─▶ ⌕ Read retry.py
        ├─▶ ⌕ Grep "backoff"
        ├╌╌▶ ◌ subagent explore tests ╌╌▶ ◌ 2.1k ╌╌╌╌╌╌┐
        └─▶ ◐ thinking 14.2k ◀──────────────────────────┘
              └─▶ ✎ Edit retry.py  [retry.py +42 −17] [test_retry.py +8 −3]
                    ├─▶ ▶ Bash pytest ──▶ ✕ failed exit 1 ──┐ ×3
                    │   ▲                                   │
                    │   └───────────────────────────────────┘
                    └─▶ ▶ Bash pytest ✓ ──▶ ■ result done
```

### ─ lanes · 60m ─ (row 3, col 1)
One 18px line per agent: name padEnd 11, then exactly **90 cells** of `█` colored by activity (segments computed from cumulative cell boundaries so every row sums to 90), then `┃` in cyan as the now-marker. Axis line below in `mute`: `-60m` at cell 0, `-45m` at 22.5, `-30m` at 45, `-15m` at 67.5, `now` (cyan) at 90. User prompts: replace the cell with `▏` in `ink`.

### ─ stats ─ (col 2, rows 1–3), one column, gap 10, line-height 15
1. `token burn · 24h            [1h] 24h  7d` then 4 rows: series name padEnd 11 + 24 sparkline chars in series color.
2. `model mix` — 4 rows: model padEnd 10 · 20-cell `▇/░` bar (cyan) · pct padStart 3.
3. `cache hit  ▇▇▇▇▇▇▇▇▇▇▇▇▇▇░░░░░░  71%` (teal) · `est. cost  $41.27  +$3.10/h`.
4. `tools` — 5 rows: name padEnd 6 · 14-cell amber bar · count padStart 4.
5. `repos` — 5 rows: repo padEnd 11 · 10-cell cyan bar · tokens padStart 6.
6. `activity · 12 weeks` — 7 rows × 12 cells `░▒▓█` (cyan) separated by a space; row = weekday, column = week; level by tokens/day quartile.

### ─ thoughts ─ (footer) · right hint `[p] blur: off`
5 lines, 15px: time (mute) · agent padEnd 11 (model color) · activity glyph (activity color) · text (`ink-2`), ellipsized. Blur mode: text `blur(4px)` @ 70% opacity. Cursor: `▌` blinking at the end of the newest line.

---

## Interaction
- `↑/↓` or click selects an agent row (▸ + `row-selected` bg); flow/lanes/thoughts filter to it where applicable.
- `f / b / l` switch the hero pane (flow tree / brain / loops). Brain and loops in this style: brain = indented layer lists with token counts (`ctx files  retry.py 18.4k  ████░░`); loops = iteration table (`iter 1  42s  2.1k  ✕ same error`).
- Click a node line → selected detail block updates.
- `p` toggles thought blur. Range hints `[1h] 24h 7d` toggle burn range.
- Hover a lane cell shows `14:07 · editing · retry.py` in the pane title's right slot.

## Motion (stepped, never tweened)
- Particles: 3 `●` glyphs walk the active edge one cell every 130ms (wrap).
- Lanes: shift left one cell every 40s (90 cells = 60 min); `┃` stays fixed.
- Heartbeat: sparkline shifts one char left per token event.
- Live dot `●` in header toggles between #7CFF9E and #2B303A every 1s (steps).
- Error pulse: the failed token's `err-bg` alternates #2A1216 / #3A1A20 every 600ms while a loop is active.
- Thought cursor `▌` blinks 1s steps(1); new lines push older lines up instantly.
- Selection and tab changes: immediate, no transition.
- Honor Reduce Motion: stop particles and blinks; keep data updates.

## Data model (unchanged from current platform)
`Agent { name, repo, branch, model, activity, tpm, tokensSession, tokensToday, ctxUsed/ctxMax, elapsed, heartbeat[12], loopCount, sameErrorCount }`; flow = turn transcript → nodes (prompt, thinking, tool_use, tool_result, subagent) with tokens; loop detected when the same Edit→Bash pair repeats with identical failure text. Sample data used in the prototype: repos orbit-core, lumen-ui, lantern, sandpiper, willow; models fable-5.1, opus-5, sonnet-5, haiku-4.5; 88k–2.05M tokens per session, 3.12M today, 46.5k tok/min.

## Implementation notes
- Build on a character grid: fixed font-size 12 / line-height 16 and `white-space: pre`; align with padding strings, not pixel offsets. In SwiftUI: `Text` with `.monospaced()` and `.fixedSize()`, or a `Canvas` that draws glyph cells.
- Compute lane cells from cumulative boundaries (`end_i = round(t_i / 60min × 90)`), not per-segment rounding, so rows always sum to 90.
- Pane title is drawn inside the border (top:0), not straddling it — avoids clipping.
- Never use glow/shadows; contrast comes from color on #0B0D10 (all semantic colors ≥ 7:1).

## Files
- `Agent HUD.dc.html` — prototype; target frame `#3a` (section 3, first frame). Also contains 1e/2a (neon original, behavior reference), 3b/3c (other style explorations — ignore).
- `support.js` — runtime for the prototype.
