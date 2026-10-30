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
if ($null -eq $payload -or $null -eq $payload.toolCall -or $payload.toolCall.name -ne "run_command" -or $null -eq $payload.toolCall.args) {
    @{ decision = "allow" } | ConvertTo-Json -Compress | Write-Output
    exit 0
}

$cmd = $payload.toolCall.args.CommandLine
if ([string]::IsNullOrWhiteSpace($cmd)) {
    @{ decision = "allow" } | ConvertTo-Json -Compress | Write-Output
    exit 0
}

# 1. Запрещаем использование shell команд вместо нативных инструментов (экономия токенов и надежность)
# Разрешаем 'git grep', 'git status', 'git log', но блокируем прямые вызовы утилит чтения/поиска
$isGitCommand = $cmd -match "(?i)^\s*git\s+"
if (-not $isGitCommand) {
    $forbiddenTerminalReaders = "(?i)^\s*(cat|grep|sed|ls|head|tail|Get-Content|gc|type|Select-String|sls|Get-ChildItem|gci|dir)\b"
    if ($cmd -match $forbiddenTerminalReaders) {
        $response = @{
            decision = "deny"
            reason = "[SAFETY BARRIER] Запрещено использовать shell-утилиты (cat, grep, sed, ls, head, tail, Get-Content, Select-String, dir) через терминал. Используйте нативные инструменты Antigravity: view_file, list_dir, grep_search, replace_file_content."
        }
        $response | ConvertTo-Json -Compress | Write-Output
        exit 0
    }
}

# 2. Запрещаем опасные деструктивные Git команды (проверка в рамках одной строки команды)
$destructiveGit = "(?im)^\s*git\s+.*(--force|-f\b|--hard)"
if ($cmd -match $destructiveGit) {
    $response = @{
        decision = "deny"
        reason = "[SAFETY BARRIER] Запрещены деструктивные Git операции (force push, reset --hard, clean -f)."
    }
    $response | ConvertTo-Json -Compress | Write-Output
    exit 0
}


@{ decision = "allow" } | ConvertTo-Json -Compress | Write-Output
exit 0
