#!/usr/bin/env bash
# install.sh — install codex-router-skill into ZCode or Claude Code user dirs.
#
# Targets:
#   --target zcode   (default)  ~/.agents/skills, ~/.zcode/agents, ~/.zcode/AGENTS.md
#   --target claude             ~/.claude/skills, ~/.claude/agents, ~/.claude/CLAUDE.md
#
# Linking:
#   Symlinks by default so `git pull` keeps you up to date.
#   On Windows (MSYS/MINGW/Cygwin) symlinks usually need developer mode or
#   admin rights, so we auto-fall-back to copying. Force either with
#   --symlink or --copy.
#
# Idempotent: re-running safely overwrites stale links/copies.
set -euo pipefail

# --- args -------------------------------------------------------------------------
TARGET="zcode"
LINK_MODE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            [[ $# -ge 2 ]] || { echo "ERROR: --target requires a value (zcode|claude)" >&2; exit 1; }
            TARGET="$2"; shift 2 ;;
        --zcode)  TARGET="zcode"; shift ;;
        --claude) TARGET="claude"; shift ;;
        --copy)   LINK_MODE="copy"; shift ;;
        --symlink) LINK_MODE="symlink"; shift ;;
        -h|--help)
            sed -n '2,16p' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument '$1' (run with --help for usage)" >&2
            exit 1 ;;
    esac
done

# Validate target.
case "$TARGET" in
    zcode|claude) ;;
    *) echo "ERROR: --target must be 'zcode' or 'claude' (got '$TARGET')" >&2; exit 1 ;;
esac

# Auto-detect copy mode on Windows if not explicitly forced.
if [[ -z "$LINK_MODE" ]]; then
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*) LINK_MODE="copy" ;;
        *) LINK_MODE="symlink" ;;
    esac
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- target-specific paths --------------------------------------------------------
if [[ "$TARGET" == "zcode" ]]; then
    SKILLS_DIR="$HOME/.agents/skills"
    AGENTS_DIR="$HOME/.zcode/agents"
    BASELINE_FILE="$HOME/.zcode/AGENTS.md"
    TARGET_LABEL="ZCode"
else
    SKILLS_DIR="$HOME/.claude/skills"
    AGENTS_DIR="$HOME/.claude/agents"
    BASELINE_FILE="$HOME/.claude/CLAUDE.md"
    TARGET_LABEL="Claude Code"
fi

echo "Installing codex-router-skill (target: $TARGET_LABEL, mode: $LINK_MODE)"
echo "  source: $REPO_ROOT"
echo ""

# install_path SRC DST  — link or copy SRC to DST (file or dir).
install_path() {
    local src="$1" dst="$2"
    if [[ -L "$dst" || -e "$dst" ]]; then
        echo "  • Removing existing $dst"
        rm -rf "$dst"
    fi
    if [[ "$LINK_MODE" == "symlink" ]]; then
        ln -s "$src" "$dst"
        echo "  ✓ Linked: $dst -> $src"
    else
        if [[ -d "$src" ]]; then
            cp -r "$src" "$dst"
        else
            cp "$src" "$dst"
        fi
        echo "  ✓ Copied: $src -> $dst"
    fi
}

# --- 1. Skill (with references) ---------------------------------------------------
mkdir -p "$SKILLS_DIR"
install_path "$REPO_ROOT/skills/codex-router" "$SKILLS_DIR/codex-router"

# --- 2. Subagent (direct-exec backend; always installed as fallback) --------------
mkdir -p "$AGENTS_DIR"
install_path "$REPO_ROOT/agents/codex-engineer.md" "$AGENTS_DIR/codex-engineer.md"

# --- 3. Baseline rules (idempotent by marker) -------------------------------------
MARKER="<!-- codex-router-skill baseline -->"
BASELINE_SRC="$REPO_ROOT/AGENTS.md"

if [[ ! -f "$BASELINE_FILE" ]]; then
    {
        echo "$MARKER"
        cat "$BASELINE_SRC"
    } > "$BASELINE_FILE"
    echo "  ✓ Created $BASELINE_FILE"
elif grep -q "$MARKER" "$BASELINE_FILE" 2>/dev/null; then
    echo "  • $BASELINE_FILE already has baseline marker — skipping append"
    echo "    (if the repo's AGENTS.md changed, manually merge the new version)"
else
    {
        echo ""
        echo "$MARKER"
        cat "$BASELINE_SRC"
    } >> "$BASELINE_FILE"
    echo "  ✓ Appended baseline to $BASELINE_FILE"
fi

# --- 4. Verify Codex CLI ----------------------------------------------------------
if command -v codex >/dev/null 2>&1; then
    echo ""
    echo "  ✓ Codex CLI found: $(codex --version 2>&1 || echo 'version unknown')"
else
    echo ""
    echo "  ⚠ Codex CLI not found on PATH."
    echo "    Install it (https://github.com/openai/codex) and run 'codex login'"
    echo "    before the execution layer can delegate work."
fi

# --- 5. Claude Code: hint at the OpenAI plugin backend ---------------------------
if [[ "$TARGET" == "claude" ]]; then
    echo ""
    echo "  ℹ On Claude Code, the recommended execution backend is OpenAI's codex plugin"
    echo "    (background jobs, resume, session transfer, robust review). Install it with:"
    echo "      /plugin marketplace add openai/codex-plugin-cc"
    echo "      /plugin install codex@openai-codex"
    echo "      /reload-plugins && /codex:setup"
    echo "    The installed codex-engineer subagent (direct 'codex exec') remains as a fallback."
fi

echo ""
echo "Done. Restart any open $TARGET_LABEL session to pick up the new skill."
