<#
.SYNOPSIS
  Install the broll-finder skill into one or more coding agents (Windows PowerShell 5.1+ and PowerShell 7).

.DESCRIPTION
  Copies broll-finder/SKILL.md into each chosen agent's skills folder under your Windows user profile.
  If run from a clone, it uses the local copy. Otherwise it downloads the file from GitHub.

.EXAMPLE
  .\install.ps1                         # menu; pressing Enter (or no terminal) = every detected agent
  .\install.ps1 -Agent claude           # one agent
  .\install.ps1 -Agent claude,cursor    # several agents
  .\install.ps1 -Agent all              # every agent detected on this machine
  .\install.ps1 -Dest C:\my\skills      # a custom parent skills directory
  .\install.ps1 -Project                # .\.claude\skills in the current directory
  .\install.ps1 -Agent claude -Force    # update / replace an existing install
  .\install.ps1 -Agent claude -Uninstall
  .\install.ps1 -DryRun -Agent all

.EXAMPLE
  # Remote install, no clone needed (runs in its own scope, so your session settings are untouched):
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/axel0806/broll-finder-SKILL/main/install.ps1)))
  # Remote install with options:
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/axel0806/broll-finder-SKILL/main/install.ps1))) -Agent claude,cursor
#>
[CmdletBinding()]
param(
    [string[]]$Agent,
    [string]$Dest,
    [switch]$Project,
    [string]$Ref = 'main',
    [switch]$Force,
    [switch]$Uninstall,
    [switch]$DryRun,
    [switch]$List,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$SkillName = 'broll-finder'
$Repo      = 'axel0806/broll-finder-SKILL'
$HomeDir   = $env:USERPROFILE
if (-not $HomeDir) { $HomeDir = [Environment]::GetFolderPath('UserProfile') }

function Write-Ok   ($m) { Write-Host '  ok     ' -ForegroundColor Green -NoNewline; Write-Host $m }
function Write-Warn ($m) { Write-Host '  warn   ' -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Write-Err  ($m) { Write-Host "error: $m" -ForegroundColor Red }
function Invoke-Step ([string]$Desc, [scriptblock]$Action) {
    if ($DryRun) { Write-Host "  [dry-run] $Desc" } else { & $Action }
}
# Run from a file: exit with a code. Run via irm/scriptblock: throw, because
# 'exit' there would close the user's PowerShell window.
function Stop-Install ([int]$Code, [string]$Msg) {
    Write-Err $Msg
    if ($PSCommandPath) { exit $Code } else { throw "install failed: $Msg" }
}

# Supported agents: id, display name, detection dir, skills dir
$Agents = @(
    @{ Id = 'claude';   Name = 'Claude Code';         Detect = "$HomeDir\.claude";          Dir = "$HomeDir\.claude\skills" }
    @{ Id = 'codex';    Name = 'Codex CLI';           Detect = "$HomeDir\.codex";           Dir = "$HomeDir\.codex\skills" }
    @{ Id = 'gemini';   Name = 'Gemini CLI';          Detect = "$HomeDir\.gemini";          Dir = "$HomeDir\.gemini\skills" }
    @{ Id = 'copilot';  Name = 'GitHub Copilot CLI';  Detect = "$HomeDir\.copilot";         Dir = "$HomeDir\.copilot\skills" }
    @{ Id = 'cursor';   Name = 'Cursor';              Detect = "$HomeDir\.cursor";          Dir = "$HomeDir\.cursor\skills" }
    @{ Id = 'opencode'; Name = 'OpenCode';            Detect = "$HomeDir\.config\opencode"; Dir = "$HomeDir\.config\opencode\skills" }
    @{ Id = 'goose';    Name = 'Goose';               Detect = "$HomeDir\.config\goose";    Dir = "$HomeDir\.config\goose\skills" }
    @{ Id = 'agents';   Name = 'Generic (~/.agents)'; Detect = "$HomeDir\.agents";          Dir = "$HomeDir\.agents\skills" }
)

function Show-Agents {
    foreach ($a in $Agents) {
        Write-Host ('  {0,-9} {1,-20} ' -f $a.Id, $a.Name) -NoNewline
        if (Test-Path -LiteralPath $a.Detect) { Write-Host 'detected' -ForegroundColor Green } else { Write-Host 'not found' }
    }
}

if ($Help) {
    if ($PSCommandPath) { Get-Help $PSCommandPath -Detailed } else { Write-Host "See https://github.com/$Repo#install" }
    return
}
if ($List) { Show-Agents; return }

# ---- choose targets ---------------------------------------------------------
$Targets = @()
if ($Project) { $Dest = Join-Path (Get-Location).Path '.claude\skills' }

if ($Dest) {
    $Targets += @{ Label = $Dest; Dir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Dest) }
} else {
    if (-not $Agent) {
        $canPrompt = $false
        try { $canPrompt = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected } catch { $canPrompt = $false }
        if ($canPrompt) {
            Write-Host "Install $SkillName into which agents?" -ForegroundColor White
            Show-Agents
            try { $answer = Read-Host "Agent ids, comma-separated [Enter = all detected]" } catch { $answer = '' }
            if ($answer) { $Agent = @($answer) }
        }
        # No choice given (Enter, or no terminal): install into every detected agent.
        if (-not $Agent) { $Agent = @('all') }
    }

    # Accept both -Agent claude,codex and -Agent "claude,codex"
    $ids = @($Agent | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })

    if ($ids -contains 'all') {
        $ids = @($Agents | Where-Object { Test-Path -LiteralPath $_.Detect } | ForEach-Object { $_.Id })
        if ($ids.Count -eq 0) { Stop-Install 1 'no supported agents detected; use -Agent or -Dest' }
    }

    foreach ($id in $ids) {
        $a = $Agents | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if (-not $a) {
            Stop-Install 2 ("unknown agent '{0}'. Valid agents: {1} all" -f $id, (($Agents | ForEach-Object { $_.Id }) -join ' '))
        }
        $Targets += @{ Label = $a.Name; Dir = $a.Dir }
    }
}

# ---- uninstall --------------------------------------------------------------
if ($Uninstall) {
    Write-Host "Uninstalling $SkillName" -ForegroundColor White
    foreach ($t in $Targets) {
        $target = Join-Path $t.Dir $SkillName
        if (Test-Path -LiteralPath $target) {
            Invoke-Step "Remove-Item -Recurse -Force '$target'" { Remove-Item -LiteralPath $target -Recurse -Force }
            Write-Ok "removed  $($t.Label) ($target)"
        } else {
            Write-Warn "not installed in $($t.Label) ($target)"
        }
    }
    return
}

# ---- fetch and validate SKILL.md --------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("$SkillName." + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$tmpSkill = Join-Path $tmp 'SKILL.md'

try {
    $src = $null
    if ($PSCommandPath -and $Ref -eq 'main' -and -not $PSBoundParameters.ContainsKey('Ref')) {
        $local = Join-Path (Split-Path -Parent $PSCommandPath) "$SkillName\SKILL.md"
        if (Test-Path -LiteralPath $local) { $src = $local }
    }

    if ($src) {
        Copy-Item -LiteralPath $src -Destination $tmpSkill
        Write-Host "Source: local clone ($src)"
    } else {
        $url = "https://raw.githubusercontent.com/$Repo/$Ref/$SkillName/SKILL.md"
        Write-Host "Source: $url"
        # Windows PowerShell 5.1 may default to TLS 1.0, which GitHub rejects.
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
        try {
            Invoke-WebRequest -Uri $url -OutFile $tmpSkill -UseBasicParsing
        } catch {
            Stop-Install 1 "download failed: $($_.Exception.Message)"
        }
    }

    $lines = @(Get-Content -LiteralPath $tmpSkill -TotalCount 10)
    if ($lines.Count -eq 0 -or $lines[0].Trim() -ne '---' -or -not ($lines -match "^name: $SkillName\s*$")) {
        Stop-Install 1 'SKILL.md failed validation (missing frontmatter or wrong name); nothing installed'
    }

    # ---- install ------------------------------------------------------------
    Write-Host "Installing $SkillName" -ForegroundColor White
    $installed = 0; $replaced = 0; $skipped = 0
    foreach ($t in $Targets) {
        $target = Join-Path $t.Dir $SkillName
        $exists = Test-Path -LiteralPath $target
        if ($exists -and -not $Force) {
            Write-Warn "exists   $($t.Label) ($target); use -Force to replace"
            $skipped++; continue
        }
        $stage = Join-Path $t.Dir ".$SkillName.tmp.$PID"
        $dir = $t.Dir
        Invoke-Step "create '$stage' and copy SKILL.md" {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
            New-Item -ItemType Directory -Path $stage | Out-Null
            Copy-Item -LiteralPath $tmpSkill -Destination (Join-Path $stage 'SKILL.md')
        }
        if ($exists) {
            Invoke-Step "Remove-Item -Recurse -Force '$target'" { Remove-Item -LiteralPath $target -Recurse -Force }
        }
        Invoke-Step "move '$stage' -> '$target'" { Move-Item -LiteralPath $stage -Destination $target }
        if ($exists) { Write-Ok "replace  $($t.Label) ($target)"; $replaced++ }
        else         { Write-Ok "install  $($t.Label) ($target)"; $installed++ }
    }
    if ($DryRun) { Write-Host "Dry run, nothing changed: would install $installed, replace $replaced, skip $skipped." }
    else         { Write-Host "Done: $installed installed, $replaced replaced, $skipped skipped." }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- dependency check -------------------------------------------------------
# The skill shells out to these at run time, so check the PATH the agent will see.
# -CommandType Application ignores aliases/functions with the same name.
Write-Host 'Checking dependencies on PATH' -ForegroundColor White
$missing = @()
foreach ($dep in 'yt-dlp', 'ffmpeg', 'ffprobe') {
    $cmd = Get-Command $dep -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { Write-Ok "found    $dep ($($cmd.Source))" }
    else      { Write-Warn "missing  $dep"; $missing += $dep }
}
if ($missing.Count -gt 0) {
    Write-Host '         The skill needs yt-dlp to download and ffmpeg/ffprobe to merge and check clips.'
    Write-Host '         Install: winget install yt-dlp.yt-dlp Gyan.FFmpeg'
    Write-Host '         Then open a new terminal so the updated PATH is picked up.'
}
if (-not $DryRun -and ($installed + $replaced) -gt 0) { Write-Host "Restart your agent, then ask it for b-roll or run /$SkillName." }
