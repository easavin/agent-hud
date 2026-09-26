import Foundation
import HUDCore

// Prints what the HUD sees right now. Handy for debugging ingest without the UI.
//   hudctl          live agents
//   hudctl stats    history aggregates (uses a throwaway index, so it always times a full backfill)

if CommandLine.arguments.dropFirst().first == "stats" {
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("hudctl-index-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: scratch) }
    let index = HistoryIndex(storeURL: scratch)
    let started = Date()
    let stats = await index.refresh()
    print(String(format: "backfill %.1fs", Date().timeIntervalSince(started)))
    print(String(format: "today: %d tokens · $%.2f est. API cost · $%.2f last hour · %d errors · cache hit %.0f%%",
                 stats.tokensToday, stats.costToday, stats.costLastHour, stats.errorsToday, stats.cacheHitRate * 100))
    print("models:", stats.modelMix.map { "\($0.model) \(Int($0.share * 100))%" }.joined(separator: " · "))
    print("tools: ", stats.tools.map { "\($0.name) \($0.count)" }.joined(separator: " · "))
    print("repos: ", stats.repos.map { "\($0.name) \($0.tokens)" }.joined(separator: " · "))
    let day = stats.burn[.day] ?? []
    print("24h output:", day.map { String(($0.output + $0.thinking) / 1000) }.joined(separator: " "))
    print("active days in 12 weeks:", stats.heatmap.joined().filter { ($0 ?? 0) > 0 }.count)
    exit(0)
}

let engine = IngestEngine()
let agents = await engine.poll()
if agents.isEmpty { print("no live agents") }
for agent in agents {
    print("● \(agent.name)  [\(agent.repo) @ \(agent.gitBranch ?? "-")]  pid \(agent.pid)")
    print("  \(agent.activity.rawValue)  model=\(agent.model ?? "-")  tok/min=\(agent.tokensPerMinute)  ctx=\(agent.contextTokens)/\(agent.contextMax)  turn \(agent.turnIndex)")
    print("  in=\(agent.usage.input) out=\(agent.usage.output) cacheRead=\(agent.usage.cacheRead) cacheWrite=\(agent.usage.cacheCreation) errors=\(agent.errorCount)")
    let tools = agent.toolCounts.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key)×\($0.value)" }
    print("  tools: \(tools.joined(separator: " "))  steps=\(agent.steps.count) lanes=\(agent.lanes.count) plan=\(agent.planDone)/\(agent.plan.count)")
    for loop in agent.loops { print("  loop \(loop.label) ×\(loop.count) sameError=\(loop.sameErrorCount) resolved=\(loop.resolved)") }
    let hour = Date().addingTimeInterval(-3600)
    let recent = agent.lanes.filter { ($0.end ?? .distantFuture) > hour && $0.kind != .idle }
    if let first = recent.first, let last = recent.last {
        let span = (last.end ?? Date()).timeIntervalSince(max(first.start, hour))
        print("  lanes last hour: \(recent.count) segments, \(Int(first.start.timeIntervalSinceNow / 60))m → \(Int(((last.end ?? Date()).timeIntervalSinceNow) / 60))m, \(Int(span))s")
    }
    for item in agent.ticker.suffix(3) { print("    [\(item.kind.rawValue)] \(item.text.prefix(100))") }
}
