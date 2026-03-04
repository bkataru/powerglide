# Changelog

All notable changes to the **powerglide** project will be documented in this file.

## [0.2.5] - 2026-03-04

### Added
- **BF16 trial harness** — `examples/trial_bf16.zig` runs T01–T13 × 4 Qwen3.5 models (0.8B/2B/4B/9B) at full BF16 precision; manages igllama lifecycle (spawn, health-poll, kill) per model
- **`zig build trial-bf16`** — new build step mirroring `zig build trial`
- **igllama json_mode** — patched igllama v0.3.9: `response_format: {"type":"json_object"}` now wires `JSON_GRAMMAR` GBNF constraint into the llama.cpp sampler chain via `llama_sampler_init_grammar()`

### Fixed
- **Shell injection in grep/glob tools** — `grep_handler` and `glob_handler` previously interpolated user-controlled `pattern`/`path` into shell command strings via `std.fmt.allocPrint` + `/bin/sh -c`. Replaced with direct `execve`-style argv arrays (`grep -rn -- pattern path`, `find path -name pattern -type f`). Output truncated to 100 lines post-hoc.
- **MCP tool name validation** — `mcpToolToTool` now validates `server_name` and `mcp_tool.name` against `[a-zA-Z0-9_-]` before constructing the prefixed name; returns `error.InvalidToolName` for malformed inputs.
- **README port/model mismatch** — corrected local LLM section: full 4-port lineup (`:8090–:8093`), added 2B/9B models, fixed 4B port (`:8092` not `:8091`).

### Changed
- **CLAUDE.md**: version bumped to 0.2.5; 9B model corrected to `Qwen3.5-9B-UD-Q4_K_XL.gguf`; roadmap items 12–14 added.

## [0.2.4] - 2026-03-04

### Added
- **Q8 quantization for 2B and 9B** — downloaded `Qwen3.5-2B-Q8_0.gguf` (1.9 GB) and `Qwen3.5-9B-Q8_0.gguf` (8.9 GB) via `igllama pull`; both now run at full Q8 precision
- **Quantization sensitivity findings** — Q8 vs Q4 trial: 2B improved from 8/13 to 11/13 (+3 tasks, 42% fewer turns); 9B hallucination on T01 persists but tool-use tasks now all correct; 0.8B and 4B unaffected

### Changed
- **Port layout**: 2B now serves `Qwen3.5-2B-Q8_0.gguf` on :8091; 9B now serves `Qwen3.5-9B-Q8_0.gguf` on :8093
- **trial.zig ENDPOINTS**: updated model filenames from UD-Q4_K_XL to Q8_0 for 2B and 9B
- **CLAUDE.md**: updated local LLM lineup to reflect Q8 models

### Fixed
- **9B hallucination partially resolved** — at Q8, 9B correctly runs tools for T07/T12/T13/T06 (was hallucinating from memory at Q4); T01 VERSION still hallucinated in 1-turn responses

## [0.2.3] - 2026-03-04

### Added
- **Zig trial harness** — `examples/trial.zig` runs T01–T13 across the full Qwen3.5 lineup via `zig build trial`; replaces Python scripts; pure Zig, part of the build system
- **Full Qwen3.5 lineup** — 4 weight classes now triaged: 0.8B-Q8 (:8090), 2B-Q4 (:8091), 4B-Q8 (:8092), 9B-Q4 (:8093); GGUFs downloaded via `igllama pull`
- **Showcase rewrite** — Case Studies 5–6 replaced with Zig trial results; 9B added; qwen2.5-coder-0.5b removed throughout; new "9B hallucinates, 4B verifies" finding documented

### Fixed
- **Harness: flat-args fallback** — models that emit `{"tool":"bash","command":"..."}` at top level (no `args` wrapper) now dispatch correctly
- **Harness: PARSE_ERR on pretty-printed JSON** — igllama json_mode emits literal `\n` between tokens; `unescapeControlChars` + retry resolves without model restart
- **Harness: escape-loop prevention** — feeding "unknown tool" back to small models caused exponential backslash escaping; replaced with targeted format reminder

### Changed
- **Port layout updated**: 0.8B→:8090, 2B→:8091, 4B→:8092, 9B→:8093 (was 4B on :8091, 0.5B-coder on :8092)
- **qwen2.5-coder-0.5b removed** from lineup, GGUF deleted, all showcase references purged

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
