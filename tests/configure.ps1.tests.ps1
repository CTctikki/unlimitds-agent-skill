$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\unlimitds-setup\scripts\configure.ps1'
$testKey = 'uds_test_key_12345678901234567890'
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message (expected: $Expected, actual: $Actual)"
    }
}

function New-TestHome {
    param([switch]$WithConfig)

    $homePath = Join-Path ([System.IO.Path]::GetTempPath()) ("unlimitds-ps-{0}" -f [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $homePath -Force | Out-Null
    if ($WithConfig) {
        $codexDirectory = Join-Path $homePath '.codex'
        New-Item -ItemType Directory -Path $codexDirectory -Force | Out-Null
        @'
model = "old-model"
model_provider = "openai"
approval_policy = "never"

[features]
multi_agent = true

[model_providers.other]
name = "Other"
base_url = "https://example.com/v1"

[model_providers.unlimitds]
name = "Old UnlimitDS"
base_url = "https://old.invalid/v1"

[projects."C:\\demo"]
trust_level = "trusted"
'@ | Set-Content -LiteralPath (Join-Path $codexDirectory 'config.toml') -Encoding utf8NoBOM
    }
    return $homePath
}

function Invoke-Setup {
    param(
        [string]$HomePath,
        [string]$Mode,
        [string]$ApiKey = $testKey,
        [string]$Clients = 'both'
    )

    $saved = @{}
    $variables = @{
        UNLIMITDS_SETUP_TEST_MODE = '1'
        UNLIMITDS_SETUP_HOME = $HomePath
        UNLIMITDS_SETUP_CLIENTS = $Clients
        UNLIMITDS_SETUP_SKIP_API_CHECK = '1'
        UNLIMITDS_API_KEY_INPUT = $ApiKey
    }
    foreach ($name in $variables.Keys) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, $variables[$name], 'Process')
    }

    try {
        $output = & pwsh -NoProfile -File $scriptPath -Mode $Mode 2>&1 | Out-String
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output.Trim() }
    }
    finally {
        foreach ($name in $variables.Keys) {
            [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
        }
    }
}

function Invoke-Test {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        Write-Host "PASS $Name"
    }
    catch {
        $failures.Add("$Name`: $($_.Exception.Message)")
        Write-Host "FAIL $Name"
    }
}

Invoke-Test 'standard mode preserves existing Codex configuration' {
    $homePath = New-TestHome -WithConfig
    try {
        $result = Invoke-Setup -HomePath $homePath -Mode standard
        Assert-Equal $result.ExitCode 0 $result.Output
        Assert-True (-not $result.Output.Contains($testKey)) 'Output leaked the API key'

        $configPath = Join-Path $homePath '.codex\config.toml'
        $content = Get-Content -LiteralPath $configPath -Raw
        Assert-True $content.Contains('model = "deepseek-v4-pro"') 'Standard model was not configured'
        Assert-Equal ([regex]::Matches($content, '(?m)^model_provider = "unlimitds"$').Count) 1 'Top-level provider count is wrong'
        Assert-Equal ([regex]::Matches($content, '(?m)^\[model_providers\.unlimitds\]$').Count) 1 'UnlimitDS provider table count is wrong'
        Assert-True $content.Contains('approval_policy = "never"') 'Unrelated top-level setting was removed'
        Assert-True $content.Contains('[model_providers.other]') 'Another provider table was removed'
        Assert-True $content.Contains('[projects."C:\\demo"]') 'Project settings were removed'
        Assert-True $content.Contains('base_url = "https://unlimitds.chat/v1"') 'Base URL is missing'
        Assert-True $content.Contains('env_key = "UNLIMITDS_API_KEY"') 'Environment key setting is missing'
        Assert-True $content.Contains('wire_api = "responses"') 'Responses protocol is missing'

        $backups = @(Get-ChildItem -LiteralPath (Split-Path $configPath) -Filter 'config.toml.unlimitds-backup-*')
        Assert-Equal $backups.Count 1 'Expected one Codex configuration backup'

        $environment = Get-Content -LiteralPath (Join-Path $homePath '.unlimitds\test-user-env.json') -Raw | ConvertFrom-Json
        Assert-Equal $environment.UNLIMITDS_API_KEY $testKey 'Codex key was not persisted'
        Assert-Equal $environment.ANTHROPIC_BASE_URL 'https://unlimitds.chat' 'Claude base URL was not persisted'
        Assert-Equal $environment.ANTHROPIC_MODEL 'deepseek-v4-pro' 'Claude standard model was not persisted'

        $summary = $result.Output | ConvertFrom-Json
        Assert-True $summary.ok 'Summary did not report success'
        Assert-Equal $summary.mode 'standard' 'Summary mode is wrong'
        Assert-Equal @($summary.configured_clients).Count 2 'Both clients should be configured'
    }
    finally {
        Remove-Item -LiteralPath $homePath -Recurse -Force
    }
}

Invoke-Test 'jailbreak mode is idempotent' {
    $homePath = New-TestHome -WithConfig
    try {
        $first = Invoke-Setup -HomePath $homePath -Mode jailbreak
        $second = Invoke-Setup -HomePath $homePath -Mode jailbreak
        Assert-Equal $first.ExitCode 0 $first.Output
        Assert-Equal $second.ExitCode 0 $second.Output

        $content = Get-Content -LiteralPath (Join-Path $homePath '.codex\config.toml') -Raw
        Assert-Equal ([regex]::Matches($content, '(?m)^model = "deepseek-v4-pro_jailbreak"$').Count) 1 'Jailbreak model count is wrong'
        Assert-Equal ([regex]::Matches($content, '(?m)^\[model_providers\.unlimitds\]$').Count) 1 'Provider block was duplicated'
        $environment = Get-Content -LiteralPath (Join-Path $homePath '.unlimitds\test-user-env.json') -Raw | ConvertFrom-Json
        Assert-Equal $environment.ANTHROPIC_MODEL 'deepseek-v4-pro_jailbreak' 'Claude jailbreak model was not persisted'
        Assert-True (-not $second.Output.Contains($testKey)) 'Repeated run leaked the API key'
    }
    finally {
        Remove-Item -LiteralPath $homePath -Recurse -Force
    }
}

Invoke-Test 'invalid key stops before mutation' {
    $homePath = New-TestHome -WithConfig
    try {
        $configPath = Join-Path $homePath '.codex\config.toml'
        $before = Get-Content -LiteralPath $configPath -Raw
        $result = Invoke-Setup -HomePath $homePath -Mode standard -ApiKey 'bad-key'
        Assert-True ($result.ExitCode -ne 0) 'Malformed key unexpectedly succeeded'
        Assert-Equal (Get-Content -LiteralPath $configPath -Raw) $before 'Configuration changed after invalid key'
        Assert-True (-not (Test-Path (Join-Path $homePath '.unlimitds\test-user-env.json'))) 'Environment changed after invalid key'
        Assert-True (-not $result.Output.Contains('bad-key')) 'Error output leaked the malformed key'
    }
    finally {
        Remove-Item -LiteralPath $homePath -Recurse -Force
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host "All PowerShell setup tests passed."
