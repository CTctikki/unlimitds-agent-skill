$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-RepositoryCondition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-RepositoryTest {
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

Invoke-RepositoryTest 'skill frontmatter is discoverable' {
    $skillPath = Join-Path $repositoryRoot 'unlimitds-setup\SKILL.md'
    Assert-RepositoryCondition (Test-Path $skillPath) 'SKILL.md is missing'
    $skill = Get-Content -LiteralPath $skillPath -Raw
    Assert-RepositoryCondition ($skill -match '(?m)^name: unlimitds-setup$') 'Skill name is incorrect'
    Assert-RepositoryCondition ($skill -match '(?m)^description: Use when .+$') 'Description must start with Use when'
}

Invoke-RepositoryTest 'skill limits novice interaction to key and mode' {
    $skill = Get-Content -LiteralPath (Join-Path $repositoryRoot 'unlimitds-setup\SKILL.md') -Raw
    Assert-RepositoryCondition $skill.Contains('只收集两个输入') 'Two-input limit is not explicit'
    Assert-RepositoryCondition $skill.Contains('API Key') 'API Key prompt is missing'
    Assert-RepositoryCondition $skill.Contains('标准模式') 'Standard mode is missing'
    Assert-RepositoryCondition $skill.Contains('破甲模式') 'Jailbreak mode is missing'
    Assert-RepositoryCondition $skill.Contains('选择模式即表示授权') 'Mode choice must authorize the listed changes'
}

Invoke-RepositoryTest 'skill dispatches deterministic scripts safely' {
    $skill = Get-Content -LiteralPath (Join-Path $repositoryRoot 'unlimitds-setup\SKILL.md') -Raw
    foreach ($required in @('configure.ps1', 'configure.sh', 'standard', 'jailbreak', '重启')) {
        Assert-RepositoryCondition $skill.Contains($required) "Missing required workflow term: $required"
    }
    Assert-RepositoryCondition ($skill -match '不得.{0,30}(输出|回显|记录).{0,30}(完整|明文).{0,20}(API Key|密钥)') 'Secret-output prohibition is missing'
    Assert-RepositoryCondition ($skill -match '脚本.{0,20}(缺失|不可用).{0,30}(停止|终止)') 'Missing-script stop condition is absent'
}

Invoke-RepositoryTest 'Codex skill metadata is present' {
    $metadataPath = Join-Path $repositoryRoot 'unlimitds-setup\agents\openai.yaml'
    Assert-RepositoryCondition (Test-Path $metadataPath) 'agents/openai.yaml is missing'
    $metadata = Get-Content -LiteralPath $metadataPath -Raw
    Assert-RepositoryCondition ($metadata -match '(?m)^\s*display_name:\s*".+"$') 'Display name is missing'
    Assert-RepositoryCondition ($metadata -match '(?m)^\s*short_description:\s*".+"$') 'Short description is missing'
    Assert-RepositoryCondition ($metadata -match '(?m)^\s*default_prompt:\s*".*\$unlimitds-setup.*"$') 'Default prompt must invoke the skill'
}

Invoke-RepositoryTest 'novice README provides one-copy installation' {
    $readmePath = Join-Path $repositoryRoot 'README.md'
    Assert-RepositoryCondition (Test-Path $readmePath) 'README.md is missing'
    $readme = Get-Content -LiteralPath $readmePath -Raw
    foreach ($required in @(
        'https://github.com/CTctikki/unlimitds-agent-skill/tree/main/unlimitds-setup',
        '~/.codex/skills/unlimitds-setup',
        '~/.claude/skills/unlimitds-setup',
        '标准模式',
        '破甲模式',
        '重启',
        'https://unlimitds.chat'
    )) {
        Assert-RepositoryCondition $readme.Contains($required) "README is missing: $required"
    }
    Assert-RepositoryCondition ($readme -match '(?s)复制.{0,20}(下面|这段).{0,1000}安装') 'Copy-paste Agent prompt is missing'
    Assert-RepositoryCondition ($readme -match 'API Key.{0,40}(密码|密钥)') 'API key safety warning is missing'
    Assert-RepositoryCondition ($readme -match '(非官方|Unofficial)') 'Unofficial-project notice is missing'
}

Invoke-RepositoryTest 'public repository files are complete' {
    $licensePath = Join-Path $repositoryRoot 'LICENSE'
    Assert-RepositoryCondition (Test-Path $licensePath) 'LICENSE is missing'
    Assert-RepositoryCondition ((Get-Content -LiteralPath $licensePath -Raw).Contains('MIT License')) 'MIT license is missing'
    $ignore = Get-Content -LiteralPath (Join-Path $repositoryRoot '.gitignore') -Raw
    foreach ($entry in @('.env', '.unlimitds/', '.worktrees/')) {
        Assert-RepositoryCondition $ignore.Contains($entry) ".gitignore is missing $entry"
    }
}

Invoke-RepositoryTest 'repository contains no likely real UnlimitDS key' {
    $candidateFiles = Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File | Where-Object {
        $_.FullName -notmatch '[\\/]\.git([\\/]|$)' -and
        $_.FullName -notmatch '[\\/]\.worktrees([\\/]|$)'
    }
    foreach ($file in $candidateFiles) {
        $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match 'uds_(?!test_|YOUR_KEY)[A-Za-z0-9_-]{20,}') {
            throw "Possible real API key found in $($file.FullName)"
        }
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host 'All repository contract tests passed.'
