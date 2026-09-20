# Agent HUD

A macOS monitor for Claude Code agents: an always-on-top widget (320×320, or 160×160 mini) that expands into a
1280×800 mission-control dashboard. It reads `~/.claude/sessions/*.json` and `~/.claude/projects/**/*.jsonl` —
strictly local, read-only, no network, no API keys.

The interface is a **terminal / TUI**: one monospace face at 12/16 on a character grid, 1px-bordered panes with the
title sitting on the border, charts made of block characters (`█ ▇ ░ ▁▂▃▄▅▆▇█ ░▒▓█`) and motion that steps cell by
cell. No gradients, no glow, no rounded chrome.

## Build & run

```bash
xcodegen generate
xcodebuild -project AgentHUD.xcodeproj -scheme AgentHUD -derivedDataPath build build
open build/Build/Products/Debug/AgentHUD.app
```

- It is a regular Dock app: the Dock icon is live (block-bar history + tok/min), clicking it opens the dashboard, and its
  right-click menu, the **View** menu (⌘1 dashboard · ⌘2 widget · ⌘3 mini) and the menu bar icon all control the widget.
- The widget has its own traffic lights: red hides it, yellow toggles mini/compact, green opens the dashboard
  (double-click works too). Closing the dashboard leaves the widget running; ⌘Q quits.
- `AgentHUD --demo busy|idle|alert` shows the design prototype's sample fleet instead of real sessions.
- `AgentHUD --snapshot <dir> [--demo …]` renders every frame to PNG and quits (no screen-recording permission needed).

The build signs with **Apple Development** (`project.yml`, team `TJ4NKH4368`) rather than ad-hoc. That matters for
permissions, not for distribution: the **Files** tab walks each session's working directory, so macOS asks for access
to Documents / Desktop / Downloads the first time a session runs there. An ad-hoc signature changes with every build,
so macOS treats each rebuild as a new app and asks again; a certificate keeps one identity and the grant sticks.
Building on another machine means either an Apple Development cert of your own or going back to `CODE_SIGN_IDENTITY: "-"`.

Only ever keep one built copy around: two bundles with the same identifier (say `Debug` and a stale `Release`) both
register with LaunchServices, and then a Dock or `open` launch can start the other one — two widgets on screen.

## Layout

- `Packages/HUDCore` — pure logic, unit-tested (`swift test`): transcript parsing, incremental tailing, per-session state
  (activity, turn steps, loops, plan progress, context "brain"), history index + cost estimate. `swift run hudctl [stats]`
  prints what the HUD sees.
- `AgentHUD/Views/Terminal/` — the whole UI.
  - `Term.swift` — design tokens, the monospace metrics, `TermRow`/`TermText` (a line of the grid), `TermPane`, `TermList`.
  - `TerminalDashboard.swift` — the 1280×800 frame, header line and keyboard; `AgentsPane`, `LanesPane`, `StatsPane`,
    `ThoughtsPane` are the other three corners of it.
  - `FlowTree.swift` + `FlowPane.swift` — a turn rendered as an ASCII tree (dashed subagent branches, box returns for
    retry loops); `HeroPanes.swift` — the brain, loops and files tabs.
  - `TerminalWidget.swift`, `DockTileView.swift` — the 320/160 widgets and the live Dock tile.
- `design_handoff_agent_hud_terminal/` — the Claude Design handoff this UI is built from (frame `3a`).
  `design_handoff_agent_hud/` — the previous neon handoff, kept for the behavior frames (1e / 2a).
  `docs/design-prompt.md` — the prompt that produced the first one.

## Two rules the UI is built on

**The character grid.** A line is a `TermRow`: runs of text with a color, built with `Term.pad` / `Term.padStart` so
columns line up by padding rather than pixel offsets. It renders as a single `Text` backed by an `AttributedString`,
which keeps every space exactly where it was put. Lane cells come from cumulative boundaries
(`end = round(t / 60min × 90)`) so every row is exactly 90 cells wide.

**Stepped motion, and not much of it.** Everything that moves is a `TimelineView` over one or two lines of text —
particles (130 ms), the live dot and the thought cursor (1 s), lanes (1 s). Nothing tweens, nothing glows, and no
timer drives a pane bigger than the line it animates; measured with `top`, the app sits around 1% with the dashboard
open and a live session. Reduce Motion stops the particles and the blinks and leaves the data updating.

The font is JetBrains Mono when it is installed and **Menlo** otherwise — not SF Mono, which has no `◐ ⌕ ✎ ✕ ◌` and
would fall back to a proportional face and break the grid.

## Notes

- Finished sessions stay in the dashboard's **Recent** list for 3 days (`IngestEngine.historyWindow`, max 8) and remain fully
  browsable. The widget, Dock tile and counters only ever count live sessions.
- Subagent nodes branch off the flow tree with a dashed `╌╌▶`, carry the tokens the subagent spent and merge back into the
  line below with a `┐ … ┘` return. Source: `<session>/subagents/agent-*.jsonl` + `.meta.json`.
- The tree nests one level per round of tool calls and stops at depth 4 (`FlowTree.maxDepth`); real turns run twenty
  rounds deep and would otherwise march off the right edge.
- The Dock tile is an Activity Monitor-style history: output tokens per 10 s over 5 min, stacked, one color per agent.
- Keys: `↑ ↓` select a session · `f` `b` `l` `s` switch the hero pane · `p` blurs the thoughts · `1` `2` `7` set the
  burn range. Clicking works everywhere too, and hovering a lane cell reports it in the pane title.

- The **Files** tab merges two sources: Read/Edit/Write calls from the transcript (intent, line counts) and a scan of the
  session's working directory for files modified since the session began (catches shell-made changes; drawn dashed).
  The scan skips hidden folders, `node_modules`, build output and the like, and never crawls a home directory.

- tok/min is **output** tokens over the trailing minute, zero for idle agents.
- Cost is an API list-price equivalent (`CostEstimator.prices`), not what a subscription is billed.
- The history index is cached in `~/Library/Application Support/AgentHUD/index.json`; delete it to force a re-scan (~7s for 330 MB).
