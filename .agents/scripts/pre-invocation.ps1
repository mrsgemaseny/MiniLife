[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$rawInput = ""
if ([Console]::IsInputRedirected) {
    $rawInput = [Console]::In.ReadToEnd()
}
if ([string]::IsNullOrWhiteSpace($rawInput)) {
    @{ injectSteps = @() } | ConvertTo-Json -Compress | Write-Output
    exit 0
}

$inputJson = $rawInput | ConvertFrom-Json
$injectSteps = @()

$contextMd = Join-Path $PSScriptRoot "..\CONTEXT.md"
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$brainCandidate = Join-Path (Split-Path -Parent $projectRoot) "Brain's protocol - second brain\context"
if (-not (Test-Path $brainCandidate)) {
    $brainCandidate = Join-Path $env:USERPROFILE "IdeaProjects\new_world\Brain's protocol - second brain\context"
}
$brainDir = if (Test-Path $brainCandidate) { (Resolve-Path $brainCandidate).Path } else { $null }

# Для повторных вызовов (invocationNum > 1) отдаем легковесное напоминание для экономии токенов
if ($null -ne $inputJson -and $inputJson.invocationNum -gt 1) {
    $injectSteps += @{ ephemeralMessage = "[AI GUARD] Active Session (MiniLife Godot 4). Directives: Zero emojis | Use native API tools | Strict SignalBus isolation & PROJECT_MiniLife.md compliance." }
    @{ injectSteps = $injectSteps } | ConvertTo-Json -Depth 5 -Compress | Write-Output
    exit 0
}

# При первом запуске сессии (invocationNum == 1) загружаем полный контекст
if (Test-Path $contextMd) {
    $lines = Get-Content $contextMd -Encoding UTF8
    if ($lines.Count -gt 200) {
        $injectSteps += @{ ephemeralMessage = "[CONTEXT SIZE WARNING] .agents/CONTEXT.md is $($lines.Count) lines (limit: 200). Prune resolved history." }
    }
    $content = $lines -join "`n"
    $injectSteps += @{ ephemeralMessage = "[AUTO-INJECTED] CONTENTS OF .agents/CONTEXT.md:`n$content" }
}

# Tiered Memory Architecture: Only inject essential active context (rules, me, projects)
# Archival files (audits, other project specs) remain on disk for on-demand tool retrieval
$coreWhitelist = @("rules.md", "me.md", "projects.md")

if ($brainDir -and (Test-Path $brainDir)) {
    foreach ($fileName in $coreWhitelist) {
        $filePath = Join-Path $brainDir $fileName
        if (Test-Path $filePath) {
            $lines = Get-Content $filePath -Encoding UTF8
            # Cap each file to max 120 lines to prevent context window bloat
            if ($lines.Count -gt 120) {
                $content = ($lines | Select-Object -First 120) -join "`n"
            } else {
                $content = $lines -join "`n"
            }
            $injectSteps += @{ ephemeralMessage = "[AUTO-INJECTED SECOND BRAIN] $fileName:`n$content" }
        }
    }
}

@{ injectSteps = $injectSteps } | ConvertTo-Json -Depth 10 -Compress | Write-Output
exit 0

