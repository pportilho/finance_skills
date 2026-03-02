# install.ps1 — Finance Skills plugin installer (Windows / PowerShell)
#
# Usage:
#   .\install.ps1 -Plugin core         -Target C:\path\to\project
#   .\install.ps1 -Plugin all          -Target C:\path\to\project
#   .\install.ps1 -List
#
# Copies (not symlinks) each skill directory from the chosen plugin(s) into
# <Target>\.claude\skills\. Re-running is safe — existing skills are skipped.
# Unlike install.sh, copied skills are not automatically updated when the
# Finance Skills repo changes. Re-run the script to refresh.

param(
    [string] $Plugin = "",
    [string] $Target = "",
    [switch] $List,
    [switch] $Help
)

$ErrorActionPreference = "Stop"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$PluginsDir = Join-Path $ScriptDir "plugins"

$Dependencies = [ordered]@{
    "core"               = @()
    "wealth-management"  = @("core")
    "compliance"         = @("core")
    "advisory-practice"  = @("core", "wealth-management")
    "trading-operations" = @("core")
    "client-operations"  = @("core")
    "data-integration"   = @("core")
}

$AllPlugins = @(
    "core", "wealth-management", "compliance",
    "advisory-practice", "trading-operations",
    "client-operations", "data-integration"
)

$InstalledPlugins = @{}

# ---------------------------------------------------------------------------
# Usage / list
# ---------------------------------------------------------------------------

function Show-Usage {
    Write-Host "Usage: .\install.ps1 -Plugin <name> -Target <path>"
    Write-Host "       .\install.ps1 -Plugin all    -Target <path>"
    Write-Host "       .\install.ps1 -List"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Plugin <name>  Plugin to install ('all' installs every plugin)"
    Write-Host "  -Target <path>  Target project directory (creates .claude\skills\ if needed)"
    Write-Host "  -List           List available plugins and exit"
    Write-Host "  -Help           Show this help"
    Write-Host ""
    Write-Host "Available plugins:"
    Write-Host "  core               Mathematical foundations (always installed as dependency)"
    Write-Host "  wealth-management  Investment knowledge, portfolio construction, personal finance"
    Write-Host "  compliance         US securities regulatory guidance"
    Write-Host "  advisory-practice  Advisor-facing systems and workflows"
    Write-Host "  trading-operations Order lifecycle, execution, settlement"
    Write-Host "  client-operations  Account lifecycle and servicing"
    Write-Host "  data-integration   Reference data and integration patterns"
}

function Show-List {
    Write-Host "Available plugins:"
    Write-Host ""
    foreach ($name in $AllPlugins) {
        $manifest = Join-Path $PluginsDir "$name\plugin.json"
        $desc     = ""
        $count    = 0
        if (Test-Path $manifest) {
            $json  = Get-Content $manifest -Raw | ConvertFrom-Json
            $desc  = $json.description
            $skills = Join-Path $PluginsDir "$name\skills"
            if (Test-Path $skills) {
                $count = (Get-ChildItem -Path $skills -Directory).Count
            }
        }
        $deps = $Dependencies[$name]
        Write-Host "  $name ($count skills)"
        if ($desc)  { Write-Host "    $desc" }
        if ($deps)  { Write-Host "    Dependencies: $($deps -join ', ')" }
        Write-Host ""
    }
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

function Install-Plugin {
    param([string]$PluginName, [string]$TargetPath)

    if ($InstalledPlugins.ContainsKey($PluginName)) { return }

    $pluginDir = Join-Path $PluginsDir $PluginName
    if (-not (Test-Path $pluginDir)) {
        Write-Error "Unknown plugin: '$PluginName'. Run '.\install.ps1 -List' to see options."
        exit 1
    }

    # Install dependencies first
    foreach ($dep in $Dependencies[$PluginName]) {
        Install-Plugin -PluginName $dep -TargetPath $TargetPath
    }

    Write-Host "Installing plugin: $PluginName"

    $skillsTarget = Join-Path $TargetPath ".claude\skills"
    if (-not (Test-Path $skillsTarget)) {
        New-Item -ItemType Directory -Path $skillsTarget -Force | Out-Null
    }

    $pluginSkillsDir = Join-Path $pluginDir "skills"
    $count = 0

    if (Test-Path $pluginSkillsDir) {
        foreach ($skillDir in Get-ChildItem -Path $pluginSkillsDir -Directory) {
            $destPath = Join-Path $skillsTarget $skillDir.Name
            if (Test-Path $destPath) {
                Write-Host "  Skipping $($skillDir.Name) (already exists)"
            } else {
                Copy-Item -Path $skillDir.FullName -Destination $destPath -Recurse
                Write-Host "  Copied $($skillDir.Name)"
                $count++
            }
        }
        Write-Host "  $count skill(s) installed from $PluginName"
    } else {
        Write-Host "  Warning: no skills directory found for plugin '$PluginName'"
    }

    $InstalledPlugins[$PluginName] = $true
}

# ---------------------------------------------------------------------------
# Guide generation
# ---------------------------------------------------------------------------

function New-FinanceSkillsGuide {
    param([string]$TargetPath)

    $skillsDir = Join-Path $TargetPath ".claude\skills"
    $guidePath = Join-Path $TargetPath "FINANCE_SKILLS.md"

    $PluginOrder = [ordered]@{
        "core"               = "Core — Mathematical Foundations"
        "wealth-management"  = "Wealth Management — Investment & Portfolio"
        "compliance"         = "Compliance — Regulatory Guidance"
        "advisory-practice"  = "Advisory Practice — Advisor Workflows"
        "trading-operations" = "Trading Operations — Order Lifecycle"
        "client-operations"  = "Client Operations — Account Servicing"
        "data-integration"   = "Data Integration — Reference & Market Data"
    }

    # Collect skills grouped by plugin
    $pluginSkills = @{}  # plugin_name -> @{ name; desc; when }

    if (-not (Test-Path $skillsDir)) { return }

    foreach ($skillDir in (Get-ChildItem -Path $skillsDir -Directory | Sort-Object Name)) {
        $skillMd = Join-Path $skillDir.FullName "SKILL.md"
        if (-not (Test-Path $skillMd)) { continue }

        $content = Get-Content $skillMd -Raw -Encoding UTF8

        # Extract description from YAML frontmatter
        $desc = ""
        if ($content -match "(?s)^---(.+?)---") {
            $front = $Matches[1]
            if ($front -match 'description:\s*"?([^"\n]+)"?') {
                $desc = $Matches[1].Trim()
            }
        }

        # Extract first 4 "When to Use" bullets
        $whenItems = @()
        if ($content -match "(?s)## When to Use\n((?:- .+\n?)+)") {
            $whenBlock = $Matches[1]
            $whenItems = ([regex]::Matches($whenBlock, "- (.+)") | Select-Object -First 4).Value `
                         | ForEach-Object { $_ -replace "^- ", "" }
        }

        # Determine plugin from path
        $parts      = $skillDir.FullName -split "[/\\]"
        $pluginName = "unknown"
        for ($i = 0; $i -lt $parts.Count; $i++) {
            if ($parts[$i] -eq "skills" -and $i -gt 0) {
                $pluginName = $parts[$i - 1]
                break
            }
        }

        if (-not $pluginSkills.ContainsKey($pluginName)) {
            $pluginSkills[$pluginName] = [System.Collections.Generic.List[hashtable]]::new()
        }
        $pluginSkills[$pluginName].Add(@{ Name = $skillDir.Name; Desc = $desc; When = $whenItems })
    }

    $totalSkills  = ($pluginSkills.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
    $totalPlugins = $pluginSkills.Count

    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.AddRange([string[]]@(
        "# Finance Skills — Reference Guide",
        "",
        "This project has Finance Skills installed. Each skill teaches Claude domain",
        "knowledge about a specific area of financial services.",
        "",
        "Skills live in ``.claude\skills\``. Claude Code reads them automatically",
        "when you ask finance-related questions. Use natural language — the right",
        "skill activates based on context.",
        "",
        "**Installed:** $totalSkills skills across $totalPlugins plugin(s)",
        "",
        "---",
        "",
        "## For AI Assistants",
        "",
        "When working on this project with finance-related tasks:",
        "",
        "- **Before answering a quantitative question** (pricing, risk, returns,",
        "  volatility), read the relevant ``SKILL.md`` — it contains formulas,",
        "  worked examples, and common pitfalls.",
        "- **Python scripts** are in ``scripts\`` inside each skill directory.",
        "  They are standalone and importable:",
        "  ``````python",
        "  from volatility_modeling import VolatilityModeling",
        "  from forward_risk import ForwardRisk",
        "  from return_calculations import ReturnCalculations",
        "  ``````",
        "- **Compliance skills** cite specific rule numbers (FINRA, SEC, ERISA).",
        "  Always reference the rule when flagging a compliance concern.",
        "- **Cross-references** at the bottom of each SKILL.md point to related",
        "  skills — follow them to build a complete picture.",
        "- **Skill selection guide:** if unsure which skill applies, check the",
        "  ``## When to Use`` section of candidate skills.",
        "",
        "---",
        "",
        "## Quick Reference",
        "",
        "| Skill | Description |",
        "|-------|-------------|"
    ))

    foreach ($key in $PluginOrder.Keys) {
        if (-not $pluginSkills.ContainsKey($key)) { continue }
        foreach ($s in $pluginSkills[$key]) {
            $short = if ($s.Desc.Length -gt 80) { $s.Desc.Substring(0, 77) + "..." } else { $s.Desc }
            $lines.Add("| ``$($s.Name)`` | $short |")
        }
    }

    $lines.AddRange([string[]]@("", "---", "", "## Skills by Plugin", ""))

    foreach ($key in $PluginOrder.Keys) {
        if (-not $pluginSkills.ContainsKey($key)) { continue }
        $label = $PluginOrder[$key]
        $lines.AddRange([string[]]@("### $label", ""))
        foreach ($s in $pluginSkills[$key]) {
            $lines.AddRange([string[]]@("#### ``$($s.Name)``", ""))
            if ($s.Desc) { $lines.AddRange([string[]]@($s.Desc, "")) }
            if ($s.When.Count -gt 0) {
                $lines.Add("**Use when:**")
                foreach ($w in $s.When) { $lines.Add("- $w") }
                $lines.Add("")
            }
        }
    }

    $lines.AddRange([string[]]@(
        "---",
        "",
        "_Generated by Finance Skills installer. Re-run ``install.ps1`` to refresh._"
    ))

    $lines -join "`n" | Set-Content -Path $guidePath -Encoding UTF8
    Write-Host "  Guide: $guidePath"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if ($Help -or ($Plugin -eq "" -and -not $List)) {
    Show-Usage
    exit 0
}

if ($List) {
    Show-List
    exit 0
}

if ($Target -eq "") {
    Write-Error "-Target is required."
    Show-Usage
    exit 1
}

if (-not (Test-Path $Target)) {
    Write-Error "Target directory does not exist: $Target"
    exit 1
}

if ($Plugin -eq "all") {
    Write-Host "Installing all plugins into $Target\.claude\skills\"
    Write-Host ""
    foreach ($p in $AllPlugins) {
        Install-Plugin -PluginName $p -TargetPath $Target
    }
} else {
    Write-Host "Installing plugin '$Plugin' into $Target\.claude\skills\"
    Write-Host ""
    Install-Plugin -PluginName $Plugin -TargetPath $Target
}

Write-Host ""
New-FinanceSkillsGuide -TargetPath $Target

Write-Host ""
Write-Host "Done. Skills are available at $Target\.claude\skills\"
Write-Host "      Skills guide written to  $Target\FINANCE_SKILLS.md"
Write-Host ""
Write-Host "Note: Skills were copied (not symlinked). To pick up future updates"
Write-Host "      to Finance Skills, re-run this script."
