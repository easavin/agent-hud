# Handoff: Agent HUD — macOS monitor for AI coding agents

## Overview
Agent HUD is a native macOS (SwiftUI) always-on-top monitor for 3–8 concurrent Claude Code sessions. It is to agents what a CPU/GPU monitor is to hardware: a small corner widget (320×320, with a 160×160 mini) that expands into a 1280×800 mission-control dashboard. A glance tells you who is thinking, who is stuck in a loop, and how fast tokens burn.

## About the Design Files
`Agent HUD.dc.html` (+ `support.js`) is a **design reference built in HTML/SVG** — a live prototype of the intended look, data model and motion. It is **not** production code. Recreate every frame natively in SwiftUI (Canvas / Shape / Path / TimelineView, `.blur`, `.shadow`), following the exact values below. Open the HTML in a browser to see it live; the canvas pans/zooms. Frame ids (1a, 1b … 2c) are referenced throughout this document.

## Fidelity
**High-fidelity.** Colors, type sizes, stroke widths, spacing and motion are final. Recreate pixel-accurately. Only the activity glyphs (◐ ⌕ ✎ ▶ ✕ ◦) are Unicode stand-ins — replace with SF Symbols (`brain`, `magnifyingglass`, `pencil`, `play.fill`, `xmark`, `ellipsis`).

## Frames
| id | frame | size |
|----|-------|------|
| 1a | Compact widget · busy (4 active) | 320×320 |
| 1b | Compact widget · all idle | 320×320 |
| 1c | Compact widget · alert (lantern looping, red pulse) | 320×320 |
| 1d | Mini widget | 160×160 |
| 1e | Expanded dashboard · Flow view | 1280×800 |
| 1f | Component sheet | — |
| 2a | Expanded dashboard · Brain view + progress rings + loop radar | 1280×800 |
| 2b | Loop radar · expanded ("Loops" hero tab) | 400×320 |
| 2c | Progress ring · card hover / detail | 300×320 |

---

## Design Tokens

### Color
Base
- `bg` #05070D — window base. Widgets/dashboard use a radial fill: `radial-gradient(130% 90% at 50% 0%, #0B1020 0%, #05070D 72%)`
- `panel` #0B1020 @ 55% alpha — glass panels (`rgba(11,16,32,.55)`); `.6` for unselected cards
- `hairline` rgba(124,160,255,.16) frames / `.14` panels & cards / `.12` dividers
- `ink` #E6ECFF — primary text
- `ink-2` #C7D0E8 — thought-stream body text
- `mute` #7C8AA8 — labels, secondary
- `grid` rgba(124,160,255,.06) 16px grid (widget) / `.045` 32px grid (dashboard), masked by a radial fade so it only shows near the top-center

Semantic activity (must be identical everywhere)
- `thinking` #B36BFF
- `reading / searching` #2FD4FF
- `editing / writing` #FFB020
- `running commands` #3DFF7A
- `error / failed tool` #FF3B5C
- `waiting / idle` #4A5568
- `subagent` #17D4B0 (outline only, dashed)
- loop-radar intermediate: #FF7A45 (between amber and red)
- error pill fill: #2A0A14

Model accent rings (desaturated so they never compete with activity colors)
- fable-5.1 #F4F7FF · opus-5 #9FB4FF · sonnet-5 #F5D08A · haiku-4.5 #8FA3B8

Glow recipe: `drop-shadow(0 0 6px <color>)` on active strokes; 8px for active brain nodes; 10px for error nodes; 2→12px animated for the error pulse. Selected-card glow: `0 0 24px rgba(179,107,255,.18)` + inner 1px `rgba(179,107,255,.25)`.

### Type — JetBrains Mono (SF Mono acceptable), tabular numerals everywhere
- display 26 / 600 / −2% tracking (widget tok/min)
- number 20 / 600 / −2% (cost, loop count, mini uses 20)
- title 12 / 600 (agent name)
- body 11 / 500 (widget row name), 10 / 400 secondary (branch, ticker, stream)
- label 9 / 500 / +14% / uppercase (section labels)
- micro 8 / 400 / +10% / uppercase (badges, legends, chips)
- 7 / 600 inside 28px progress ring; 6 / +10% "STEPS" in 56px ring

### Spacing & radius — strict 4/8 grid
Radii: 16 widget · 14 mini · 12 dashboard window · 10 panel & agent card · 8 badges, chips, popover · 6 toggle chips · 4 file chips, bars, thin tracks · 2 lane segments, heat cells.
Padding: widget 16 · dashboard body 8, panels 8–10 · card 10/12 (2a: 8/12).
Shadows: window `0 0 0 1px rgba(0,0,0,.7), 0 12–20px 40–60px rgba(0,0,0,.5–.6), inset 0 1px 0 rgba(255,255,255,.04)`.

---

## Frame specs

### 1a / 1b / 1c — Compact widget 320×320
- Top-left label "AGENT HUD" 9/500 +14% mute at (16,12). Top-right status: 6px dot with 8px glow + text: busy "4 ACTIVE" green · idle "ALL QUIET" slate · alert "1 LOOPING" red.
- **Reactor gauge** centered at (160, 92): track circle r58 stroke 8 `rgba(124,160,255,.10)`; faint outer circle r68 1px @ 6%.
  - Segments: one per agent, `360/n` degrees each, 10° gap, stroke 8, round caps, starting at 12 o'clock clockwise. Color = current activity. Opacity = `0.45 + 0.55·(tpm/maxTpm)`; waiting = 0.3, no glow. Active segments get 6px glow.
  - Inner dashed ring r46, 1px `rgba(230,236,255,.22)`, dash `2 6`, rotating.
  - Sweep arc r46, 60° long, stroke 1.5 round caps, 4px glow — cyan when busy, red in alert, slate when idle; rotates with the dashed ring.
  - Center: tok/min (display 26) · "TOK/MIN" 8/+14% mute · "today 3.12M" 10 mute with ink number. Idle shows "0".
- **Agent rows** start at y=160, 5 rows × 24px, grid `8 | 92 | 72 | 76` gap 8, padding 0 16: 6px status dot (6px glow), repo name 11/500 ink, heartbeat sparkline 72×14 1px stroke in activity color @ 85%, right-aligned glyph + activity word 9/+8% uppercase in activity color. Waiting rows at 40% opacity.
- **Thought ticker** bottom: 16px margins, 24px tall, 1px top hairline @ 12%, text 10px colored by activity of the most active agent (busy violet, idle mute, alert red). Horizontally masked 5% at both edges. Copy examples:
  - busy: `orbit-core ▸ thinking: "the race is in the retry handler — the backoff timer fires before the mutex releases, so the second attempt reads stale state…"`
  - idle: `all quiet ▸ 5 sessions waiting for input · last activity 14m ago`
  - alert: `lantern ▸ error ×4: pytest exit 1 — AssertionError in test_cache::test_warm_hit — retrying edit…`

### 1d — Mini 160×160
Ring center (80,74) r50 stroke 6; dashed ring r40; sweep 60° cyan; number 20/600 + "TOK/MIN" 7px; footer 9/+12% "4 active · 5 sessions" (active count green). Same segment data and motion as compact.

### 1e — Dashboard 1280×800 (Flow view)
Layout: header 40 · body 632 = grid `264 | 704 | 296`, gap 8, padding 8 · thought stream 128 (flex remainder).
- **Header**: "AGENT HUD" 11/700 +16% · "MISSION CONTROL" 9 mute · center metrics (12/600 ink numbers + 10 mute units): 46.5k tok/min · 3.12M today · $41.27 est. · 4/5 active (green) · right: clock 10 mute + breathing green dot.
- **Left rail — agent cards** (5): pad 10/12, r10, gap 6. Row 1: name 12/600 + model badge (8/+10% uppercase, 1px border & text in model color, r8, pad 2/6). Row 2: `⎇ branch` 10 mute. Row 3: status dot + activity word 9/+10% uppercase in activity color; elapsed 9 mute right. Context bar 216×4 r2: track `rgba(124,160,255,.12)`, fill cyan <60%, amber 60–74%, red ≥75%. Row 5: "ctx 62% · 1.24M" 9 mute (numbers ink) + heartbeat 88×18. Selected card: border `rgba(179,107,255,.55)`, fill `rgba(179,107,255,.06)`, glow above. Unselected: hairline .14, fill panel .6.
- **Center top — Thinking Flow graph** panel 704×376, pad 8, title row 24 with legend (dots per activity, "◌ subagent"). Canvas 688×322.
  - Node r = `10 + 0.9·√(tokens/100)` clamped 10–26, stroke 1.5, fill = color @ 12%, halo circle r+8 @ 9%, glow 6px. Glyph inside (12px if r≥19 else 9px). Label 9/+6% ink at y+r+4; sub 8 mute at +14.
  - Prompt & result nodes: filled `rgba(230,236,255,.9)`, no glow. Error node: fill red @ 25%, glow 10px, two dark (#05070D) 1.5px "crack" polylines across it. Subagent nodes: teal, dashed `3 3`, r10.
  - Edges: cubic Bézier from source right edge to target left edge, control x at midpoint; 1.25px @ 55%, color = target node. Subagent edges dashed `3 3`. Loop edge (fail → back to Edit): red dashed `4 3` @ 70% curving below, with a `×3` pill (28×14 r7, fill #2A0A14, 1px red, 6px glow, 9/600 red) at the apex.
  - File chips hang off the Edit node: 92×16 r4, fill amber @ 12%, 1px amber; filename 8 amber, `+42` green, `−17` red; 1px amber connector.
  - Selected-node popover (204 wide, pad 8/10, r8, fill `rgba(11,16,32,.92)` + 8px backdrop blur, 1px red @ 50%, red glow 20px @ 15%): "Bash · failed" 10/600 red · "SELECTED" 8 mute · command 9 ink · "4.2s · 1.9k tok · exit 1 · iter 3/3" 9 mute · error message 8 red @ 85%.
  - Sample graph: prompt "fix flaky retry" → thinking 8.4k → {Read retry.py, Grep "backoff", subagent explore tests → subagent 2.1k} → thinking 14.2k → Edit retry.py (chips retry.py +42 −17, test_retry.py +8 −3) → Bash pytest → failed exit 1 ⟲ ×3 → Bash pytest ✓ → result done.
- **Center bottom — Activity lanes** panel 704×232: title + zoom chips 15m / **60m** / 6h (selected: 1px cyan @ 50%, fill cyan @ 10%, ink text). Lane row 28px: name 10 ink at x4; track x96 width 560 (=60 min) 14px r3 @ 5%; segments 14px r2 @ 80% in activity color; prompt ticks 1.5×5 ink above the lane. Vertical gridlines at −45/−30/−15 @ 8%; axis labels 8 mute; "NOW" playhead at x658: 1.5px cyan, 6px glow.
- **Right rail — Stats** (panels pad 10, gap 8):
  1. Token burn: title + range chips 1h / **24h** / 7d; stacked area 252×72, four series (input cyan, output amber, cache-read teal, thinking violet) fill @ 55% + 1px top line; 1px baseline @ 20%; legend 8 uppercase.
  2. Model mix donut r24 stroke 8, 3° gaps, colors = model rings; legend "fable-5.1 38% · sonnet-5 31% · opus-5 22% · haiku-4.5 9%". Cache-hit gauge: 270° arc (−135°→135°) r26 stroke 6 round, track @ 12%, value teal with 5px glow, "71%" 14/600 + "1.9M / 2.7M" 7 mute.
  3. Est. cost today "$41.27" 20/600 + "+$3.10 / h at current burn" 8 mute · Loops & errors "7 loops" amber, "12 errors" red (20/600).
  4. Tool usage bar list (Read 412, Edit 188, Bash 143, Grep 97, Write 31) — 52×4 tracks r2, fill by tool color · Repos leaderboard (lantern 2.05M, orbit-core 1.24M, lumen-ui 612k, willow 340k, sandpiper 88k) — 24×4 bars in model color.
  5. Activity heatmap 12 weeks × 7 days: cells 19×8 r2, pitch 21×10, cyan @ .06–.95.
- **Thought stream** (bottom, fill `rgba(5,7,13,.6)`, top divider): header 9 label + "BLUR THOUGHTS" toggle (22×12 pill, 6px knob; on = cyan border @ 60% / fill @ 20%). 6 lines 10px, grid `56 | 84 | 72 | 1fr` gap 10: time mute · agent name in model color 500 · glyph + activity 9 uppercase in activity color · text #C7D0E8 ellipsized. Blur mode: text `blur(4px)` @ 70%. Blinking 6×11 cyan cursor bottom-right.

### 2a — Dashboard · Brain view (adds to 1e)
- Hero title row: "orbit-core · turn 7" + tab chips **flow / brain / loops** (selected: violet 1px @ 60%, fill @ 12%). Right hint: "node size = tokens held · bright = active this turn".
- **Context brain** 688×322: five layers at x = 48 / 200 / 352 / 504 / 640 with dashed vertical guides (1px `1 4` @ 7%) and uppercase 8/+12% layer labels: PROMPT · CONTEXT · FILES · TOOLS · REASONING · OUTPUT. Nodes centered vertically around y=165, spacing `min(48, 260/n)`.
  - Node r = `4 + √(tokens/60)` clamp 5–17, stroke 1.25, halo r+7 @ 7%. Active this turn: fill @ 35%, glow 8px, opacity 1, breathing. Dormant: fill @ 12%, opacity 0.35, no glow. Label right of node: name 8 #C7D0E8 + tokens mute.
  - Colors: files & Read/Grep cyan · Edit/Write/output files amber · Bash green · reasoning violet · prompt & summary ink.
  - Edges: cubic, `.75px @ 8–22%` mute (weight = co-activation); hot edges (both ends active) `1.25px @ 70%` in target color and carry 3px particles.
  - Bottom: context-window bar 688×6 r1 (segments system 8k mute, files 61k cyan, tool results 34k green, thinking 21k violet; 1px hairline outline) with a white 1px compaction tick at 62%; caption row 8 uppercase.
  - Sample data: files retry.py 18.4k · test_retry.py 9.1k · backoff.py 6.2k · config.py 2.1k · CLAUDE.md 4.8k · README.md 1.2k; tools Read 14.2k · Grep 3.9k · Edit 7.6k · Bash 12.8k · Write 0.9k; reasoning hypothesis 4.1k · locate race 8.4k · patch 6.2k · verify 14.2k · conclude 1.8k; output plan.md 2.4k · diff 5.1k · summary 0.8k.
- **Agent card v2** (pad 8/12, gap 5): 28×28 progress ring left of the name (track 2.5px @ 14%, arc 2.5px round in model color, 4px glow; "3/7" 7/600 inside). Under the name: `⎇ branch · eta ~18m` 8 mute (eta red when "blocked"). Ring turns #3DFF7A when complete, #4A5568 when waiting/blocked. Header gains "15/30 steps".
- **Loop radar panel** (replaces loops/errors): 1px red border @ 28%, red glow 20px @ 6%; 64×64 mini radar (center dot amber r3, rings r = 8 + 6·i) + "LOOP RADAR" label, "×4" 20/600 red, "lantern · edit→pytest" 9 ink, "7 loops today · 12 errors · orbit-core ×3 resolved" 8 mute.

### 2b — Loop radar expanded 400×320
Radar 280×280 at left: center = retried tool (Edit): r12 amber fill @ 15% + 1.5px amber + 6px glow, ✎ glyph; r20 dashed `2 5` @ 20% spinning. One orbit ring per iteration r = 26 + 20·i: past iterations dashed `2 3` 1.25px full circles; current iteration solid 2px, open arc 0°→40°, pulsing red. Ring color amber #FFB020 → #FF7A45 → red #FF3B5C with i; opacity .35→1. Fail marker r3 (#05070D fill, 1.25px red) at 200° on each ring. On success the ring exits along a green dashed `3 3` tangent toward the "BREAKOUT → PASSES" label (top-right). Right column (92 wide, 8px): cycle description, iteration list (42s · 2.1k …), "same error 3× — suggest intervene", and an INTERRUPT chip (1px red @ 50%).

### 2c — Progress ring detail 300×320
56×56 ring (track 4px @ 14%, arc 4px round model color, 6px glow), "3/7" 12/600 + "STEPS" 6px; name 12/600; "43% · eta ~18m @ 18.4k/min" 9; "est. 610k tokens remaining" 8. Checklist rows 16px, grid `14 | 1fr | 44`: ✓ done ink · ◐ current in activity color · ○ pending mute · ✕ failed red; right column tokens/state 8 mute. Footer spec text 8 mute.

### 1f — Empty state
Compact-widget shell with all strokes slate: track r58 @ 8%, dashed ring @ 12% rotating 60s, "0 / TOK/MIN" in #4A5568, "no agents running / ALL QUIET" 11 + 9/+14%, footer "start a session with claude".

---

## Motion (what · values · driver)
All easing `ease-in-out` unless noted; honor Reduce Motion by freezing everything.
- Segment breathe — opacity .55→1, period `4s − 2s·(tpm/20k)` (4s idle → 2s at 20k tpm); driven by per-agent tokens/min.
- Sweep + dashed ring — rotate 360° linear, 12s while any agent active, 40s idle.
- Error pulse — opacity .45→1 and glow 2→12px, 1.2s; while an agent's same-error loop count ≥ 2.
- Heartbeat sparkline — 24 samples, shifts left 1px / 120ms, new sample per token event; amplitude .7 active, .08 waiting.
- Thought ticker — translateX 0→−50% (duplicated text), 18s linear, restart on new thought.
- Flow-graph particles — 3 × 4px dots along the active edge (offset-path / `Path.trim` in SwiftUI), 1.6s linear, staggered .53s; while a tool call is in progress.
- Brain particles — 3px dots on hot edges, 1.4–2.6s linear, random phase; brain nodes breathe 1.6–2.8s (period from recency).
- Node enter — scale .6→1, glow 0→8px, 400ms `cubic-bezier(.2,.8,.2,1)`.
- Loop badge tick — scale 1→1.25→1, 300ms ease-out on each iteration.
- Lanes — content scrolls left 1px / 6.4s (560px = 60 min); playhead opacity .55→1, 2s.
- Card select — border + glow 220ms ease-out; ctx bar width 300ms ease-out.
- Progress ring — arc grows 400ms `cubic-bezier(.2,.8,.2,1)` per completed step.
- Loop radar — new ring draws in 500ms ease-out from 0°; current ring pulseRed 1.2s; breakout trail draws 600ms ease-out.
- Header dot breathe 2s · stream cursor blink 1s `steps(1)` · new stream line slides up 12px 180ms ease-out.

## State & data model
- `Agent { name, repo, branch, model, activity: thinking|reading|editing|running|error|waiting, tpm, tokensSession, tokensToday, ctxUsed/ctxMax, elapsed, heartbeat[24], loopCount, sameErrorCount, plan: {done,total,steps[]}, eta }`
- Widget state derives: `idle` (all waiting) · `busy` · `alert` (any agent `sameErrorCount ≥ 2`).
- Dashboard: `selectedAgent`, `heroTab: flow|brain|loops`, `laneRange: 15m|60m|6h`, `burnRange: 1h|24h|7d`, `blurThoughts`.
- Flow graph = turn transcript → nodes (prompt, thinking blocks, tool_use, tool_result, subagent spawn/merge) with token counts; loops detected when the same (Edit → Bash) pair repeats with identical failure text.
- Brain = context inventory (files read, tools used, reasoning steps, outputs) with tokens held; "active this turn" = touched in the current turn.
- Progress = agent todo list (done/total); ETA = remaining steps × mean tokens per completed step ÷ current tpm.
- Sample data in the prototype: repos orbit-core / lumen-ui / lantern / sandpiper / willow; models fable-5.1, opus-5, sonnet-5, haiku-4.5; tokens 88k–2.05M per session, 3.12M today, 46.5k tok/min aggregate.

## Assets
No bitmaps. Everything is vector: arcs, cubic paths, rounded rects, circles, blur/glow. Glyphs → SF Symbols. Font: JetBrains Mono (bundle) or SF Mono.

## Files
- `Agent HUD.dc.html` — the live prototype (all frames; tweaks: blurThoughts, reduceMotion, showNotes). Requires `support.js` alongside.
- `support.js` — runtime for the prototype (not for reuse).
