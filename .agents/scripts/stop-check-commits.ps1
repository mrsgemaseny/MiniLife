[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$rawInput = ""
if ([Console]::IsInputRedirected) {
    $rawInput = [Console]::In.ReadToEnd()
}

# Динамическое определение путей проекта и Second Brain
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$brainCandidate = Join-Path (Split-Path -Parent $projectRoot) "Brain's protocol - second brain"
if (-not (Test-Path $brainCandidate)) {
    $brainCandidate = Join-Path $env:USERPROFILE "IdeaProjects\new_world\Brain's protocol - second brain"
}
$brainRoot = if (Test-Path $brainCandidate) { (Resolve-Path $brainCandidate).Path } else { $null }

# Проверяем git статус проекта MiniLife
$projectStatus = ""
if (Test-Path $projectRoot) {
    Push-Location $projectRoot
    $projectStatus = git status --porcelain 2>$null
    Pop-Location
}

# Проверяем git статус Second Brain
$brainStatus = ""
if ($brainRoot -and (Test-Path $brainRoot)) {
    Push-Location $brainRoot
    $brainStatus = git status --porcelain 2>$null
    Pop-Location
}

if ($projectStatus -or $brainStatus) {
    $out = @{
        decision = "continue"
        reason = "[WORKFLOW BARRIER] Обнаружены незакоммиченные изменения в проекте или Second Brain! Правило: ТЕСТЫ ПРОШЛИ -> ЗАПИСЬ В ЖУРНАЛ -> GIT COMMIT/PUSH. Пожалуйста, сохраните изменения в журнале Second Brain и сделайте commit & push."
    }
    $out | ConvertTo-Json -Compress | Write-Output
} else {
    $out = @{
        decision = "stop"
    }
    $out | ConvertTo-Json -Compress | Write-Output
}
exit 0
