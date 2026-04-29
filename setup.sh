#!/usr/bin/env bash
# secrets-helper setup wizard
# Creates configurable macOS keychain tiers for tiered secret storage.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERSION="$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "unknown")"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/secrets-helper"
readonly CONFIG_FILE="$CONFIG_DIR/config.sh"
readonly KEYCHAIN_DIR="$HOME/Library/Keychains"
readonly SKILL_DIR="$SCRIPT_DIR/agent-skill"

# --- Default tier proposals (user can override every value) ---
readonly DEFAULT_TIER_COUNT=3
readonly DEFAULT_NAMES=("dev-secrets" "prod-secrets" "signing-secrets")
readonly DEFAULT_POLICIES=(1 2 3)
readonly DEFAULT_DESCS=(
    "Dev tokens, AI-accessible API keys, low-risk credentials"
    "Production credentials, infrastructure access"
    "Code signing, deployment keys, high-risk credentials"
)

# --- UI helpers ---
prompt() {
    local question="$1" default="$2" answer
    read -r -p "$question [$default]: " answer
    echo "${answer:-$default}"
}

prompt_choice() {
    local question="$1" default="$2" answer
    while true; do
        read -r -p "$question [$default]: " answer
        answer="${answer:-$default}"
        if [[ "$answer" =~ ^[1-3]$ ]]; then
            echo "$answer"
            return 0
        fi
        echo "  Please enter 1, 2, or 3." >&2
    done
}

policy_label() {
    case "$1" in
        1) echo "auto-unlock" ;;
        2) echo "session" ;;
        3) echo "prompt" ;;
    esac
}

# --- Keychain creation ---
create_keychain() {
    local name="$1" policy="$2"
    local kc_path="$KEYCHAIN_DIR/${name}.keychain-db"

    if [[ -f "$kc_path" ]]; then
        echo "  Keychain '$name' already exists — skipping creation."
        echo "  To recreate: security delete-keychain '$kc_path'"
        return 0
    fi

    echo "  Creating keychain '$name'..."
    echo "  You will be asked to set a password for this keychain."
    security create-keychain "$kc_path"

    case "$policy" in
        1) security set-keychain-settings "$kc_path" ;;            # no auto-lock
        2) security set-keychain-settings -l -t 3600 "$kc_path" ;; # lock on sleep, 1h idle
        3) security set-keychain-settings -l -t 1 "$kc_path" ;;    # lock immediately
    esac

    # Add to user keychain search list (so `security` finds it without -w flag)
    local current
    current=$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//' | tr '\n' ' ')
    # shellcheck disable=SC2086
    security list-keychains -d user -s $current "$kc_path" >/dev/null

    echo "  Created '$name' ($(policy_label "$policy"))"
}

# --- Agent skill installation ---

# detect_agents prints lines of: "AGENT|TARGET_PATH|TYPE"
#   TYPE = global (auto-installable) | project (needs cwd to be a project) | gui (manual via app)
detect_agents() {
    [[ -d "$HOME/.claude" ]]   && echo "Claude Code|$HOME/.claude/skills/secrets-helper/SKILL.md|global"
    [[ -d "$HOME/.kiro" ]]     && echo "Kiro|$HOME/.kiro/steering/secrets-helper.md|global"
    command -v cursor   >/dev/null 2>&1 && echo "Cursor|.cursor/rules/secrets-helper.mdc|project"
    command -v windsurf >/dev/null 2>&1 && echo "Windsurf|AGENTS.md|project"
    command -v gemini   >/dev/null 2>&1 && echo "Gemini CLI|GEMINI.md|project"
    command -v codex    >/dev/null 2>&1 && echo "OpenAI Codex|AGENTS.md|project"
    command -v aider    >/dev/null 2>&1 && echo "Aider|CONVENTIONS.md|project"
    command -v zed      >/dev/null 2>&1 && echo "Zed|.rules|project"
    [[ -d "$HOME/.codex" ]]    && echo "Codex CLI|$HOME/.codex/AGENTS.md|global"
    if command -v code >/dev/null 2>&1 || [[ -d "$HOME/Library/Application Support/Code/User" ]]; then
        echo "GitHub Copilot|.github/copilot-instructions.md|project"
    fi
}

install_global_skill() {
    local agent="$1" target="$2"
    local source_file
    case "$agent" in
        "Claude Code") source_file="$SKILL_DIR/claude-code/SKILL.md" ;;
        "Kiro"|"Codex CLI") source_file="$SKILL_DIR/secrets-helper.md" ;;
        *) echo "  ✗ no source mapping for $agent"; return 1 ;;
    esac

    if [[ ! -f "$source_file" ]]; then
        echo "  ✗ source file missing: $source_file"
        return 1
    fi

    if [[ -f "$target" ]]; then
        echo "  Skill already exists: $target"
        echo "  Re-installing (will overwrite)..."
    fi

    mkdir -p "$(dirname "$target")"
    cp "$source_file" "$target"
    echo "  ✓ Installed for $agent → $target"
}

print_project_install_instructions() {
    local detections="$1"
    local has_project=0
    while IFS='|' read -r agent target type; do
        [[ "$type" == "project" ]] || continue
        if (( has_project == 0 )); then
            echo ""
            echo "Project-level agents (you copy these into individual project repos):"
            has_project=1
        fi

        local source_file
        case "$agent" in
            Cursor) source_file="$SKILL_DIR/cursor/secrets-helper.mdc" ;;
            *)      source_file="$SKILL_DIR/secrets-helper.md" ;;
        esac
        printf "  %-18s cp %s <project>/%s\n" "$agent" "$source_file" "$target"
    done <<< "$detections"

    if (( has_project == 1 )); then
        echo ""
        echo "  Tip: AGENTS.md is supported by Codex, Windsurf, Cursor (alt), Factory, Amp, Kilo, and Zed."
        echo "  One file at the project root usually covers them all."
    fi
}

# --- Wizard ---
main() {
    cat <<BANNER

==========================================
  secrets-helper setup (v$VERSION)
==========================================

This wizard creates one or more macOS keychains, each with its own
security policy. You decide the names, count, and policy per tier.

You will be prompted to set a password for each keychain.
Use the same password as your login keychain to enable auto-unlock.

BANNER

    local count
    count=$(prompt "How many security tiers do you want?" "$DEFAULT_TIER_COUNT")
    if ! [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
        echo "Invalid count: $count" >&2
        exit 1
    fi

    local names=() policies=() descs=()
    for ((i=0; i<count; i++)); do
        echo ""
        echo "=== Tier $((i+1)) ==="

        local default_name="${DEFAULT_NAMES[$i]:-tier-$((i+1))}"
        local default_policy="${DEFAULT_POLICIES[$i]:-2}"
        local default_desc="${DEFAULT_DESCS[$i]:-}"

        local name policy desc
        name=$(prompt "Name" "$default_name")

        echo "Security policy:"
        echo "  1) auto-unlock  — always accessible (convenient for AI tools, dev tokens)"
        echo "  2) session      — unlocked per shell, locks on sleep or after 1h idle"
        echo "  3) prompt       — asks for password every time"
        policy=$(prompt_choice "Choice" "$default_policy")

        desc=$(prompt "Description" "$default_desc")

        names+=("$name")
        policies+=("$policy")
        descs+=("$desc")
    done

    echo ""
    echo "=== Summary ==="
    for ((i=0; i<count; i++)); do
        printf "  %d. %-20s %-12s %s\n" "$((i+1))" "${names[$i]}" "$(policy_label "${policies[$i]}")" "${descs[$i]}"
    done
    echo ""

    local confirm
    confirm=$(prompt "Create these keychains?" "yes")
    if [[ "$confirm" != "yes" && "$confirm" != "y" ]]; then
        echo "Aborted."
        exit 0
    fi

    echo ""
    for ((i=0; i<count; i++)); do
        create_keychain "${names[$i]}" "${policies[$i]}"
    done

    # Save config
    mkdir -p "$CONFIG_DIR"
    {
        echo "# secrets-helper config"
        echo "# Generated by setup.sh on $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Edit this file to add/rename tiers (re-run setup.sh to change keychain settings)."
        echo ""
        printf 'TIER_NAMES=('
        printf '"%s" ' "${names[@]}"
        printf ')\n'
        printf 'TIER_POLICIES=('
        printf '"%s" ' "${policies[@]}"
        printf ')\n'
        printf 'TIER_DESCS=('
        printf '"%s" ' "${descs[@]}"
        printf ')\n'
    } > "$CONFIG_FILE"

    echo ""
    echo "Config written to $CONFIG_FILE"

    # --- Agent skill install ---
    echo ""
    echo "==========================================="
    echo "  Agent skill installation"
    echo "==========================================="
    echo ""
    echo "AI coding agents work better when they know about secrets-helper."
    echo "We can install a skill that teaches them the tier model, commands,"
    echo "and security rules so they use the keychain instead of .env files."
    echo ""

    local detections
    detections=$(detect_agents || true)

    if [[ -z "$detections" ]]; then
        echo "  No supported agents detected on this machine. Skipping."
    else
        echo "Detected agents:"
        while IFS='|' read -r agent target type; do
            [[ -n "$agent" ]] || continue
            printf "  %-18s [%s]  %s\n" "$agent" "$type" "$target"
        done <<< "$detections"
        echo ""
        echo "Install skill for global / user-level agents?"
        echo "  1) yes — install for all detected global agents"
        echo "  2) Claude Code only"
        echo "  3) skip"
        local skill_choice
        skill_choice=$(prompt_choice "Choice" "1")

        if [[ "$skill_choice" == "1" || "$skill_choice" == "2" ]]; then
            echo ""
            while IFS='|' read -r agent target type; do
                [[ "$type" == "global" ]] || continue
                if [[ "$skill_choice" == "2" && "$agent" != "Claude Code" ]]; then
                    continue
                fi
                install_global_skill "$agent" "$target"
            done <<< "$detections"
        fi

        print_project_install_instructions "$detections"
    fi

    echo ""
    echo "==========================================="
    echo "  Next steps"
    echo "==========================================="
    echo "  1. Add to PATH:        export PATH=\"$SCRIPT_DIR/bin:\$PATH\""
    echo "  2. (Optional) source:  source $SCRIPT_DIR/lib/secrets-helper.sh"
    echo "  3. Add a secret:       secrets add ${names[0]} MY_TOKEN <value>"
    echo "  4. Read a secret:      secrets get ${names[0]} MY_TOKEN"
    echo "  5. Check version:      secrets --version"
    echo ""
}

main "$@"
