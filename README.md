# secrets-helper

Tiered macOS Keychain wrapper for storing API tokens, credentials, and signing keys with **different security policies per tier**.

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
