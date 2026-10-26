import Foundation

public enum AgentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude, codex, gemini, antigravity, custom
    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        case .antigravity: return "Antigravity"
        case .custom: return "Custom agent"
        }
    }

    /// The command-line tool, for the agents that have one.
    public var binary: String? {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .gemini: return "gemini"
        case .antigravity, .custom: return nil
        }
    }

    public var installHint: String {
        switch self {
        case .claude: return "npm install -g @anthropic-ai/claude-code"
        case .codex: return "npm install -g @openai/codex"
        case .gemini: return "npm install -g @google/gemini-cli"
        case .antigravity: return "Download Antigravity from antigravity.google"
        case .custom: return "Any command-line agent; set its command in Settings → AI"
        }
    }

    /// What to run in a terminal to sign in (each tool keeps its own credentials).
    public var signInCommand: String? {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex login"
        case .gemini: return "gemini"
        case .antigravity, .custom: return nil
        }
    }
}

public enum AgentAutonomy: String, Codable, CaseIterable, Sendable {
    case plan, edit, full
    public var title: String {
        switch self {
        case .plan: return "Plan only"
        case .edit: return "Edit files"
        case .full: return "Full auto"
        }
    }
    public var explanation: String {
        switch self {
        case .plan: return "Reads the project and proposes a plan. Changes nothing."
        case .edit: return "Edits files in the project. Commands that need approval are refused."
        case .full: return "Edits files and runs any command without asking. Use with care."
        }
    }
}

public enum AgentEvent: Equatable, Sendable {
    case text(String)
    case tool(name: String, detail: String)
    case result(success: Bool, summary: String, costUSD: Double?)
}

/// Builds the shell command for an agent. The task is never spliced into the command: it is exported as
/// `NEX_TASK` and referenced as `"$NEX_TASK"`, so quotes, `;` or `$( )` in a task are just text.
public enum AgentCommandBuilder {
    public static let taskVariable = "NEX_TASK"

    public static func command(kind: AgentKind, autonomy: AgentAutonomy, customTemplate: String?) -> String? {
        let task = "\"$\(taskVariable)\""
        switch kind {
        case .claude:
            let mode: String
            switch autonomy {
            case .plan: mode = "--permission-mode plan --permission-prompts none"
            case .edit: mode = "--permission-mode acceptEdits --permission-prompts none"
            case .full: mode = "--dangerously-skip-permissions"
            }
            return "claude -p \(task) --output-format stream-json --verbose \(mode)"
        case .codex:
            let mode: String
            switch autonomy {
            case .plan: mode = "--sandbox read-only"
            case .edit: mode = "--full-auto"
            case .full: mode = "--dangerously-bypass-approvals-and-sandbox"
            }
            return "codex exec --skip-git-repo-check \(mode) \(task)"
        case .gemini:
            switch autonomy {
            case .plan: return "gemini -p \(task)"
            case .edit: return "gemini --approval-mode auto_edit -p \(task)"
            case .full: return "gemini --yolo -p \(task)"
            }
        case .antigravity:
            return nil                       // no command-line runner: the app opens instead
        case .custom:
            let template = (customTemplate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !template.isEmpty else { return nil }
            return template.contains("$\(taskVariable)") ? template : "\(template) \(task)"
        }
    }

    /// For running the agent interactively in a terminal tab (the task is shell-quoted).
    public static func interactiveCommand(kind: AgentKind, task: String) -> String? {
        guard let binary = kind.binary else { return nil }
        return "\(binary) \(CommandBuilder.quote(task))"
    }
}

/// Turns Claude Code's `--output-format stream-json` lines into readable progress.
public enum ClaudeStreamParser {
    public static func events(from line: String) -> [AgentEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        guard let data = trimmed.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = obj["type"] as? String else { return [.text(trimmed)] }
        switch type {
        case "assistant":
            let content = ((obj["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
            return content.compactMap { block in
                switch block["type"] as? String {
                case "text":
                    let text = ((block["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.isEmpty ? nil : .text(text)
                case "tool_use":
                    return .tool(name: (block["name"] as? String) ?? "Tool", detail: detail(block["input"] as? [String: Any] ?? [:]))
                default:
                    return nil
                }
            }
        case "result":
            let isError = (obj["is_error"] as? Bool) ?? false
            let subtype = (obj["subtype"] as? String) ?? ""
            let result = ((obj["result"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return [.result(success: !isError && subtype == "success", summary: result.isEmpty ? subtype : result,
                            costUSD: obj["total_cost_usd"] as? Double)]
        default:
            return []
        }
    }

    private static func detail(_ input: [String: Any]) -> String {
        if let path = input["file_path"] as? String ?? input["path"] as? String { return URL(fileURLWithPath: path).lastPathComponent }
        if let command = input["command"] as? String { return String(command.prefix(80)) }
        for key in ["pattern", "url", "description", "query"] { if let v = input[key] as? String { return String(v.prefix(80)) } }
        return ""
    }
}
