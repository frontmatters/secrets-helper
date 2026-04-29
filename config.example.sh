#!/usr/bin/env bash
# Example: project-specific shortcut functions
#
# Copy this file somewhere outside the repo (e.g. ~/.config/keybuddy/shortcuts.sh)
# and source it from your shell rc to define your own convenience functions.
#
# These wrap the generic `secrets get` calls for the services YOU use.
# This file is just an example — do NOT commit your real shortcuts to a public repo.

# Example: GitHub multi-account
github_token() {
    local account="${1:-DEFAULT}"
    secrets get dev-secrets "GITHUB_TOKEN_${account}"
}

# Example: simple API keys in dev tier
anthropic_key() { secrets get dev-secrets ANTHROPIC_API_KEY; }
openai_key()    { secrets get dev-secrets OPENAI_API_KEY; }

# Example: production credentials (will prompt for password if locked)
deploy_token() { secrets get prod-secrets DEPLOY_TOKEN; }

# Example: signing credentials (always prompts)
apple_app_password() {
    local app="${1:-default}"
    secrets get signing-secrets "APPLE_APP_PASSWORD_${app}"
}
