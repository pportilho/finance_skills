#!/usr/bin/env bash
# install.sh — Finance Skills plugin installer
#
# Usage:
#   ./install.sh --plugin <plugin-name> --target <path/to/project>
#   ./install.sh --plugin all --target <path/to/project>
#   ./install.sh --list
#
# The installer symlinks each skill directory from the chosen plugin(s) into
# <target>/.claude/skills/. The core plugin is always installed first.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$SCRIPT_DIR/plugins"

# Plugin dependency map (space-separated list of deps per plugin)
declare -A PLUGIN_DEPS
PLUGIN_DEPS["core"]=""
PLUGIN_DEPS["wealth-management"]="core"
PLUGIN_DEPS["compliance"]="core"
PLUGIN_DEPS["advisory-practice"]="core wealth-management"
PLUGIN_DEPS["trading-operations"]="core"
PLUGIN_DEPS["client-operations"]="core"
PLUGIN_DEPS["data-integration"]="core"

ALL_PLUGINS=(core wealth-management compliance advisory-practice trading-operations client-operations data-integration)

# Track installed plugins to avoid duplicates
declare -A INSTALLED_PLUGINS

usage() {
  cat <<EOF
Usage: $0 --plugin <plugin-name> --target <path>
       $0 --plugin all --target <path>
       $0 --list

Options:
  --plugin <name>   Plugin to install (or "all" to install everything)
  --target <path>   Target project directory (will create .claude/skills/ if needed)
  --list            List available plugins and exit
  --help            Show this help

Available plugins:
  core               Mathematical foundations (always installed)
  wealth-management  Investment knowledge, portfolio construction, personal finance
  compliance         US securities regulatory guidance
  advisory-practice  Advisor-facing systems and workflows
  trading-operations Order lifecycle, execution, settlement
  client-operations  Account lifecycle and servicing
  data-integration   Reference data and integration patterns
EOF
}

list_plugins() {
  local marketplace="$SCRIPT_DIR/marketplace.json"
  echo "Available plugins:"
  echo ""
  if [[ -f "$marketplace" ]]; then
    python3 - "$marketplace" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    catalog = json.load(f)

for plugin in catalog.get("plugins", []):
    name = plugin.get("name", "")
    description = plugin.get("description", "")
    skill_count = plugin.get("skillCount", len(plugin.get("skills", [])))
    deps = plugin.get("dependencies", [])
    print(f"  {name} ({skill_count} skills)")
    print(f"    {description}")
    if deps:
        print(f"    Dependencies: {' '.join(deps)}")
    print()
PYEOF
  else
    # Fallback: read individual plugin.json files
    for plugin in "${ALL_PLUGINS[@]}"; do
      manifest="$PLUGINS_DIR/$plugin/plugin.json"
      if [[ -f "$manifest" ]]; then
        description=$(python3 -c "import json,sys; d=json.load(open('$manifest')); print(d.get('description',''))" 2>/dev/null || echo "")
        skill_count=$(ls "$PLUGINS_DIR/$plugin/skills/" 2>/dev/null | wc -l | tr -d ' ')
        echo "  $plugin ($skill_count skills)"
        echo "    $description"
        deps="${PLUGIN_DEPS[$plugin]:-}"
        if [[ -n "$deps" ]]; then
          echo "    Dependencies: $deps"
        fi
        echo ""
      fi
    done
  fi
}

install_plugin() {
  local plugin="$1"
  local target="$2"
  local skills_dir="$target/.claude/skills"

  # Skip if already installed in this run
  if [[ -n "${INSTALLED_PLUGINS[$plugin]+_}" ]]; then
    return 0
  fi

  # Validate plugin exists
  if [[ ! -d "$PLUGINS_DIR/$plugin" ]]; then
    echo "Error: Unknown plugin '$plugin'" >&2
    echo "Run '$0 --list' to see available plugins." >&2
    exit 1
  fi

  # Install dependencies first
  local deps="${PLUGIN_DEPS[$plugin]:-}"
  for dep in $deps; do
    install_plugin "$dep" "$target"
  done

  echo "Installing plugin: $plugin"

  # Create target skills directory if needed
  mkdir -p "$skills_dir"

  # Symlink each skill directory
  local plugin_skills_dir="$PLUGINS_DIR/$plugin/skills"
  if [[ -d "$plugin_skills_dir" ]]; then
    local count=0
    for skill_dir in "$plugin_skills_dir"/*/; do
      if [[ -d "$skill_dir" ]]; then
        skill_name="$(basename "$skill_dir")"
        link_path="$skills_dir/$skill_name"
        if [[ -e "$link_path" || -L "$link_path" ]]; then
          echo "  Skipping $skill_name (already exists)"
        else
          ln -s "$skill_dir" "$link_path"
          echo "  Linked $skill_name"
          count=$((count + 1))
        fi
      fi
    done
    echo "  $count skill(s) installed from $plugin"
  else
    echo "  Warning: no skills directory found for plugin '$plugin'"
  fi

  INSTALLED_PLUGINS[$plugin]=1
}

generate_guide() {
  local target="$1"
  local skills_dir="$target/.claude/skills"
  local guide_path="$target/FINANCE_SKILLS.md"

  python3 - "$skills_dir" "$guide_path" <<'PYEOF'
import os, sys, re

skills_dir = sys.argv[1]
guide_path = sys.argv[2]

PLUGIN_ORDER = [
    ("core",               "Core — Mathematical Foundations"),
    ("wealth-management",  "Wealth Management — Investment & Portfolio"),
    ("compliance",         "Compliance — Regulatory Guidance"),
    ("advisory-practice",  "Advisory Practice — Advisor Workflows"),
    ("trading-operations", "Trading Operations — Order Lifecycle"),
    ("client-operations",  "Client Operations — Account Servicing"),
    ("data-integration",   "Data Integration — Reference & Market Data"),
]

def get_frontmatter_field(content, field):
    if not content.startswith("---"):
        return ""
    end = content.find("---", 3)
    if end < 0:
        return ""
    for line in content[3:end].splitlines():
        if line.startswith(f"{field}:"):
            return line.split(":", 1)[1].strip().strip("\"'")
    return ""

def get_when_to_use(content, n=4):
    m = re.search(r"## When to Use\n((?:- .+\n?)+)", content)
    if not m:
        return []
    return re.findall(r"- (.+)", m.group(1))[:n]

# Collect skills, grouped by plugin
plugin_skills = {}   # plugin_name -> [(skill_name, description, [when_items])]

if not os.path.isdir(skills_dir):
    sys.exit(0)

for entry in sorted(os.listdir(skills_dir)):
    skill_path = os.path.join(skills_dir, entry)
    real_path  = os.path.realpath(skill_path)
    if not os.path.isdir(real_path):
        continue
    skill_md = os.path.join(real_path, "SKILL.md")
    if not os.path.isfile(skill_md):
        continue

    with open(skill_md, encoding="utf-8") as f:
        content = f.read()

    description = get_frontmatter_field(content, "description")
    when_items  = get_when_to_use(content)

    # Determine plugin from real path: .../plugins/<plugin>/skills/<skill>/
    parts = real_path.replace("\\", "/").split("/")
    plugin_name = "unknown"
    for i, part in enumerate(parts):
        if part == "skills" and i > 0:
            plugin_name = parts[i - 1]
            break

    plugin_skills.setdefault(plugin_name, []).append((entry, description, when_items))

total_skills   = sum(len(v) for v in plugin_skills.values())
total_plugins  = len(plugin_skills)

lines = []
lines += [
    "# Finance Skills — Reference Guide",
    "",
    "This project has Finance Skills installed. Each skill teaches Claude domain",
    "knowledge about a specific area of financial services.",
    "",
    "Skills live in `.claude/skills/`. Claude Code reads them automatically",
    "when you ask finance-related questions. Use natural language — the right",
    "skill activates based on context.",
    "",
    f"**Installed:** {total_skills} skills across {total_plugins} plugin(s)",
    "",
    "---",
    "",
    "## For AI Assistants",
    "",
    "When working on this project with finance-related tasks:",
    "",
    "- **Before answering a quantitative question** (pricing, risk, returns,",
    "  volatility), read the relevant `SKILL.md` — it contains formulas,",
    "  worked examples, and common pitfalls.",
    "- **Python scripts** are in `scripts/` inside each skill directory.",
    "  They are standalone and importable:",
    "  ```python",
    "  from volatility_modeling import VolatilityModeling",
    "  from forward_risk import ForwardRisk",
    "  from return_calculations import ReturnCalculations",
    "  ```",
    "- **Compliance skills** cite specific rule numbers (FINRA, SEC, ERISA).",
    "  Always reference the rule when flagging a compliance concern.",
    "- **Cross-references** at the bottom of each SKILL.md point to related",
    "  skills — follow them to build a complete picture.",
    "- **Skill selection guide:** if unsure which skill applies, check the",
    "  `## When to Use` section of candidate skills.",
    "",
    "---",
    "",
    "## Quick Reference",
    "",
    "| Skill | Description |",
    "|-------|-------------|",
]

for plugin_key, _ in PLUGIN_ORDER:
    for skill_name, desc, _ in plugin_skills.get(plugin_key, []):
        short = (desc[:77] + "...") if len(desc) > 80 else desc
        lines.append(f"| `{skill_name}` | {short} |")

lines += ["", "---", "", "## Skills by Plugin", ""]

for plugin_key, plugin_label in PLUGIN_ORDER:
    skills = plugin_skills.get(plugin_key)
    if not skills:
        continue
    lines += [f"### {plugin_label}", ""]
    for skill_name, desc, when_items in skills:
        lines += [f"#### `{skill_name}`", ""]
        if desc:
            lines += [desc, ""]
        if when_items:
            lines.append("**Use when:**")
            for item in when_items:
                lines.append(f"- {item}")
            lines.append("")

lines += [
    "---",
    "",
    "_Generated by Finance Skills installer. Re-run `install.sh` to refresh._",
]

with open(guide_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

print(f"  Guide: {guide_path}")
PYEOF
}

# --- Parse arguments ---

PLUGIN=""
TARGET=""
CMD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin)
      PLUGIN="$2"
      shift 2
      ;;
    --target)
      TARGET="$2"
      shift 2
      ;;
    --list)
      CMD="list"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$CMD" == "list" ]]; then
  list_plugins
  exit 0
fi

# Validate required arguments
if [[ -z "$PLUGIN" ]]; then
  echo "Error: --plugin is required" >&2
  usage >&2
  exit 1
fi

if [[ -z "$TARGET" ]]; then
  echo "Error: --target is required" >&2
  usage >&2
  exit 1
fi

# Validate target directory
if [[ ! -d "$TARGET" ]]; then
  echo "Error: Target directory does not exist: $TARGET" >&2
  exit 1
fi

# Install
if [[ "$PLUGIN" == "all" ]]; then
  echo "Installing all plugins into $TARGET/.claude/skills/"
  echo ""
  for p in "${ALL_PLUGINS[@]}"; do
    install_plugin "$p" "$TARGET"
  done
else
  echo "Installing plugin '$PLUGIN' into $TARGET/.claude/skills/"
  echo ""
  install_plugin "$PLUGIN" "$TARGET"
fi

generate_guide "$TARGET"

echo ""
echo "Done. Skills are available at $TARGET/.claude/skills/"
echo "      Skills guide written to  $TARGET/FINANCE_SKILLS.md"
