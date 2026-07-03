#!/usr/bin/env bash
# install.sh — install codex-router-skill into ZCode or Claude Code user dirs.
#
# Targets:
#   --target zcode   (default)  ~/.agents/skills, ~/.zcode/agents, ~/.zcode/AGENTS.md
#   --target claude             ~/.claude/skills, ~/.claude/agents, ~/.claude/CLAUDE.md
# Routing profiles:
#   --profile savings     (default) Codex only for proven hard/high-risk work
#   --profile balanced              earlier Codex planning/review for complex work
#   --profile quality               more Codex judgment for taste/risk-heavy work
#   --profile codex-heavy           short bursts where quality/independence beats cost
#   --profile glm-only              never use Codex unless the user explicitly asks
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
PROFILE="savings"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            [[ $# -ge 2 ]] || { echo "ERROR: --target requires a value (zcode|claude)" >&2; exit 1; }
            TARGET="$2"; shift 2 ;;
        --profile)
            [[ $# -ge 2 ]] || { echo "ERROR: --profile requires a value (glm-only|savings|balanced|quality|codex-heavy)" >&2; exit 1; }
            PROFILE="$2"; shift 2 ;;
        --zcode)  TARGET="zcode"; shift ;;
        --claude) TARGET="claude"; shift ;;
        --copy)   LINK_MODE="copy"; shift ;;
        --symlink) LINK_MODE="symlink"; shift ;;
        -h|--help)
            sed -n '2,20p' "$0"
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

# Validate routing profile.
case "$PROFILE" in
    glm-only|savings|balanced|quality|codex-heavy) ;;
    *) echo "ERROR: --profile must be one of: glm-only, savings, balanced, quality, codex-heavy (got '$PROFILE')" >&2; exit 1 ;;
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
echo "  routing profile: $PROFILE"
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

PROFILE_BEGIN="<!-- codex-router-skill routing-profile:start -->"
PROFILE_END="<!-- codex-router-skill routing-profile:end -->"

profile_block() {
    local label ratio gate retry
    case "$PROFILE" in
        glm-only)
            label="GLM-only lockdown"
            ratio="GLM 100% / Codex 0%, unless the user explicitly asks for Codex"
            gate="Do not delegate to Codex automatically. Use GLM plus local tools and fresh-context GLM review."
            retry="If GLM fails twice, pause and ask whether to spend Codex budget."
            ;;
        savings)
            label="savings-first default"
            ratio="GLM 90-95% / Codex 5-10%"
            gate="Delegate only after GLM misses a concrete acceptance criterion, or for high-risk read-only second opinions."
            retry="Give GLM one focused attempt before upgrading, unless the task is clearly architecture/high-risk from the start."
            ;;
        balanced)
            label="balanced engineering"
            ratio="GLM 75-85% / Codex 15-25%"
            gate="Use Codex earlier for cross-module design, ambiguous debugging, and pre-implementation review; return mechanical execution to GLM."
            retry="Give GLM a small pilot first, then upgrade if the pilot exposes design uncertainty or brittle coupling."
            ;;
        quality)
            label="quality-first delivery"
            ratio="GLM 60-70% / Codex 30-40%"
            gate="Use Codex for architecture, API/taste-heavy work, high-risk reviews, and rescue before repeated GLM retries."
            retry="Prefer one strong Codex pass over multiple GLM retries when acceptance risk is material."
            ;;
        codex-heavy)
            label="Codex-heavy burst"
            ratio="GLM 40-60% / Codex 40-60%, for short bounded windows"
            gate="Use Codex for initial design, risky implementation, and independent review; keep GLM on exploration, evidence packing, and mechanical follow-through."
            retry="Stop after the agreed burst budget or two Codex attempts, then downgrade or ask for a new budget."
            ;;
    esac

    cat <<EOF
$PROFILE_BEGIN
## Codex Router Active Routing Profile

Active profile: **$PROFILE** ($label)
Soft ratio target: **$ratio**

Default Codex gate:
$gate

Retry / upgrade rule:
$retry

Standing policy:
- Treat the ratio as an audit target, not a random scheduler. Never route easy work to Codex just to hit a percentage.
- User instructions in the current task override this profile.
- If Codex is unavailable, mark the run GLM-only and use a fresh-context GLM verifier for high-risk checks.
$PROFILE_END
EOF
}

install_profile_block() {
    local block_file merged_file
    block_file="$(mktemp)"
    profile_block > "$block_file"

    if [[ -f "$BASELINE_FILE" ]] && grep -qF "$PROFILE_BEGIN" "$BASELINE_FILE" 2>/dev/null && grep -qF "$PROFILE_END" "$BASELINE_FILE" 2>/dev/null; then
        merged_file="$(mktemp)"
        awk -v begin="$PROFILE_BEGIN" -v end="$PROFILE_END" -v block_file="$block_file" '
            BEGIN {
                while ((getline line < block_file) > 0) {
                    replacement = replacement line ORS
                }
                close(block_file)
            }
            $0 == begin {
                printf "%s", replacement
                in_profile = 1
                next
            }
            $0 == end {
                in_profile = 0
                next
            }
            !in_profile { print }
        ' "$BASELINE_FILE" > "$merged_file"
        mv "$merged_file" "$BASELINE_FILE"
        echo "  ✓ Updated routing profile in $BASELINE_FILE"
    else
        {
            echo ""
            cat "$block_file"
        } >> "$BASELINE_FILE"
        if [[ -f "$BASELINE_FILE" ]] && grep -qF "$PROFILE_BEGIN" "$BASELINE_FILE" 2>/dev/null; then
            echo "  ✓ Appended routing profile to $BASELINE_FILE"
        fi
    fi

    rm -f "$block_file"
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

install_profile_block

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
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*)
            echo ""
            echo "  ⚠ Windows note: the OpenAI plugin backend is currently blocked here — Codex's"
            echo "    Windows sandbox runner times out under Claude Code (openai/codex#30839; UAC"
            echo "    does not fix it). On Windows, rely on the codex-engineer subagent with the"
            echo "    global sandbox_mode=\"danger-full-access\" (no -s). See"
            echo "    docs/windows-sandbox.md for details."
            ;;
    esac
fi

echo ""
echo "Done. Restart any open $TARGET_LABEL session to pick up the new skill."
