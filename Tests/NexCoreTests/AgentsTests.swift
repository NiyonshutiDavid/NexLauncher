import Testing
import Foundation
@testable import NexCore

@Suite struct AgentCommandTests {
    @Test func claudeStreamsJSONWithThePermissionModeForEachAutonomyLevel() {
        let edit = AgentCommandBuilder.command(kind: .claude, autonomy: .edit, customTemplate: nil)
        #expect(edit == #"claude -p --output-format stream-json --verbose --permission-mode acceptEdits --permission-prompts none -- "$NEX_TASK""#)
        #expect(AgentCommandBuilder.command(kind: .claude, autonomy: .plan, customTemplate: nil)?.contains("--permission-mode plan") == true)
        #expect(AgentCommandBuilder.command(kind: .claude, autonomy: .full, customTemplate: nil)?.contains("--dangerously-skip-permissions") == true)
    }

    @Test func codexAndGeminiUseTheirNonInteractiveModes() {
        #expect(AgentCommandBuilder.command(kind: .codex, autonomy: .edit, customTemplate: nil) == #"codex exec --skip-git-repo-check --full-auto -- "$NEX_TASK""#)
        #expect(AgentCommandBuilder.command(kind: .codex, autonomy: .plan, customTemplate: nil)?.contains("--sandbox read-only") == true)
        #expect(AgentCommandBuilder.command(kind: .gemini, autonomy: .edit, customTemplate: nil) == #"gemini --approval-mode auto_edit --prompt="$NEX_TASK""#)
        #expect(AgentCommandBuilder.command(kind: .gemini, autonomy: .full, customTemplate: nil)?.contains("--yolo") == true)
    }

    @Test func antigravityRunsItsCLIWithTheModeForEachAutonomyLevel() {
        // agy installs to ~/.local/bin, which a login shell may not have on its PATH.
        #expect(AgentCommandBuilder.command(kind: .antigravity, autonomy: .edit, customTemplate: nil)
                == #"PATH="$HOME/.local/bin:$PATH" agy --mode accept-edits -p "$NEX_TASK""#)
        #expect(AgentCommandBuilder.command(kind: .antigravity, autonomy: .plan, customTemplate: nil)?.contains("--mode plan -p") == true)
        #expect(AgentCommandBuilder.command(kind: .antigravity, autonomy: .full, customTemplate: nil)?.contains("--dangerously-skip-permissions -p") == true)
    }

    @Test func antigravityKindDescribesItsCLI() {
        #expect(AgentKind.antigravity.binary == "agy")
        #expect(AgentKind.antigravity.signInCommand == "agy")
        #expect(AgentKind.antigravity.installHint == "curl -fsSL https://antigravity.google/cli/install.sh | bash")
    }

    @Test func geminiCarriesTheReplacementNotice() {
        #expect(AgentKind.gemini.notice?.contains("Antigravity CLI") == true)
        #expect(AgentKind.claude.notice == nil && AgentKind.antigravity.notice == nil)
    }

    @Test func customTemplatesGetTheTaskAsAVariableNeverSplicedIn() {
        #expect(AgentCommandBuilder.command(kind: .custom, autonomy: .edit, customTemplate: #"aider --message "$NEX_TASK""#) == #"aider --message "$NEX_TASK""#)
        #expect(AgentCommandBuilder.command(kind: .custom, autonomy: .edit, customTemplate: "my-agent run") == #"my-agent run "$NEX_TASK""#)
        #expect(AgentCommandBuilder.command(kind: .custom, autonomy: .edit, customTemplate: "  ") == nil)
    }

    @Test func interactiveCommandsQuoteTheTaskSafely() {
        #expect(AgentCommandBuilder.interactiveCommand(kind: .claude, task: "fix it's bug") == #"claude -- 'fix it'\''s bug'"#)
        #expect(AgentCommandBuilder.interactiveCommand(kind: .codex, task: "a") == "codex -- 'a'")
        #expect(AgentCommandBuilder.interactiveCommand(kind: .antigravity, task: "fix it") == #"PATH="$HOME/.local/bin:$PATH" agy -i 'fix it'"#)
        #expect(AgentCommandBuilder.interactiveCommand(kind: .custom, task: "a") == nil)
    }
}

@Suite struct ClaudeStreamParserTests {
    @Test func assistantTextAndToolCalls() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Looking at the tests."},{"type":"tool_use","name":"Edit","input":{"file_path":"/p/src/app.ts"}}]}}"#
        #expect(ClaudeStreamParser.events(from: line) == [.text("Looking at the tests."), .tool(name: "Edit", detail: "app.ts")])
    }

    @Test func bashToolShowsTheCommand() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}]}}"#
        #expect(ClaudeStreamParser.events(from: line) == [.tool(name: "Bash", detail: "npm test")])
    }

    @Test func resultSuccessAndError() {
        #expect(ClaudeStreamParser.events(from: #"{"type":"result","subtype":"success","is_error":false,"result":"Done: fixed the bug.","total_cost_usd":0.0123}"#)
                == [.result(success: true, summary: "Done: fixed the bug.", costUSD: 0.0123)])
        #expect(ClaudeStreamParser.events(from: #"{"type":"result","subtype":"error_max_turns","is_error":true,"result":""}"#)
                == [.result(success: false, summary: "error_max_turns", costUSD: nil)])
    }

    @Test func systemAndToolResultLinesAreQuietAndGarbageIsText() {
        #expect(ClaudeStreamParser.events(from: #"{"type":"system","subtype":"init"}"#).isEmpty)
        #expect(ClaudeStreamParser.events(from: #"{"type":"user","message":{"content":[{"type":"tool_result"}]}}"#).isEmpty)
        #expect(ClaudeStreamParser.events(from: "plain output") == [.text("plain output")])
        #expect(ClaudeStreamParser.events(from: "   ").isEmpty)
    }
}

@Suite struct AgentSettingsTests {
    @Test func olderSettingsGetAgentDefaults() throws {
        let json = #"{"displayName":"D","scanRoot":"file:///tmp/","showDockIcon":true,"pinnedProjectIDs":[]}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(s.defaultAgent == .claude && s.agentAutonomy == .edit && s.customAgentCommand.isEmpty && s.notifyAgents)
    }
}

@Suite struct AgentDashTaskTests {
    @Test func tasksStartingWithADashAreNotReadAsFlags() {
        #expect(AgentCommandBuilder.command(kind: .claude, autonomy: .edit, customTemplate: nil)?.hasSuffix(#"-- "$NEX_TASK""#) == true)
        #expect(AgentCommandBuilder.command(kind: .codex, autonomy: .edit, customTemplate: nil)?.hasSuffix(#"-- "$NEX_TASK""#) == true)
        #expect(AgentCommandBuilder.command(kind: .gemini, autonomy: .edit, customTemplate: nil)?.contains(#"--prompt="$NEX_TASK""#) == true)
        #expect(AgentCommandBuilder.interactiveCommand(kind: .claude, task: "- fix") == "claude -- '- fix'")
    }

    @Test func quickPanelShortcutSettingDefaultsOn() throws {
        let json = #"{"displayName":"D","scanRoot":"file:///tmp/","showDockIcon":true,"pinnedProjectIDs":[]}"#
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)).quickPanelShortcutEnabled)
    }
}

@Suite struct AgentConversationTests {
    @Test func claudeFollowUpsResumeTheSession() {
        let cmd = AgentCommandBuilder.command(kind: .claude, autonomy: .edit, customTemplate: nil, resumeSessionID: "abc-123")
        #expect(cmd?.contains("--resume 'abc-123'") == true)
        #expect(cmd?.hasSuffix(#"-- "$NEX_TASK""#) == true)
    }

    @Test func sessionIDIsReadFromStreamLines() {
        #expect(ClaudeStreamParser.sessionID(from: #"{"type":"system","subtype":"init","session_id":"s-1"}"#) == "s-1")
        #expect(ClaudeStreamParser.sessionID(from: #"{"type":"result","session_id":"s-2","result":"ok"}"#) == "s-2")
        #expect(ClaudeStreamParser.sessionID(from: "plain") == nil)
    }

    @Test func followUpsForOtherAgentsCarryTheEarlierExchange() {
        let text = AgentCommandBuilder.followUpTask(previousTask: "Add a footer", previousAnswer: "Added Footer.tsx", message: "Make it sticky")
        #expect(text.contains("Add a footer") && text.contains("Added Footer.tsx") && text.hasSuffix("Make it sticky"))
    }
}
