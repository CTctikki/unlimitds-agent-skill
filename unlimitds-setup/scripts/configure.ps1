[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('standard', 'jailbreak')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'

function Get-PlainTextSecret {
    $secureValue = Read-Host '请输入 UnlimitDS API Key' -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Test-CommandAvailable {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-ApiKey {
    param([string]$ApiKey, [bool]$SkipCheck)

    if ($SkipCheck) {
        return 'skipped-test-only'
    }

    try {
        $null = Invoke-RestMethod -Uri 'https://unlimitds.chat/v1/models' -Headers @{ Authorization = "Bearer $ApiKey" } -Method Get -TimeoutSec 30
        return 'passed'
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        switch ($statusCode) {
            401 { throw 'API Key 无效或已失效（HTTP 401）。' }
            429 { throw '账户额度已用完或受到频率限制（HTTP 429）。' }
            default { throw '无法连接 UnlimitDS API，请检查网络后重试。' }
        }
    }
}

function Get-ConfiguredClients {
    param([string]$HomePath, [bool]$TestMode)

    if ($TestMode -and $env:UNLIMITDS_SETUP_CLIENTS) {
        switch ($env:UNLIMITDS_SETUP_CLIENTS.ToLowerInvariant()) {
            'both' { return @('codex', 'claude') }
            'codex' { return @('codex') }
            'claude' { return @('claude') }
            'none' { return @() }
            default { throw '测试客户端覆盖值无效。' }
        }
    }

    $clients = [System.Collections.Generic.List[string]]::new()
    if ((Test-CommandAvailable 'codex') -or (Test-Path (Join-Path $HomePath '.codex'))) {
        $clients.Add('codex')
    }
    if ((Test-CommandAvailable 'claude') -or (Test-Path (Join-Path $HomePath '.claude'))) {
        $clients.Add('claude')
    }
    return @($clients)
}

function Update-CodexConfig {
    param([string]$HomePath, [string]$Model)

    $codexDirectory = Join-Path $HomePath '.codex'
    $configPath = Join-Path $codexDirectory 'config.toml'
    New-Item -ItemType Directory -Path $codexDirectory -Force | Out-Null

    $backupPath = $null
    $existingLines = @()
    if (Test-Path $configPath) {
        $timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-ffffff')
        $backupPath = "$configPath.unlimitds-backup-$timestamp"
        Copy-Item -LiteralPath $configPath -Destination $backupPath
        $existingLines = @(Get-Content -LiteralPath $configPath)
    }

    $preserved = [System.Collections.Generic.List[string]]::new()
    $atTopLevel = $true
    $skipProviderTable = $false
    foreach ($line in $existingLines) {
        if ($line -match '^\s*\[.*\]\s*$') {
            if ($line -match '^\s*\[model_providers\.unlimitds\]\s*$') {
                $skipProviderTable = $true
                $atTopLevel = $false
                continue
            }
            $skipProviderTable = $false
            $atTopLevel = $false
        }
        if ($skipProviderTable) {
            continue
        }
        if ($atTopLevel -and $line -match '^\s*(model|model_provider)\s*=') {
            continue
        }
        $preserved.Add($line)
    }

    while ($preserved.Count -gt 0 -and [string]::IsNullOrWhiteSpace($preserved[0])) {
        $preserved.RemoveAt(0)
    }
    while ($preserved.Count -gt 0 -and [string]::IsNullOrWhiteSpace($preserved[$preserved.Count - 1])) {
        $preserved.RemoveAt($preserved.Count - 1)
    }

    $output = [System.Collections.Generic.List[string]]::new()
    $output.Add("model = `"$Model`"")
    $output.Add('model_provider = "unlimitds"')
    if ($preserved.Count -gt 0) {
        $output.Add('')
        foreach ($line in $preserved) {
            $output.Add($line)
        }
    }
    $output.Add('')
    $output.Add('[model_providers.unlimitds]')
    $output.Add('name = "UnlimitDS"')
    $output.Add('base_url = "https://unlimitds.chat/v1"')
    $output.Add('env_key = "UNLIMITDS_API_KEY"')
    $output.Add('wire_api = "responses"')

    $temporaryPath = "$configPath.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        ($output -join "`n") + "`n" | Set-Content -LiteralPath $temporaryPath -Encoding utf8NoBOM -NoNewline
        Move-Item -LiteralPath $temporaryPath -Destination $configPath -Force
    }
    finally {
        if (Test-Path $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
    return $backupPath
}

function Set-PersistedVariables {
    param(
        [string]$HomePath,
        [hashtable]$Variables,
        [bool]$TestMode
    )

    foreach ($name in $Variables.Keys) {
        [Environment]::SetEnvironmentVariable($name, $Variables[$name], 'Process')
    }

    if ($TestMode) {
        $stateDirectory = Join-Path $HomePath '.unlimitds'
        New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null
        $Variables | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateDirectory 'test-user-env.json') -Encoding utf8NoBOM
        return
    }

    foreach ($name in $Variables.Keys) {
        [Environment]::SetEnvironmentVariable($name, $Variables[$name], 'User')
    }
}

try {
    $testMode = $env:UNLIMITDS_SETUP_TEST_MODE -eq '1'
    $homePath = if ($testMode -and $env:UNLIMITDS_SETUP_HOME) {
        [System.IO.Path]::GetFullPath($env:UNLIMITDS_SETUP_HOME)
    }
    else {
        [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    }

    $apiKey = if ($env:UNLIMITDS_API_KEY_INPUT) { $env:UNLIMITDS_API_KEY_INPUT.Trim() } else { Get-PlainTextSecret }
    if ($apiKey -notmatch '^uds_[A-Za-z0-9_-]{20,}$') {
        throw 'API Key 格式不正确，应以 uds_ 开头。'
    }

    $model = if ($Mode -eq 'jailbreak') { 'deepseek-v4-pro_jailbreak' } else { 'deepseek-v4-pro' }
    $skipApiCheck = $testMode -and $env:UNLIMITDS_SETUP_SKIP_API_CHECK -eq '1'
    $apiCheck = Test-ApiKey -ApiKey $apiKey -SkipCheck $skipApiCheck
    $clients = @(Get-ConfiguredClients -HomePath $homePath -TestMode $testMode)
    if ($clients.Count -eq 0) {
        throw '未检测到 Codex CLI 或 Claude Code，请先安装至少一个客户端。'
    }

    $backupPaths = [System.Collections.Generic.List[string]]::new()
    if ($clients -contains 'codex') {
        $backupPath = Update-CodexConfig -HomePath $homePath -Model $model
        if ($backupPath) {
            $backupPaths.Add($backupPath)
        }
    }

    $variables = @{ UNLIMITDS_API_KEY = $apiKey }
    if ($clients -contains 'claude') {
        $variables.ANTHROPIC_BASE_URL = 'https://unlimitds.chat'
        $variables.ANTHROPIC_AUTH_TOKEN = $apiKey
        $variables.ANTHROPIC_MODEL = $model
    }
    Set-PersistedVariables -HomePath $homePath -Variables $variables -TestMode $testMode

    [pscustomobject]@{
        ok = $true
        mode = $Mode
        model = $model
        configured_clients = @($clients)
        api_check = $apiCheck
        backup_paths = @($backupPaths)
        restart_required = $true
    } | ConvertTo-Json -Compress
}
catch {
    [Console]::Error.WriteLine("UnlimitDS 配置失败：$($_.Exception.Message)")
    exit 1
}
