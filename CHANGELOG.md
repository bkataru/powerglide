# Changelog

All notable changes to the **powerglide** project will be documented in this file.

## [0.2.2] - 2026-03-04

### Added
- **Session summary output** — `powerglide run` now emits a structured completion block showing steps taken, elapsed time, agent/model name, and `<POWERGLIDE_DONE>` or `<POWERGLIDE_ERROR>` terminal signal
- **igllama port scanning** — `powerglide doctor` scans `:8090–8099` instead of hardcoded `:8090`; reports all running igllama instances
- **`json_mode` on `OpenAIClient`** — sets `response_format: {"type":"json_object"}` for constrained JSON generation on igllama and other local endpoints
- **Showcase page** — `website/content/showcase.smd` with 4 case studies: codebase exploration (0.8B), targeted query (4B), tool calling triage + json_mode, session summary output; performance table; dogfooding verdict
- **Showcase nav link** — added to both `page.shtml` and `home.shtml` nav bars with amber highlight
- **Tests badge** in README (195/195)

### Fixed
- **`Loop step count increments` test** — now uses `/tmp/test_loop_step_count.json` instead of default `.powerglide/session.json`; previously picked up real session state from dogfooding runs and failed
- **README** — updated to v0.2.2 with local LLM section, session summary example, igllama integration, Showcase link, and tests badge

## [0.2.1] - 2026-03-04

### Added
- **SSE parser tests** — 8 tests covering `SseParser`: text_delta, DONE event, multi-event feeds, CRLF handling, non-data line filtering
- **HTTP response tests** — 5 tests for `Response.isSuccess()` and `deinit`
- **Persistence tests** — 5 tests for `PersistenceManager`: init, path generation, save/load roundtrip
- **Root module coverage** — added `stream`, `http`, `anthropic_mod`, `openai_mod`, `mcp_tool_bridge`, `monitor`, `worker`, `terminal_session`, `terminal_pool`, `terminal_exit_code` to `root.zig` so `refAllDecls` catches them

### Fixed
- **Pre-existing bugs uncovered by expanded coverage**:
  - `stream.zig`: `deinit()` and `appendSlice()` missing allocator args (Zig 0.15.2 unmanaged ArrayList)
  - `terminal/pool.zig`: `sessions.size` → `sessions.count()`, stray orphaned test code, `const pool` → `var pool` for mutable methods
  - `terminal/session.zig`: `["/bin/sh", "-c"]` array literal syntax, stray orphaned test code, `const session` → `var session`
  - `models/stream.zig`: `SseParser.init` unused allocator parameter

## [0.2.0] - 2026-03-04

### Added
- **MCP Server** (`src/mcp/server.zig`) — JSON-RPC 2.0 over stdin/stdout; exposes all registered powerglide tools to any MCP-compatible client via `powerglide mcp`.
- **MCP Client** (`src/mcp/client.zig`) — connects to external MCP servers as subprocesses, transparently registering their tools into the powerglide registry.
- **Tool Bridge** (`src/mcp/tool_bridge.zig`) — converts `McpTool` descriptors to powerglide `Tool` structs with prefixed names (`mcp_{server}_{tool}`).
- **`mcp_servers` config array** — configure external MCP server connections in `~/.config/powerglide/config.json`.
- **`powerglide mcp` CLI command** — starts powerglide in MCP server mode.

### Fixed
- **stdin API for Zig 0.15.2** — replaced `std.fs.File.stdin().reader()` (requires buffer arg) with `posix.read()` byte-by-byte pattern.
- **Removed docs/archive from git** — conversation logs untracked to reduce repo noise.
- **Favicon 404** — `docs/favicon.svg` was missing from deployed GitHub Pages site.
- **Homepage title redundancy** — removed duplicate "powerglide" text before hero SVG on index page.

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
