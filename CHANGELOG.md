# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-11-08

### Added
- `secrets-helper-setup --help` and `--version` now show usage or the version
  without starting the interactive wizard or changing keychains.

### Security

- `secrets add TIER NAME` reads the value from stdin (hidden when typed); a
  value given as an argument is refused, because it showed in process lists
  and shell history. `move` and `pull` store through the same helper, which
  hands the value to `security -i` on stdin and reads it back.
- `create-tier` passes the new keychain's password to `security -i` on stdin
  instead of `create-keychain -p` on the command line.
- `pull` accepts key names of `A-Z a-z 0-9 . _ @ : -` only, from you and from
  the other machine's list, so a name can no longer run code on the other Mac;
  a host that starts with `-` is refused and ssh gets `--`.
- `get` opens a locked auto-unlock tier (they all start locked after a reboot)
  and says `secrets unlock TIER` for a tier that will not open, instead of
  failing without a word; the README and setup no longer promise "always
  accessible".
- The agent skill (all three copies) no longer shows agents how to print a
  value, a prefix of one, or put one in an argument list: `secrets get` only
  inside the consuming command, curl gets the header through `-K <(...)`, new
  values are typed by the user. `tests/skill-lint.test.sh` keeps it that way.
- The config is only read when it is yours, not writable by others, and holds
  nothing but literal lists of the known keys; a line with `$`, backticks or a
  command is refused instead of run. setup.sh strips such characters from
  names and descriptions and writes the file with mode 600.
- Backup and restore (new in this release): the backup password reaches the
  helper on stdin, never in the environment of child processes; restore adds
  the tiers to the keychain search list instead of replacing it; a backup
  whose file names point outside the restore directory is refused; backup and
  restored files are created with mode 600 from the start.

### Fixed
- `pull` now unlocks the target tier before writing. A tier created moments
  earlier is not necessarily unlocked, and the first write failed — which is how
  a two-key pull could quietly deliver one key.
- A failed write is reported as `failed`, not `skipped`, and the command exits
  non-zero. Reporting both as "skipped" made a half-finished pull read like a
  success.

## [0.3.0] - 2026-09-08

### Added
- `secrets pull HOST TIER NAME|GLOB [--force]` — copy secrets from another
  machine's keychain over ssh. The value goes keychain → ssh → keychain: never a
  file, never stdout, never your shell history. Existing local keys are skipped
  unless `--force`.
- `secrets remote-list HOST TIER` — the names on another machine, no values.
- `secrets create-tier TIER` — materialise the keychain for a tier that is in
  your config but not yet on this machine. `pull` offers this when it needs it.
- `secrets move FROM TO NAME [--force]` — promote a secret to another tier.
  Copy, verify the copy, then delete: every failure path leaves the original in
  place, because the credentials worth moving are usually the ones you cannot
  simply re-issue.

### Notes on what `pull` can reach
- It unlocks the remote keychain with an empty password, so it works on
  `auto-unlock` tiers and fails cleanly on `session` / `prompt` ones. The
  boundary is the keychain password, not a rule in this tool.
- The `quarantine` tier is refused outright: those credentials are awaiting
  revocation, and copying them to a second machine spreads the problem.

## [0.2.1] - 2026-05-17

### Added
- Non-interactive `install.sh` for idempotent CLI installation.
- `setup.sh` now runs `install.sh` first for backwards-compatible setup.

## [0.2.0] - 2026-04-29

### Changed (BREAKING)
- Project renamed back to `secrets-helper` (was briefly `keybuddy` in v0.1.x). The descriptive name is more discoverable for users searching for a `.env` alternative or macOS keychain manager. The `keybuddy` aliases (CLI symlink, env var prefix, config dir) are removed.
- Environment variable: `KEYBUDDY_CONFIG` → `SECRETS_HELPER_CONFIG`.
- Environment variable: `KEYBUDDY_QUIET` → `SECRETS_HELPER_QUIET`.
- Config directory: `~/.config/keybuddy/` → `~/.config/secrets-helper/`.
- Sourceable wrapper file: `lib/keybuddy.sh` → `lib/secrets-helper.sh`.
- Agent skill files: `agent-skill/keybuddy.md` → `agent-skill/secrets-helper.md`, `agent-skill/cursor/keybuddy.mdc` → `agent-skill/cursor/secrets-helper.mdc`.
- Skill `name:` frontmatter: `keybuddy` → `secrets-helper`.

### Removed
- `bin/keybuddy` symlink. The CLI binary is `secrets` only.
- `keybuddy-setup` brew install wrapper. Replaced by `secrets-helper-setup`.

### Migration from v0.1.x
If you ran `setup.sh` under v0.1.x, your config lives at `~/.config/keybuddy/`. Rename it manually:

```bash
mv ~/.config/keybuddy ~/.config/secrets-helper
```

Keychains created during setup are unaffected — they live in `~/Library/Keychains/<tier>.keychain-db` and are independent of the project name.

## [0.1.2] - 2026-04-29

### Fixed
- `--version` still failed under Homebrew because the script computed `SCRIPT_DIR` from `${BASH_SOURCE[0]}` without resolving symlinks. Brew's install path is a symlink chain (`/opt/homebrew/bin/secrets` → `Cellar/secrets-helper/0.1.x/bin/secrets`), so `dirname` returned `/opt/homebrew/bin` and `../VERSION` looked for `/opt/homebrew/VERSION`, which doesn't exist. The script now walks the symlink chain to find the real script directory before resolving the VERSION file path.

## [0.1.1] - 2026-04-29

### Fixed
- `secrets --version` and `secrets-helper --version` printed "version unknown — VERSION file missing" when installed via Homebrew. The CLI computed `VERSION_FILE=$SCRIPT_DIR/../VERSION`, which is correct when run from a source checkout but wrong under brew's layout where VERSION lives in `libexec/`. The CLI now searches both `../VERSION` and `../libexec/VERSION` and uses whichever exists.

## [0.1.0] - 2026-04-29

### Added
- Initial release: tiered macOS Keychain wrapper.
- Three security policies — `auto-unlock`, `session`, `prompt` — selected per tier during setup.
- Interactive setup wizard (`setup.sh`) with configurable tier names, count, and policies. Defaults proposed but every value can be overridden.
- Generic `secrets` CLI with subcommands: `get`, `add`, `del`, `list`, `tiers`, `lock`, `unlock`, `help`, `--version`.
- Sourceable shell function wrapper (`lib/secrets-helper.sh`) for shorter syntax (`get`, `add`, etc. as bash functions).
- Agent skill bundle (`agent-skill/`) for AI coding agents:
  - Canonical instruction document (plain Markdown).
  - Claude Code wrapper (`SKILL.md` with YAML frontmatter).
  - Cursor wrapper (`.mdc` with frontmatter).
  - Setup wizard auto-detects installed agents (Claude Code, Kiro, Cursor, Windsurf, Copilot, Gemini CLI, Codex, Aider, Roo Code, Cline, Zed) and offers installation paths.
- Idempotent setup: re-running `setup.sh` skips existing keychains rather than overwriting.
- `.gitignore` blocking `*.keychain-db`, `.env*`, and personal config files.
- Comprehensive README with install, usage, custom shortcuts, and uninstall sections.

### Security
- Configuration file (`~/.config/secrets-helper/config.sh`) contains no secrets — only tier names, policies, and descriptions.
- Keychain databases (`*.keychain-db`) live exclusively in `~/Library/Keychains/` and never enter the repo.
- CLI relies on macOS `security(1)` — no custom crypto.

[Unreleased]: https://github.com/frontmatters/secrets-helper/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/frontmatters/secrets-helper/releases/tag/v0.3.0
[0.3.0]: https://github.com/frontmatters/secrets-helper/releases/tag/v0.3.0
[0.2.1]: https://github.com/frontmatters/secrets-helper/releases/tag/v0.2.1
[0.2.0]: https://github.com/frontmatters/secrets-helper/releases/tag/v0.2.0
[0.1.2]: https://github.com/frontmatters/secrets-helper/releases/tag/v0.1.2
[0.1.1]: https://github.com/frontmatters/secrets-helper/releases/tag/v0.1.1
[0.1.0]: https://github.com/frontmatters/secrets-helper/releases/tag/v0.1.0
