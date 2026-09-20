# Agent HUD

A macOS monitor for Claude Code agents: an always-on-top widget (320×320, or 160×160 mini) that expands into a
1280×800 mission-control dashboard. It reads `~/.claude/sessions/*.json` and `~/.claude/projects/**/*.jsonl` —
strictly local, read-only, no network, no API keys.

The interface is **light product-analytics**: a warm off-white canvas, flat white cards with 1px warm-grey borders,
dark-ink buttons and segmented controls, and saturated-but-muted semantic colors that clear 4.5:1 on white. Everything
is vector — node graphs, donut, radar, stacked areas, sparklines, heatmap. No gradients, no glow, no shadows except
the flow popover's hard 2px offset.

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
- `AgentHUD/Views/Light/` — the whole UI.
  - `Theme.swift` — design tokens, type, radii; `Components.swift` — `Card`, `CardHeader`, `Segmented`,
    `ToolbarButton`, `ModelBadge`, `BarTrack`, `Sparkline`, `ProgressRing` and the `Geometry` helpers.
  - `DashboardView.swift` — the 1280×800 frame, header, metrics strip, body grid, thought stream and the keyboard.
  - `FlowLayout.swift` turns a turn's steps into positioned nodes and edges; `FlowGraphView.swift` draws them
    (Bézier edges, cracked error nodes, file chips, loop pill, popover, particles).
  - `HeroTabs.swift` — the brain graph with its context-window bar and the loop radar.
    `FileTreeLayout.swift` + `FilesView.swift` — the working directory as a schematic.
  - `AgentCard.swift`, `LanesPanel.swift`, `StatsRail.swift`, `WidgetView.swift`, `DockTileView.swift`.
- `design_handoff_agent_hud_light/` — the Claude Design handoff this UI is built from (frame `3b`).
  `design_handoff_agent_hud_terminal/` (frame `3a`) and `design_handoff_agent_hud/` (the original neon frames, still
  the behavior reference for 1e / 2a) are the earlier directions. `docs/design-prompt.md` — the prompt behind the first.

## Resizing

Every border between panes is draggable: the rail, the stats column, the flow/lanes split and the thought stream.
The handles appear on hover and the sizes persist (`railWidth`, `statsWidth`, `heroHeight`, `streamHeight`). The
window itself resizes freely — there is no locked aspect ratio and nothing is scaled; the layout reflows and the
content follows: the flow graph fits more or fewer columns, lanes stretch their track and show as many rows as
fit, the brain graph's layer columns are fractions of the pane, and the stats cards fold from two columns to one
when the rail gets narrow.

Panes window their content rather than scrolling it — `ImageRenderer` cannot draw a `ScrollView`, so `--snapshot`
would come back blank for any pane that used one. The agent rail shows the cards that fit plus `+N more · ↑↓`,
and `↑/↓` moves the window. `--snapshot` also writes `dashboard-narrow-*` (1040×640) and `dashboard-wide-*`
(1680×1000) so both ends of the range stay checkable.

## How the drawing is organised

Anything with a shape of its own is a `Canvas`: the flow graph, the brain graph, the loop radar, the lanes, the
stacked-area burn chart, the donut and the heatmap. Cards, controls and text stay ordinary SwiftUI so they hit-test
and truncate properly. `FlowLayout` is pure geometry with no SwiftUI in it, which keeps node placement, loop
compression and subagent attachment testable on their own.

Motion is calm and scoped. The flow graph splits into a static layer (edges, nodes, labels — redrawn only when the
turn changes) and a motion layer that runs at 15 fps only while a tool is in flight: three 4px dots down the live
edge, and the error node's ring alternating every 800 ms while a loop is open. Lanes redraw once a second. Reduce
Motion drops both layers to their resting frame and leaves the data updating.

Type is **IBM Plex Sans** when it is installed and the system face otherwise; code, commands and the thought stream
use **JetBrains Mono**, falling back to SF Mono. Neither font is bundled yet.

## Notes

- Finished sessions stay in the dashboard's **Recent** list for 3 days (`IngestEngine.historyWindow`, max 8) and remain fully
  browsable. The widget, Dock tile and counters only ever count live sessions.
- Subagent nodes are dashed teal circles carrying the agent type, the model that actually ran and its tokens.
  Source: `<session>/subagents/agent-*.jsonl` + `.meta.json`.
- The **Files** tab is a schematic, not a list: folders branch, files are leaves sized by how often they were
  edited, dashed rings mark changes a shell command made. Single-child folder chains collapse to `src/api`, and a
  file outside the session's own folder keeps only its parent (`…/memory`) — reproducing an absolute path put a
  90-character folder name across the whole canvas.
- The loop edge arcs *over* the row rather than under it as the handoff draws it: below the nodes is where the
  labels and the popover live.
- A turn longer than the canvas drops middle columns and says so (`⋯ +47 steps`); retries collapse to the latest
  iteration with a red `×N` pill on the loop edge.
- The Dock tile is an Activity Monitor-style history: output tokens per 10 s over 5 min, stacked, one color per agent.
- Keys: `↑ ↓` select a session · `f` `b` `l` `s` switch the hero tab · `p` blurs the thoughts · `1` `2` `7` set the
  burn range. Clicking a node opens its popover; the header's range button cycles the lane window.
- No **Interrupt** button, although the handoff lists one on the Loops tab: the app is strictly read-only and has no
  business killing someone's session.

- The **Files** tab merges two sources: Read/Edit/Write calls from the transcript (intent, line counts) and a scan of the
  session's working directory for files modified since the session began (catches shell-made changes; drawn dashed).
  The scan skips hidden folders, `node_modules`, build output and the like, and never crawls a home directory.

- tok/min is **output** tokens over the trailing minute, zero for idle agents.
- Cost is an API list-price equivalent (`CostEstimator.prices`), not what a subscription is billed.
- The history index is cached in `~/Library/Application Support/AgentHUD/index.json`; delete it to force a re-scan (~7s for 330 MB).
