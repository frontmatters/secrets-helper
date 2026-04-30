# secrets-helper

[![version](https://img.shields.io/badge/version-0.2.0-blue.svg)](CHANGELOG.md)
[![platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](#)
[![license](https://img.shields.io/badge/license-MIT-green.svg)](#license)

> **The macOS keychain that replaces your `.env` files.**

Stop committing tokens by accident. Stop pasting them in chat. Stop having a different `.env` on every machine.

secrets-helper stores your API keys and credentials in macOS Keychain, organised in **three security tiers** so that dev tokens, production credentials, and signing keys each get the friction they deserve. It also ships an **agent skill bundle** that teaches Claude Code, Cursor, GitHub Copilot, Windsurf, Codex and seven other AI coding agents how to read straight from your keychain — instead of asking you to paste tokens into chat.

You decide:
- How many tiers (default: 3)
- What to call each tier
- Which security policy each tier uses (`auto-unlock`, `session`, or `prompt`)

The setup wizard proposes sensible defaults — you confirm or override every value.

## Why tiered keychains?

Not all secrets are equal. A dev API key for a side project deserves a different security posture than your code-signing certificate.

| Policy | Behavior | Good for |
|--------|----------|----------|
| `auto-unlock` | Always accessible once logged in | Dev tokens, AI tool API keys, low-risk credentials |
| `session` | Locks on sleep or after 1h idle | Production credentials, infrastructure access |
| `prompt` | Asks for password every access | Code signing, deployment keys, high-risk credentials |

Each tier is a separate macOS keychain (`~/Library/Keychains/<tier>.keychain-db`), with its own password and lock policy.

## Install

```bash
git clone https://github.com/<your-account>/secrets-helper.git ~/Developer/secrets-helper
cd ~/Developer/secrets-helper
./setup.sh
```

The wizard walks you through tier configuration. Then add the CLI to your `PATH`:

```bash
echo 'export PATH="$HOME/Developer/secrets-helper/bin:$PATH"' >> ~/.zshrc
```

(Optional) Source the bash function wrapper for shorter commands:

```bash
echo 'source ~/Developer/secrets-helper/lib/secrets-helper.sh' >> ~/.zshrc
```

## Usage

```bash
# Add a secret to a tier
secrets add dev-secrets GITHUB_TOKEN ghp_xxxxxxxxxxxx

# Read it back
secrets get dev-secrets GITHUB_TOKEN

# List secret names in a tier
secrets list dev-secrets

# List configured tiers
secrets tiers

# Lock / unlock a tier manually
secrets lock prod-secrets
secrets unlock prod-secrets

# Delete a secret
secrets del dev-secrets OLD_TOKEN
```

If you sourced the helper, drop the `secrets` prefix:

```bash
add dev-secrets GITHUB_TOKEN ghp_xxxxxxxxxxxx
get dev-secrets GITHUB_TOKEN
list dev-secrets
```

## Custom shortcuts

For frequently-used secrets, define your own shortcut functions in a personal file (do **not** commit these). See [`config.example.sh`](config.example.sh) for examples.

```bash
# ~/.config/secrets-helper/shortcuts.sh
github_token() { secrets get dev-secrets GITHUB_TOKEN; }
anthropic_key() { secrets get dev-secrets ANTHROPIC_API_KEY; }
```

Then in your shell rc:

```bash
source ~/.config/secrets-helper/shortcuts.sh
```

## AI agent skill

The repo ships with an instruction document that teaches AI coding agents how to use `secrets-helper`: the tier model, all commands, security rules, common workflows, and anti-patterns. Once installed, agents like Claude Code, Cursor, Copilot, etc. will use the keychain CLI for credential operations instead of asking you to paste tokens in chat or writing them to `.env` files.

The setup wizard auto-detects installed agents and offers installation. Supported targets:

| Agent | Install location | Mode |
|-------|------------------|------|
| Claude Code | `~/.claude/skills/secrets-helper/SKILL.md` | Global (auto-installable) |
| Kiro | `~/.kiro/steering/secrets-helper.md` | Global (auto-installable) |
| Cursor | `<project>/.cursor/rules/secrets-helper.mdc` | Project |
| GitHub Copilot | `<project>/.github/copilot-instructions.md` | Project |
| Windsurf | `<project>/AGENTS.md` or `.windsurfrules` | Project |
| OpenAI Codex / Factory / Amp / Kilo Code | `<project>/AGENTS.md` | Project |
| Gemini CLI | `<project>/GEMINI.md` | Project |
| Roo Code | `<project>/.roo/rules/secrets-helper.md` | Project |
| Cline | `<project>/.clinerules/secrets-helper.md` | Project |
| Zed | `<project>/.rules` or `AGENTS.md` | Project |
| Aider | `<project>/CONVENTIONS.md` (referenced via `--read`) | Project |

`AGENTS.md` is supported by an [open standard](https://agents.md/) that covers Codex, Factory, Amp, Kilo Code, Cursor (alt), Zed, and Windsurf — one file at a project root usually covers them all. The setup wizard prints copy-paste commands for project-level installs.

To install the skill manually outside of the wizard:

```bash
# Claude Code (global, all projects)
mkdir -p ~/.claude/skills/secrets-helper
cp agent-skill/claude-code/SKILL.md ~/.claude/skills/secrets-helper/

# Cursor (per project)
mkdir -p .cursor/rules
cp agent-skill/cursor/secrets-helper.mdc .cursor/rules/

# Universal AGENTS.md (per project — covers most agents)
cp agent-skill/secrets-helper.md AGENTS.md
```

Cursor User Rules and Windsurf Custom Instructions are GUI-only — copy-paste the contents of [`agent-skill/secrets-helper.md`](agent-skill/secrets-helper.md) into the app's settings panel.

## Versioning and updates

```bash
secrets --version    # → secrets-helper 0.1.0
cat VERSION          # → 0.1.0
```

This project follows [Semantic Versioning](https://semver.org/). See [CHANGELOG.md](CHANGELOG.md) for release notes.

To update:

```bash
cd ~/Developer/secrets-helper
git pull
secrets --version    # confirm new version
# Re-run setup.sh ONLY if CHANGELOG mentions a setup-affecting change.
# Existing keychains are not touched.
```

## Setup another machine

1. Clone the repo
2. Run `./setup.sh` — choose the same tier names you use elsewhere
3. Re-add your secrets with `secrets add` (keychains do not sync across machines by design)

## Uninstall

```bash
# Delete keychains (replace with your tier names)
security delete-keychain ~/Library/Keychains/dev-secrets.keychain-db
security delete-keychain ~/Library/Keychains/prod-secrets.keychain-db
security delete-keychain ~/Library/Keychains/signing-secrets.keychain-db

# Remove config and repo
rm -rf ~/.config/secrets-helper
rm -rf ~/Developer/secrets-helper
```

## How it works

Under the hood this is a thin wrapper around macOS `security(1)`. Each tier maps to one keychain database; secrets are stored as generic passwords keyed by service name. Security policies translate to `security set-keychain-settings` flags:

| Policy | Flags |
|--------|-------|
| `auto-unlock` | (none — no auto-lock) |
| `session` | `-l -t 3600` |
| `prompt` | `-l -t 1` |

The keychain databases never leave your machine. The repo only contains code — no secrets, no keychain files (`.gitignore` enforces this).

## License

MIT
