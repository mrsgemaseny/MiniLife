[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$rawInput = ""
if ([Console]::IsInputRedirected) {
    $rawInput = [Console]::In.ReadToEnd()
}
if ([string]::IsNullOrWhiteSpace($rawInput)) {
    @{ decision = "allow" } | ConvertTo-Json -Compress | Write-Output
    exit 0
}

$payload = $rawInput | ConvertFrom-Json
if ($null -eq $payload -or $null -eq $payload.toolCall -or $null -eq $payload.toolCall.args) {
    @{ decision = "allow" } | ConvertTo-Json -Compress | Write-Output
    exit 0
}

$commandArgs = $payload.toolCall.args.CommandLine
if ([string]::IsNullOrWhiteSpace($commandArgs)) {
    @{ decision = "allow" } | ConvertTo-Json -Compress | Write-Output
    exit 0
}

if ($commandArgs -match "(?i)\bgit\s+push\b") {
    $today = Get-Date -Format "yyyy-MM-dd"
    $yesterday = (Get-Date).AddDays(-1).ToString("yyyy-MM-dd")
    
    $projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
    $brainCandidate = Join-Path (Split-Path -Parent $projectRoot) "Brain's protocol - second brain\journal"
    if (-not (Test-Path $brainCandidate)) {
        $brainCandidate = Join-Path $env:USERPROFILE "IdeaProjects\new_world\Brain's protocol - second brain\journal"
    }
    $journalBase = if (Test-Path $brainCandidate) { (Resolve-Path $brainCandidate).Path } else { $null }
    
    $todayFile = if ($journalBase) { Join-Path (Join-Path $journalBase $today) "minilife.md" } else { $null }
    $yesterdayFile = if ($journalBase) { Join-Path (Join-Path $journalBase $yesterday) "minilife.md" } else { $null }
    
    $hasValidJournal = $false
    foreach ($f in @($todayFile, $yesterdayFile)) {
        if (Test-Path $f) {
            $content = Get-Content $f -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($content) -and $content.Length -gt 30) {
                $hasValidJournal = $true
                break
            }
        }
    }
    
    if (-not $hasValidJournal) {
        # Резервная проверка: любая запись в журнале за последние 24 часа
        $recent = Get-ChildItem -Path $journalBase -Recurse -Filter "*.md" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge (Get-Date).AddHours(-24) }
        if ($recent) {
            $hasValidJournal = $true
        }
    }
    
    if (-not $hasValidJournal) {
        $response = @{
            decision = "deny"
            reason = "[WORKFLOW BARRIER] Попытка выполнить 'git push' без записи в журнале! Правило системы: ТЕСТЫ ПРОШЛИ -> ЗАПИСЬ В ЖУРНАЛ (journal/$today/minilife.md) -> GIT PUSH. Создайте запись в журнале Second Brain перед пушем."
        }
        $response | ConvertTo-Json -Compress | Write-Output
        exit 0
    }
}


@{ decision = "allow" } | ConvertTo-Json -Compress | Write-Output
exit 0

