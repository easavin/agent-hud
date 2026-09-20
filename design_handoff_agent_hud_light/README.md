# Handoff: Agent HUD — Light product-analytics restyle

## Overview
Restyle the existing Agent HUD platform (macOS monitor for concurrent Claude Code agents) into the **light product-analytics theme** — frame `3b` in the attached prototype. Warm off-white canvas, flat white cards with 1px warm-grey borders, dark-ink primary buttons and segmented controls, saturated-but-muted semantic colors that pass contrast on white, square-ish 6px radii, no glow, no gradients. Motion is calm and functional.

This is a **restyle of an existing app**: keep the current information architecture and data (agents, flow graph, lanes, stats, thought stream); replace the visual layer.

## About the design files
`Agent HUD.dc.html` + `support.js` is a live HTML prototype. Open it in a browser; the canvas pans/zooms. **Frame 3b** (id `#3b`, section "3", second frame) is the target. Frames 1e / 2a show the same dashboard's regions and interactions in the original neon style — use them for behavior reference (selection, popover, hero tabs Flow/Brain/Loops, progress ring, loop radar), not visuals. The HTML is a reference, not production code.

## Fidelity
High-fidelity: colors, type, radii, strokes and spacing are final. Recreate exactly. Activity glyphs (◐ ⌕ ✎ ▶ ✕ ◦ ◌) are Unicode stand-ins — replace with SF Symbols (`brain`, `magnifyingglass`, `pencil`, `play.fill`, `xmark`, `ellipsis`, `circle.dotted`).

---

## Design tokens

### Color
Surfaces
- `canvas` #F4F3EE — window background
- `header` #FBFAF7 — top bar background
- `card` #FFFFFF — all panels and agent cards
- `card-selected` #FFF8EC — selected agent card fill
- `track` #F1EFE9 — empty bar tracks, lane background
- `chip-amber-bg` #FFF3DD — file chip fill
- `border` #D8D4CB — card and window borders (1px)
- `border-strong` #C9C5BB — control borders (buttons, segmented), chart baseline
- `divider` #E7E4DC — inner card dividers, in-card bar tracks, dashed gridlines

Text
- `ink` #151618 — primary text, primary buttons, selected segments, playhead, popover border
- `mute` #6B7079 — secondary text, axis labels, units
- `on-ink` #FFFFFF — text on ink buttons / red loop pill

Semantic activity (same meaning everywhere; all ≥ 4.5:1 on white)
- thinking #6D3BD9 · reading/searching #1F5FD0 · editing/writing #B8690A · running #1E8A4C · error #D2384A · waiting/idle #8B919B · subagent #0F8B78 (dashed outline)

Model colors (badge border + text; also repo leaderboard bars)
- fable-5.1 #151618 · opus-5 #1F5FD0 · sonnet-5 #B8690A · haiku-4.5 #6B7079

Chart series: input #1F5FD0 · output #B8690A · cache-read #0F8B78 · thinking #6D3BD9. Heatmap #1F5FD0 at opacity .06–.95. Cache-hit number #0F8B78.

### Type
- UI: **IBM Plex Sans** (fallback system-ui). Code/stream/commands: **JetBrains Mono**.
- app title 17/600 · card title 15/600 (hero cards) · panel title 13/600 · agent name 14/600 · body 13/400–500 · secondary 12/400 · small 11/400 · axis/legend 10/400 · big number 26/600 line-height 1 · loop pill 11/600 white · node label 11/600, node sub 10 mute.
- Tabular numerals for all metrics.

### Radius, stroke, spacing
- Radius: window 8 · cards, buttons, segmented, popover 6 · badges 4 · lane track 2, lane segment 1 · bars 1 · file chip 3 · loop pill 3
- Strokes: borders 1px · graph edges 1.5px @ 70% · node ring 2px · sparkline 1.5px · playhead 2px ink · dashed gridlines 1px `2 3` divider
- Spacing: 4/8 grid. Window padding 16 horizontal; body grid gap 12; card padding 12 (agent cards 10/12); card header 40px tall with divider; control height 30 (header buttons), segmented items padding 4/10 (12px) or 2/7 (11px, in-panel).
- No shadows except the popover hard shadow `2px 2px 0 #151618`.

---

## Layout (frame 3b, 1280×800)
Vertical: header 52 · metrics strip 34 · body 592 · thought stream (remaining ≈ 110, margin 0 16 10).

### Header (52, bg `header`, bottom border)
Left: 20×20 ink square r5 with white "A" 11/700 · "Agents" 17/600 · "5 sessions · 4 active" 12 mute.
Right controls (30px tall, r6, 13/500): `Last 60 min ⌄` (white, border-strong) · `+ Filter` (white) · `↻ Refresh` (ink fill, white text).

### Metrics strip (34, padding 10 16 0, 13px mute, numbers 600 ink)
`46.5k tok/min · 3.12M today · $41.27 est. cost · 7 loops (amber) · 12 errors (red)` — right-aligned "Last refreshed a few seconds ago".

### Body grid: `264px | 1fr | 280px`, gap 12, padding 8 16

**Agent cards** (left, gap 8): white card r6, border `border`; padding 10/12, gap 5.
Row 1: name 14/600 · model badge 11/500, padding 1/6, r4, 1px border + text in model color.
Row 2: `⎇ branch` 12 mute, ellipsized.
Row 3: 8×8 square (r2) in activity color + activity word 12/500 in activity color; elapsed 12 mute right.
Row 4: context bar 216×6 r1, track `divider`, fill blue <60% / amber 60–74% / red ≥75%.
Row 5: "context 62% · 1.24M tokens" 11 mute + heartbeat sparkline 72×16, 1.5px in activity color.
Selected: border ink, inner 1px ink ring (`inset 0 0 0 1px`), fill `card-selected`.

**Thinking flow** (center top, 356 tall): header 40 with "Thinking flow · orbit-core" 15/600 + "turn 7" mute, right segmented control Flow / Brain / Loops (selected = ink fill, white text; border-strong 1px, r6). Canvas 688×300.
- Node: r = `10 + 0.9·√(tokens/100)` clamp 10–26; ring 2px in activity color; fill = activity color @ 12%; error fill @ 25% with two white 1.5px crack lines; prompt/result filled ink with white glyph-less face; subagent dashed `3 3` teal r10. Glyph inside (JetBrains Mono, 9–12px). Label 11/600 ink below (y+r+4), sub 10 mute (+14).
- Edges: cubic Bézier, 1.5px @ 70%, color = target node; subagent dashed `3 3`; loop edge red dashed `4 3` curving below with a **loop pill** 28×16 r3 solid red, "×3" 11/600 white.
- File chips off Edit node: 92×16 r3, fill `chip-amber-bg`, 1px amber; filename 10/500 amber, `+42` green, `−17` red; 1px amber connector.
- Popover (selected node): 230 wide, white, 1px ink border, hard shadow 2px 2px 0 ink, r6, padding 8/10: "Bash · failed" 12/600 red + "iteration 3/3" 10 mute; command in JetBrains Mono 11; "4.2s · 1.9k tokens · exit 1" 11 mute; error line 11 red.
- Particles: 3 × 4px ink-green dots (#1E8A4C) along the active edge.

**Activity lanes** (center bottom, 224 tall): header "Activity" 15/600 + "last 60 min" mute, segmented 15m / **60m** / 6h. Lane row 28px: name 12/500 ink; track x96 w560 h16 r2 `track`; segments h16 r1 in activity color at full opacity; prompt ticks 2×4 ink above lane. Dashed gridlines at −45/−30/−15 (`divider`, `2 3`); axis labels 10 mute; playhead 2px ink at x658 with "now" 10/600 below.

**Stats rail** (right, gap 8; each white card r6 padding 12):
1. Token burn — title 13/600 + segmented 1h / **24h** / 7d (11px); stacked area 252×72, series @ 90% opacity (no top line), baseline 1px `border-strong`; legend 10 mute with ■ swatches.
2. Model mix donut 56×56 (stroke 9, 3° gaps, model colors) + legend "■ fable-5.1 38%" (pct bold ink) · Cache hit rate "71%" 26/600 teal, "1.9M of 2.7M input" 11 mute.
3. Tools bar list (Read 412 · Edit 188 · Bash 143 · Grep 97 · Write 31): 52×8 square bars, track `track`, fill blue for Read/Grep, amber Edit/Write, green Bash · Repos leaderboard (lantern 2.05M, orbit-core 1.24M, lumen-ui 612k, willow 340k, sandpiper 88k): 24×8 bars in model color.
4. Activity · 12 weeks — "tokens / day" 11 mute; 12×7 cells 19×8 r1, pitch 21×10, blue at .06–.95.

**Thought stream** (bottom card, padding 6/14): title 13/600 + "Blur thoughts" toggle (26×14 pill, border-strong, `track` fill, 8px ink knob; on = ink fill, knob right). 5 rows JetBrains Mono 11/13, grid `60 | 88 | 80 | 1fr` gap 10: time mute · agent 600 in model color · glyph + activity in activity color · text ink, ellipsized. Blur mode: text `blur(4px)` @ 70%.

### Brain / Loops tabs and progress (behavior from 2a, restyled)
- Brain: same 5-layer node graph; active nodes fill @ 35% + 2px ring, dormant @ 12% and 40% opacity; edges `divider` 1px, hot edges 1.5px in target color; context-window bar 688×6 r1 with segments (system mute, files blue, tool results green, thinking violet), ink 1px compaction tick.
- Loops: radar rings 1.25px dashed `2 3`, amber → #C4531F → red; current ring solid 2px; fail markers r3 white fill + red ring; breakout tangent green dashed; "Interrupt" = ink-outline button.
- Progress ring on cards (28×28, track `divider` 2.5px, arc in model color) with "3/7" 7/600 and "eta ~18m" 11 mute; complete = green, blocked = `waiting`.

---

## Motion (ease-out unless noted; honor Reduce Motion by disabling particles and pulses only)
- Card select: border/fill 150ms. Segmented/tab change: 120ms crossfade of content.
- Context bar / progress arc: width or arc 300ms per update.
- Sparkline: shift 1px / 120ms per token event (no easing).
- Flow particles: 3 × 4px dots, 1.6s linear, stagger .53s, while a tool call is in progress.
- Node enter: scale .8→1 + opacity 0→1, 200ms.
- Loop pill count: scale 1→1.15→1, 200ms on each iteration. Error node: no pulse; ring alternates #D2384A / #F0A3AD every 800ms while looping.
- Lanes scroll left 1px / 6.4s; playhead static.
- Popover: fade + 4px rise, 120ms.
- Thought stream: new row inserts with a 150ms height expand; no cursor blink.
- Refresh button: ↻ spins 360° 600ms once per refresh.

## Data model (unchanged)
`Agent { name, repo, branch, model, activity, tpm, tokensSession, tokensToday, ctxUsed/ctxMax, elapsed, heartbeat[24], loopCount, sameErrorCount, plan{done,total,steps[]}, eta }`. Flow = turn transcript → nodes (prompt, thinking, tool_use, tool_result, subagent) with tokens; loop when the same Edit→Bash pair repeats with identical failure. Sample data: repos orbit-core, lumen-ui, lantern, sandpiper, willow; models fable-5.1, opus-5, sonnet-5, haiku-4.5; 88k–2.05M tokens per session, 3.12M today, 46.5k tok/min, $41.27, 7 loops, 12 errors.

## Implementation notes (SwiftUI)
- Cards: `RoundedRectangle(cornerRadius: 6).fill(.white).stroke(border, 1)`; no material/blur.
- Segmented controls: custom — ink fill on selected segment, 1px `border-strong` outline, no system tint.
- All vector: arcs, cubic paths, rounded rects; glyphs → SF Symbols; fonts IBM Plex Sans (bundle) + JetBrains Mono / SF Mono.
- Contrast: semantic colors chosen for ≥ 4.5:1 on white — do not lighten them for fills; use the 12% / 25% alpha fills instead.

## Files
- `Agent HUD.dc.html` — prototype; target frame `#3b`. Also contains 1e/2a (neon; behavior reference), 3a/3c (other explorations — ignore).
- `support.js` — runtime for the prototype.
