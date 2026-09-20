# Claude Design prompt — Agent HUD

Paste everything below the line into Claude Design.

---

**Design "Agent HUD" — a macOS desktop monitor for AI coding agents, in a sci-fi HUD / neon aesthetic.**

**What it is.** A developer runs 3–8 Claude Code agents at once in different repositories. Agent HUD is to those agents what a CPU/GPU monitor is to hardware: a small always-on-top square that lives in a screen corner, which expands into a full mission-control dashboard. It should feel alive — you glance at it and instantly know who is thinking, who is stuck, and how fast tokens are burning.

**Aesthetic.** Dark mission-control HUD. Near-black blue-tinted background (#05070D–#0B1020), translucent glass panels with 1px hairline borders and soft outer glow, thin luminous strokes, radial gauges, fine grid/scanline texture used sparingly. Typography: a geometric monospace for numbers and labels (JetBrains Mono / SF Mono feel), small uppercase tracked labels, large tabular numerals. Motion is part of the design: breathing glows, sweeping arcs, particles flowing along graph edges. Avoid generic admin-dashboard cards, avoid purple-gradient "AI" clichés, avoid clutter — dense but legible at arm's length.

**Semantic color system (must be consistent everywhere):**
thinking = violet/magenta · reading/searching = cyan · editing/writing = amber · running commands = electric green · error/failed tool = red · waiting for user/idle = dim slate · subagent = teal outline. Models get their own accent ring: Fable, Opus, Sonnet, Haiku.

**Deliver these frames:**

1. **Compact widget, 320×320** (the hero — most important). Shows: a central radial "reactor" gauge whose ring segments are the active agents (segment color = current activity, brightness = token throughput); in the center, total tokens/min and today's token total; below, up to 5 agent rows: status dot, repo name, tiny live sparkline "heartbeat", current activity glyph; at the bottom, a one-line **thought ticker** — a scrolling snippet of what the most active agent is thinking/doing right now (e.g. `orbit-core ▸ thinking: "the race is in the retry handler…"`). Also show 3 states: all idle (calm, dim), busy (4 agents), and alert (one agent looping on errors — red pulse).
2. **Mini variant, 160×160** — just the reactor ring + tokens/min.
3. **Expanded dashboard, 1280×800**, with these regions:
   - **Left rail — Agents.** A card per session: name, repo, git branch, model badge, status, context-window fill bar, tokens this session, elapsed time, heartbeat waveform. Selected card is highlighted.
   - **Center hero — Thinking Flow Graph** for the selected agent. A live node graph flowing left→right: user prompt → thinking nodes → tool-call nodes (Read, Edit, Bash, Search…) → results. Node color follows the semantic system; node size = tokens spent. **Loops must be visible**: when the agent retries (edit → run tests → fail → edit again), draw it as a cycle with an iteration counter badge (×3). Failed tool calls are red nodes with a crack/glitch treatment. Subagents fork off as teal branches and merge back. Edited files appear as small amber file chips hanging off edit nodes with +/− line counts. Particles travel along the currently active edge. Include a hover/selected node detail popover (tool name, duration, tokens, snippet).
   - **Below the graph — Activity Timeline Lanes.** One horizontal lane per agent over the last 60 min (zoomable), colored segments for thinking / reading / editing / running / waiting / error, like a profiler flame chart. A "now" playhead glows on the right edge. User prompts are small tick markers.
   - **Right rail — Stats.** Token burn area chart (input / output / cache-read / thinking stacked) with time-range toggle 1h·24h·7d; model-mix donut; cache hit-rate gauge; estimated cost today; tool-usage bar list; per-repo leaderboard; 12-week activity heatmap; "loops & errors" counter.
   - **Bottom strip — Thought Stream.** A terminal-like log of the latest thinking snippets and actions across all agents, color-tagged per agent, with a privacy "blur thoughts" toggle.
4. **Component sheet**: color tokens, type scale, gauge, sparkline, node types (prompt / thinking / tool / error / subagent / file chip), lane segment, agent card, badges, empty state ("no agents running — all quiet").

**Constraints.** It will be built natively in SwiftUI on macOS, so: favor shapes achievable with vector paths, gradients, blur and glow (arcs, lines, rounded rects, particles) over bitmap textures; keep a strict 4/8px spacing grid; give me exact hex values, font sizes and stroke widths; every animated element should note its motion (duration, easing, what drives it). Use realistic sample data: repos named `orbit-core`, `lumen-ui`, `lantern`, `sandpiper`, `willow`; models `fable-5.1`, `opus-5`, `sonnet-5`, `haiku-4.5`; token numbers in the 10k–5M range.
