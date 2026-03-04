# Changelog

All notable changes to the **powerglide** project will be documented in this file.

## [0.1.3] - 2026-03-04

### Added
- **Technical Technical Diagrams**: Extracted high-quality SVGs (Ralph Loop, Module Structure, Swarm Architecture) from the Zine website and embedded them directly into `README.md` and `AGENTS.md`.
- **Favicon Support**: Generated a high-quality SVG favicon from the logo and integrated it across all documentation layouts.
- **Integration Tests**: Added `test/integration/cli_test.zig` to automate verification of core CLI subcommands (`version`, `help`, `doctor`, `config`, `tools`).
- **E2E Workflow Script**: Created `test/e2e/workflow.sh` for full-lifecycle verification of the harness.
- **Documentation Archive**: Created `docs/archive/` and `docs/context/` to manage historical logs and project-planning artifacts.

### Changed
- **Velocity Model Overhaul**: Refactored the execution engine to use a **floating-point velocity multiplier** (`delay = 1000 / velocity`) instead of fixed milliseconds. This applies to the Ralph Loop, global Config, and individual Workers.
- **Documentation Refresh**: Rewrote `README.md` and `AGENTS.md` to reflect the supercar-grade technical vision, including the recovery of Barvis context and Rae Sremmurd references.
- **Zig 0.15.2 Patterns**: Standardized `ArrayList` and `HashMap` usage across the codebase to use **unmanaged** patterns, ensuring explicit memory control.
- **Homepage Polish**: Removed redundant titles from the website homepage to prioritize the hero logo and descriptive technical prose.

### Fixed
- **Use-After-Free**: Resolved a critical memory bug in `src/tools/tool.zig` where the `bash` tool was accessing freed output buffers.
- **Memory Leaks**: Fixed leaks in `src/tools/registry.zig` tests where tool output content was not properly deinited.
- **Path Resolution**: Fixed issues with session file persistence in subdirectories.

## [0.1.1] - 2026-03-04

### Added
- Zine-based SSG documentation website under `website/`.
- Deployment automation for GitHub Pages.

## [0.1.0] - 2026-03-02

### Added
- Initial scaffolding of the powerglide multi-agent harness in Zig 0.15.2.
- Ralph Loop 11-state machine implementation.
- Multi-model routing for Anthropic and OpenAI.
- PTY-based tool execution with reliable exit code capture.
- Basic `vxfw` TUI dashboard.
