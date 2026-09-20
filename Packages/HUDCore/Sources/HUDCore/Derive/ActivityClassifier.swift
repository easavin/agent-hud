import Foundation

public enum ActivityClassifier {
    /// Maps a tool name to the activity it represents.
    public static func activity(forTool name: String) -> ActivityKind {
        switch name {
        case "Read", "Grep", "Glob", "LS", "WebFetch", "WebSearch", "ToolSearch", "NotebookRead":
            return .reading
        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            return .editing
        case "Agent", "Task", "Workflow":
            return .subagent
        case "AskUserQuestion", "ExitPlanMode":
            return .waiting
        default:
            // Bash, MCP tools, skills: the agent is executing something out in the world.
            return .running
        }
    }
}
