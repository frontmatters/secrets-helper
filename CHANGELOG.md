# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-29

### Added
- Initial release: tiered macOS Keychain wrapper.
- Three security policies — `auto-unlock`, `session`, `prompt` — selected per tier during setup.
- Interactive setup wizard (`setup.sh`) with configurable tier names, count, and policies. Defaults proposed but every value can be overridden.
- Generic `secrets` CLI with subcommands: `get`, `add`, `del`, `list`, `tiers`, `lock`, `unlock`, `help`, `--version`.
- Sourceable shell function wrapper (`lib/keybuddy.sh`) for shorter syntax (`get`, `add`, etc. as bash functions).
- Agent skill bundle (`agent-skill/`) for AI coding agents:
  - Canonical instruction document (plain Markdown).
  - Claude Code wrapper (`SKILL.md` with YAML frontmatter).
  - Cursor wrapper (`.mdc` with frontmatter).
  - Setup wizard auto-detects installed agents (Claude Code, Kiro, Cursor, Windsurf, Copilot, Gemini CLI, Codex, Aider, Roo Code, Cline, Zed) and offers installation paths.
- Idempotent setup: re-running `setup.sh` skips existing keychains rather than overwriting.
- `.gitignore` blocking `*.keychain-db`, `.env*`, and personal config files.
- Comprehensive README with install, usage, custom shortcuts, and uninstall sections.

### Security
- Configuration file (`~/.config/keybuddy/config.sh`) contains no secrets — only tier names, policies, and descriptions.
- Keychain databases (`*.keychain-db`) live exclusively in `~/Library/Keychains/` and never enter the repo.
- CLI relies on macOS `security(1)` — no custom crypto.

<!-- Update these URLs to your fork/upstream once published. -->
[Unreleased]: https://example.com/keybuddy/compare/v0.1.0...HEAD
[0.1.0]: https://example.com/keybuddy/releases/tag/v0.1.0
