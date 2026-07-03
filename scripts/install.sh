#!/usr/bin/env bash
# install.sh — install codex-router-skill into ZCode / Claude Code user dirs.
#
# Installs via symlink so `git pull` keeps you up to date.
# Idempotent: re-running safely overwrites stale symlinks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

AGENTS_DIR="$HOME/.agents"
ZCODE_AGENTS_DIR="$HOME/.zcode/agents"
ZCODE_AGENTS_MD="$HOME/.zcode/AGENTS.md"

echo "Installing codex-router-skill from: $REPO_ROOT"
echo ""

# --- 1. Skill (with references) -------------------------------------------------
SKILL_SRC="$REPO_ROOT/skills/codex-router"
SKILL_DST="$AGENTS_DIR/skills/codex-router"

mkdir -p "$AGENTS_DIR/skills"
if [[ -L "$SKILL_DST" || -e "$SKILL_DST" ]]; then
    echo "  • Removing existing skill at $SKILL_DST"
    rm -rf "$SKILL_DST"
fi
ln -s "$SKILL_SRC" "$SKILL_DST"
echo "  ✓ Linked skill: $SKILL_DST -> $SKILL_SRC"

# --- 2. Subagent ----------------------------------------------------------------
AGENT_SRC="$REPO_ROOT/agents/codex-engineer.md"
AGENT_DST="$ZCODE_AGENTS_DIR/codex-engineer.md"

mkdir -p "$ZCODE_AGENTS_DIR"
if [[ -L "$AGENT_DST" || -e "$AGENT_DST" ]]; then
    echo "  • Removing existing subagent at $AGENT_DST"
    rm -f "$AGENT_DST"
fi
ln -s "$AGENT_SRC" "$AGENT_DST"
echo "  ✓ Linked subagent: $AGENT_DST -> $AGENT_SRC"

# --- 3. AGENTS.md baseline ------------------------------------------------------
# Append if not already present (idempotent by marker).
MARKER="<!-- codex-router-skill baseline -->"
BASELINE_SRC="$REPO_ROOT/AGENTS.md"

if [[ ! -f "$ZCODE_AGENTS_MD" ]]; then
    {
        echo "$MARKER"
        cat "$BASELINE_SRC"
    } > "$ZCODE_AGENTS_MD"
    echo "  ✓ Created $ZCODE_AGENTS_MD"
elif grep -q "$MARKER" "$ZCODE_AGENTS_MD" 2>/dev/null; then
    echo "  • $ZCODE_AGENTS_MD already has baseline marker — skipping append"
    echo "    (if you upgraded the repo's AGENTS.md, manually merge the new version)"
else
    {
        echo ""
        echo "$MARKER"
        cat "$BASELINE_SRC"
    } >> "$ZCODE_AGENTS_MD"
    echo "  ✓ Appended baseline to $ZCODE_AGENTS_MD"
fi

# --- 4. Verify Codex CLI --------------------------------------------------------
if command -v codex >/dev/null 2>&1; then
    echo ""
    echo "  ✓ Codex CLI found: $(codex --version 2>&1 || echo 'version unknown')"
else
    echo ""
    echo "  ⚠ Codex CLI not found on PATH."
    echo "    Install it (https://github.com/openai/codex) and run 'codex login'"
    echo "    before the codex-engineer subagent can delegate work."
fi

echo ""
echo "Done. Restart any open ZCode/Claude Code session to pick up the new skill."
