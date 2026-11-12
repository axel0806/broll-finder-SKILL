<#
.SYNOPSIS
  Install the broll-finder skill into one or more coding agents (Windows PowerShell 5.1+ and PowerShell 7).

.DESCRIPTION
  Copies broll-finder/SKILL.md into each chosen agent's skills folder under your Windows user profile.
  If run from a clone, it uses the local copy. Otherwise it downloads the file from GitHub.

.EXAMPLE
  .\install.ps1                         # checklist menu (detected agents pre-selected)
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
    Write-Host ('  {0,-20} {1,-11} {2}' -f 'Agent', '-Agent', 'Status')
    foreach ($a in $Agents) {
        Write-Host ('  {0,-20} {1,-11} ' -f $a.Name, $a.Id) -NoNewline
        if (Test-Path -LiteralPath $a.Detect) { Write-Host 'detected' -ForegroundColor Green } else { Write-Host 'not found' }
    }
}

# Interactive checklist: Up/Down or j/k move, Space toggles, a toggles all,
# Enter confirms, q/Esc cancels. Detected agents start selected.
# Returns the selected ids, or $null if cancelled.
function Select-AgentsMenu ([string]$Title) {
    $items = @(foreach ($a in $Agents) {
        $d = Test-Path -LiteralPath $a.Detect
        [pscustomobject]@{ Id = $a.Id; Name = $a.Name; Detected = $d; Selected = $d }
    })
    $cur = 0
    Write-Host $Title -ForegroundColor White
    Write-Host 'up/down or j/k: move   space: select   a: all   enter: continue   q: cancel' -ForegroundColor DarkGray
    foreach ($i in $items) { Write-Host '' }          # reserve the lines (handles buffer scrolling)
    $top = [Console]::CursorTop - $items.Count
    $width = [Math]::Max(20, [Math]::Min(60, [Console]::BufferWidth - 1))
    $cursorWas = $true
    try { $cursorWas = [Console]::CursorVisible; [Console]::CursorVisible = $false } catch {}

    $draw = {
        for ($n = 0; $n -lt $items.Count; $n++) {
            $it = $items[$n]
            [Console]::SetCursorPosition(0, $top + $n)
            if ($n -eq $cur) { $ptr = '  > ' } else { $ptr = '    ' }
            if ($it.Selected) { $box = '[x]' } else { $box = '[ ]' }
            if ($it.Detected) { $st = 'detected' } else { $st = 'not found' }
            Write-Host $ptr -NoNewline -ForegroundColor White
            if ($it.Selected) { Write-Host $box -NoNewline -ForegroundColor Green } else { Write-Host $box -NoNewline }
            $label = ' {0,-20} ' -f $it.Name
            if ($n -eq $cur) { Write-Host $label -NoNewline -ForegroundColor Black -BackgroundColor Gray } else { Write-Host $label -NoNewline }
            if ($it.Detected) { Write-Host $st -NoNewline -ForegroundColor Green } else { Write-Host $st -NoNewline -ForegroundColor DarkGray }
            Write-Host (' ' * [Math]::Max(0, $width - 4 - 3 - $label.Length - $st.Length)) -NoNewline
        }
    }

    try {
        while ($true) {
            & $draw
            $k = [Console]::ReadKey($true)
            $c = [string]$k.KeyChar
            if ($k.Key -eq 'UpArrow' -or $c -eq 'k' -or $c -eq 'K') {
                if ($cur -gt 0) { $cur-- } else { $cur = $items.Count - 1 }
            } elseif ($k.Key -eq 'DownArrow' -or $c -eq 'j' -or $c -eq 'J') {
                if ($cur -lt $items.Count - 1) { $cur++ } else { $cur = 0 }
            } elseif ($k.Key -eq 'Spacebar') {
                $items[$cur].Selected = -not $items[$cur].Selected
            } elseif ($c -eq 'a' -or $c -eq 'A') {
                $allOn = @($items | Where-Object { -not $_.Selected }).Count -eq 0
                foreach ($it in $items) { $it.Selected = -not $allOn }
            } elseif ($k.Key -eq 'Enter') {
                $sel = @($items | Where-Object { $_.Selected } | ForEach-Object { $_.Id })
                if ($sel.Count -gt 0) { return ,$sel }
                [Console]::Beep(800, 120)                 # nothing selected: stay in the menu
            } elseif ($k.Key -eq 'Escape' -or $c -eq 'q' -or $c -eq 'Q') {
                return $null
            }
        }
    } finally {
        try { [Console]::SetCursorPosition(0, $top + $items.Count) } catch {}
        try { [Console]::CursorVisible = $cursorWas } catch {}
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
        try {
            $canPrompt = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
        } catch { $canPrompt = $false }
        if ($canPrompt) {
            if ($Uninstall) { $verb = "Remove $SkillName from" } else { $verb = "Install $SkillName into" }
            $picked = Select-AgentsMenu "$verb which agents?"
            if ($null -eq $picked) {
                Write-Host 'Cancelled, nothing changed.'
                if ($PSCommandPath) { exit 1 } else { return }
            }
            $Agent = $picked
        }
        # No terminal (CI, redirected input): use every detected agent.
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
            Stop-Install 2 ("unknown agent '{0}'. Use one of: {1} all  (see -List)" -f $id, (($Agents | ForEach-Object { $_.Id }) -join ' '))
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
