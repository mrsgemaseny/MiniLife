# ==============================================================================
# AI Prompt Guard - Context Injection & Hallucination Prevention
# ==============================================================================

function global:prompt {
    # Injects critical guardrail warnings directly into the stderr stream of PowerShell.
    # The AI agent captures stderr after each command, automatically refreshing context.
    [Console]::Error.WriteLine("[AI GUARD] CRITICAL DIRECTIVES: NO EMOJIS | USE API TOOLS (view_file, grep_search, replace_file_content) NOT CLI (cat, grep, ls) | READ .agents/AGENTS.MD ON UNCERTAINTY")
    
    # Return standard PowerShell prompt path
    "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
}
