# secrets-helper

[![version](https://img.shields.io/badge/version-0.3.0-blue.svg)](CHANGELOG.md)
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

## Sharing keys between your machines

A second machine needs the same keys. `pull` copies them straight from one
keychain into the other over ssh — the value never touches a file, your terminal,
or your shell history.

```bash
secrets remote-list  laptop-2 dev-secrets      # what is over there (names only)
secrets pull         laptop-2 dev-secrets GITHUB_TOKEN_WORK
secrets pull         laptop-2 dev-secrets 'AWS_*'          # globs work
secrets pull         laptop-2 dev-secrets GITHUB_TOKEN_WORK --force   # overwrite
```

Keys that already exist locally are skipped unless you pass `--force`, so a pull
never silently replaces a value that might be newer here. A key that could not be
stored is reported as failed rather than skipped, and the command exits non-zero
— a partial pull should not pass for a complete one.

If the tier is configured but has no keychain on this machine yet — a fresh
laptop — `pull` offers to create it before fetching anything.

### What this can and cannot reach

`pull` unlocks the remote keychain with an empty password. That works for
`auto-unlock` tiers and **only** for those:

| Tier policy | `pull` |
|---|---|
| `auto-unlock` | works — the keychain has no password |
| `session`, `prompt` | fails with a clear message; copy those by hand |

This is not a rule the tool enforces and could relax later. It is the keychain
password doing its job. `pull` cannot reach a tier you protected, because macOS
will not unlock it without a person present.

Two consequences worth being explicit about:

- **An auto-unlock tier is readable by anything that can reach the account.**
  Anyone with ssh access could always run two `security` commands to the same
  effect; `pull` gives that a name, it does not grant new access. But it is the
  reason an auto-unlock tier should hold revocable API keys — not your server's
  sudo password.
- **A tier holding leaked-and-not-yet-revoked credentials is refused outright.**
  Copying those to a second machine spreads the problem instead of ending it.
  `pull` refuses any tier listed in `NEVER_PULL_TIERS` in your config, which
  defaults to `quarantine`:

  ```bash
  NEVER_PULL_TIERS=("quarantine" "burned")   # in your config.sh
  ```

## Backing up and restoring your tiers

```bash
secrets backup                      # every tier -> ~/secrets-YYYYMMDD.secbak
secrets backup --out b.secbak dev-secrets
secrets restore b.secbak            # --force moves existing keychains aside first
```

A `.secbak` holds the keychain files themselves, encrypted with a backup
password you choose (AES-256-GCM, scrypt). The keychains inside stay locked
with their own passwords, so a backup is protected twice. `--openssl-compat`
writes a file `openssl enc -d` can open without this tool, for an emergency.

- Needs `python3` with the `cryptography` package
  (`python3 -m pip install --user cryptography`).
- The backup password is asked for, or taken from `SECRETS_BACKUP_PASSWORD` if
  you set it; it is never passed on to other programs.
- Restore adds the tiers to the keychain search list and leaves every other
  keychain in it.

## Moving a secret to another tier

Tiers only help if things end up in the right one. A credential you first stored
as a quick dev token, and later realise is really infrastructure access, can be
promoted without ever leaving the keychain:

```bash
secrets move dev-secrets prod-secrets DATABASE_PASSWORD
secrets move dev-secrets quarantine   LEAKED_TOKEN        # awaiting revocation
```

The order is copy → verify → delete, and every failure leaves the original where
it was. A move should never be able to lose a credential you cannot re-issue, so
if the target tier will not unlock, the write fails, or the copy does not read
back identical, the source is still there and the command says so.

An existing key in the target stops the move unless you pass `--force`.

If the target tier is protected (`session` or `prompt`), you will be asked for its
password — that prompt is the reason the credential is going there.

## Why tiered keychains?

Not all secrets are equal. A dev API key for a side project deserves a different security posture than your code-signing certificate.

| Policy | Behavior | Good for |
|--------|----------|----------|
| `auto-unlock` | No password; `secrets get` opens it when needed (after a reboot every keychain but login starts locked) and it never locks again | Dev tokens, AI tool API keys, low-risk credentials |
| `session` | Locks on sleep or after 1h idle | Production credentials, infrastructure access |
| `prompt` | Asks for password every access | Code signing, deployment keys, high-risk credentials |

Each tier is a separate macOS keychain (`~/Library/Keychains/<tier>.keychain-db`), with its own password and lock policy.

## Install

```bash
git clone https://github.com/<your-account>/secrets-helper.git ~/secrets-helper
cd ~/secrets-helper
./install.sh
```

`install.sh` is non-interactive and idempotent. It links the `secrets` CLI into `~/.local/bin` and leaves existing keychains/config untouched.

For first-time configuration, run the interactive wizard:

```bash
./setup.sh
```

The wizard walks you through tier configuration and optional agent skill installation.

If `~/.local/bin` is not on your `PATH`, add it:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

(Optional) Source the bash function wrapper for shorter commands:

```bash
echo 'source ~/secrets-helper/lib/secrets-helper.sh' >> ~/.zshrc
```

## Usage

```bash
# Add a secret to a tier: it asks for the value and does not show it
secrets add dev-secrets GITHUB_TOKEN
# or pipe it in; the value is never an argument, so it stays out of process
# lists and shell history
pbpaste | secrets add dev-secrets GITHUB_TOKEN

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
add dev-secrets GITHUB_TOKEN        # asks for the value
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
cd ~/secrets-helper
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
rm -rf ~/secrets-helper
```

## How it works

Under the hood this is a thin wrapper around macOS `security(1)`. Each tier maps to one keychain database; secrets are stored as generic passwords keyed by service name. Security policies translate to `security set-keychain-settings` flags:

| Policy | Flags |
|--------|-------|
| `auto-unlock` | (none — no auto-lock) |
| `session` | `-l -t 3600` |
| `prompt` | `-l -t 1` |

The keychain databases never leave your machine. The repo only contains code — no secrets, no keychain files (`.gitignore` enforces this).

## Security model and its limits

What secrets-helper guarantees, and what it deliberately leaves to macOS:

- **A value never becomes a command-line argument.** `add` reads it from stdin,
  every write goes to `security -i` on stdin, keychain passwords too. Process
  lists and shell history do not see them.
- **The lock is the boundary.** Once a tier is unlocked, any process running
  as you can read it through `/usr/bin/security` without a prompt. That is why
  high-risk credentials belong in a `session` or `prompt` tier, and why an
  `auto-unlock` tier should only hold keys you can revoke.
- **`NEVER_PULL_TIERS` is enforced by the machine that pulls.** The other
  machine cannot refuse a request. A tier you never want copied should have a
  password: `pull` can only open tiers with an empty one.
- **Environment variables are trusted.** `SECRETS_HELPER_CONFIG`,
  `SECRETS_KEYCHAIN_DIR` and `SECRETS_SSH` exist for tests and relocation. A
  process that can set them for you can also run `security` itself, so they add
  no new way in.
- **The config is data.** It is read only when it is yours, not writable by
  others, and holds literal lists (no `$`, no backticks, no commands).

## License

MIT
