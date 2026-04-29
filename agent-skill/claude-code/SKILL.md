---
name: keybuddy
description: "Use when reading, storing, or referencing API tokens, credentials, or secrets on macOS. Activates for token management, .env file discussions, authentication setup, and any time the user asks about API keys or credentials. The tool stores secrets in tiered macOS keychains (auto-unlock / session / prompt policies) and replaces .env-based secret storage."
allowed-tools:
  - Bash
  - Read
  - Grep
---

# Keybuddy — Password Management for AI Agents

This skill teaches you how to use `keybuddy`, a tiered macOS Keychain wrapper. When this tool is installed on the user's machine, you should use it as the **single source of truth** for API tokens, credentials, and signing keys — not `.env` files, not chat, not memory.

## What `keybuddy` is

`keybuddy` is a thin CLI on top of macOS Keychain. It stores secrets across multiple keychains ("tiers"), each with a different security policy. Users configure tiers during setup; you discover them at runtime.

**The user's threat model:** different secrets need different friction. A dev API key should be readable without prompting (ergonomics). A production deploy token should require a session unlock (caution). A signing certificate should prompt every time (paranoia). One keychain can't satisfy all three — hence tiers.

## When to use this skill

Activate when the user (or your task) involves:

- **Reading credentials** to authenticate to an external service (GitHub, Anthropic, OpenAI, cloud providers, internal APIs)
- **Storing a new credential** the user has just received or generated
- **Looking for an existing token** ("the GitHub token", "my Anthropic key")
- **Mentions of `.env` files** for secret storage on macOS — redirect the user to keychain-based storage
- **Auditing how secrets are stored** in a project

Do **not** activate when:
- The user is on Linux/Windows (this tool is macOS-only)
- The "secret" is non-sensitive config (URL, port, feature flag) — `.env` is fine for that
- The tool is not installed (check first — see Detection below)

## Detection — is `keybuddy` available?

Always verify before using. If absent, fall back gracefully (ask user, suggest installing, do not invent commands).

```bash
command -v secrets >/dev/null 2>&1 && echo "installed" || echo "missing"
```

If missing, suggest the user install it from their `keybuddy` repo (`./setup.sh`) before proceeding.

## The tier model

Each tier maps to one macOS keychain with one of three policies:

| Policy | Behavior | Typical contents |
|--------|----------|------------------|
| `auto-unlock` | Always accessible once user is logged in. No prompts. | Dev API keys, AI tool tokens, low-risk credentials. **Safe for agents to read silently.** |
| `session` | Unlocked once per shell session, locks on sleep or after 1h idle. | Production credentials, deploy tokens, infrastructure access. **May prompt user.** |
| `prompt` | Asks for password every access. | Code signing, app passwords, high-risk credentials. **Will prompt user — do not call without explicit user request.** |

Tier names are user-defined. Common defaults: `dev-secrets`, `prod-secrets`, `signing-secrets` — but never assume; always discover.

## Discovery flow

Before reading any secret, run discovery. This is cheap and prevents guessing.

```bash
# 1. List configured tiers and their policies
secrets tiers

# 2. List secrets in a specific tier (returns service names, not values)
secrets list dev-secrets
```

When the user asks for "the GitHub token", search across tiers:

```bash
for tier in $(secrets tiers | tail -n +2 | awk '{print $1}'); do
    secrets list "$tier" 2>/dev/null | grep -i github && echo "  found in: $tier"
done
```

## Reading a secret

```bash
secrets get <tier> <name>
```

**Critical security rules** when consuming the value:

1. **Never `echo` or print the value to stdout.** The output of `secrets get` is the secret. If you echo it, it appears in the conversation transcript.
2. **Use shell substitution** to pass it directly to the tool that needs it:
   ```bash
   curl -H "Authorization: token $(secrets get dev-secrets GITHUB_TOKEN)" https://api.github.com/user
   ```
3. **Do not assign to environment variables** unless strictly necessary. If you must, scope tightly:
   ```bash
   GITHUB_TOKEN=$(secrets get dev-secrets GITHUB_TOKEN) gh repo list  # scoped to one command
   ```
   Avoid `export GITHUB_TOKEN=...` which leaks to all subsequent processes.
4. **Do not write the value to a file** — not `.env`, not a config file, not a temp file. The keychain IS the storage.
5. **Do not pass the value as a function argument** that gets logged. Many shells log argv to history.
6. **Never include the value in commit messages, git diffs, error messages, or chat output**, even when debugging.

## Adding a new secret

When the user gives you a new token (paste in chat, file, or generate workflow):

1. **Confirm the tier with the user** before storing. Defaults vary; security policy matters:
   - Dev tools / API keys for AI: `auto-unlock` tier
   - Production / deploy: `session` tier
   - Signing / Apple / high-risk: `prompt` tier
2. **Use `secrets add`** — this is `add or update`, idempotent:
   ```bash
   secrets add <tier> <NAME> <VALUE>
   ```
3. **Naming convention**: UPPER_SNAKE_CASE, descriptive (`GITHUB_TOKEN_WORK`, `ANTHROPIC_API_KEY`, `STRIPE_PROD_SECRET`).
4. **Suggest the user clear the source**: if they pasted the token in chat, suggest scrolling that out of view; if it was in a file, suggest deleting the file after `secrets add` succeeds.
5. **Verify the write** with `secrets get` — but pipe through a length check, not a print:
   ```bash
   v=$(secrets get <tier> <NAME>); echo "stored: ${#v} chars"
   ```

## Listing and managing

```bash
secrets tiers                     # show all configured tiers + policies
secrets list <tier>               # show service names in a tier (no values)
secrets del <tier> <name>         # delete a secret (irreversible)
secrets lock <tier>               # manually lock a keychain
secrets unlock <tier>             # manually unlock (prompts for password)
secrets help                      # built-in usage
secrets --version                 # check installed version
```

## Common workflows

### GitHub authentication
```bash
# Multi-account: use suffix in name
secrets get dev-secrets GITHUB_TOKEN_WORK
secrets get dev-secrets GITHUB_TOKEN_PERSONAL

# In a curl call (preferred)
curl -H "Authorization: token $(secrets get dev-secrets GITHUB_TOKEN)" https://api.github.com/user

# With gh CLI (one-shot env var)
GH_TOKEN=$(secrets get dev-secrets GITHUB_TOKEN) gh repo list
```

### Anthropic / OpenAI / LLM APIs
```bash
ANTHROPIC_API_KEY=$(secrets get dev-secrets ANTHROPIC_API_KEY) claude "..."
OPENAI_API_KEY=$(secrets get dev-secrets OPENAI_API_KEY) python my_script.py
```

### Cloud / production credentials (session tier)
```bash
# May prompt for keychain password if locked
HCLOUD_TOKEN=$(secrets get prod-secrets HCLOUD_TOKEN) hcloud server list
```

### Signing (prompt tier — only on explicit user request)
```bash
# Will ALWAYS prompt — only run when user has asked for a signing operation
APPLE_APP_PASSWORD=$(secrets get signing-secrets APPLE_APP_PASSWORD) xcrun notarytool submit ...
```

## Troubleshooting

| Symptom | Cause | Resolution |
|---------|-------|------------|
| `command not found: secrets` | Tool not installed or not in PATH | Ask user to run `keybuddy/setup.sh` and add `bin/` to PATH |
| `Error: unknown tier 'X'` | Tier not configured | Run `secrets tiers` to see configured tiers; may need different name |
| Keychain prompts for password | Tier is `session` or `prompt` policy and is locked | Either run `secrets unlock <tier>` first (with user consent) or accept the prompt |
| `Error: config not found` | Setup hasn't been run | Direct user to run `setup.sh` |
| Secret retrieved but request still fails | Wrong tier or stale token | Re-check with `secrets list <tier>`; user may need to rotate the token |

## Anti-patterns to avoid

These are mistakes agents commonly make. Do not do them.

1. **Reading `.env` files when keybuddy is installed.** Suggest migration: "I see this project has a `.env` with API keys. Want me to migrate them into your keychain via `secrets add`?"
2. **Asking the user to paste a secret in chat** when you could read it from the keychain.
3. **Using `export` for credentials** at top of a script. Use scoped per-command env vars instead.
4. **Logging the value during debugging.** Log the *length* or the *first 4 chars + ...* if you must verify presence:
   ```bash
   v=$(secrets get dev-secrets X); echo "${v:0:4}... (${#v} chars)"
   ```
5. **Saving secrets to a "memory" or notes file.** They live in the keychain only.
6. **Hardcoding tier names** without discovery. Names are user-configurable.
7. **Calling `secrets get` on a `prompt` tier without user awareness** — will pop up a system password prompt unexpectedly.

## What `keybuddy` deliberately does NOT do

- Sync across machines (each Mac has its own keychain — by design)
- Work on Linux or Windows
- Replace Vault / 1Password / cloud secret managers for team-shared secrets
- Encrypt anything itself — relies on macOS Keychain Services
- Rotate tokens automatically — that's the user's responsibility

If the user needs any of those, suggest the appropriate alternative tool (HashiCorp Vault for shared secrets, 1Password for team password management, AWS Secrets Manager for cloud apps).

## Quick reference card

```
DISCOVERY     secrets tiers
              secrets list <tier>

READ          $(secrets get <tier> <NAME>)            ← shell substitution, never echo

WRITE         secrets add <tier> <NAME> <VALUE>       ← confirm tier with user first

DELETE        secrets del <tier> <NAME>               ← irreversible, confirm

MAINTAIN      secrets lock <tier>
              secrets unlock <tier>
              secrets --version
```

When in doubt: discover the tier structure first (`secrets tiers`), then list contents (`secrets list <tier>`), then read with `$(secrets get ...)` inside the consuming command. Never print, never persist, never commit.
