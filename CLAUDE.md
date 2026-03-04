# Claude Code Guide — powerglide Repository

## Build & Test Commands

```bash
# Full build
zig build

# Run all tests (including leak checks)
zig build test --summary all

# Health check
./zig-out/bin/powerglide doctor
```

## Repository Guidelines

- **Style**: Follow idiomatic Zig 0.15.2 patterns. Use `std.fs.File.stdout().deprecatedWriter()` for I/O.
- **Memory**: Explicit allocation is required for all data structures. Use **unmanaged** `ArrayList` and `HashMap` where appropriate, passing the allocator to each method.
- **Ralph Loop**: Respect the 11-state model in `src/agent/loop.zig`.
- **Velocity**: Always use the **multiplier-based** velocity model (`delay = 1000 / velocity`). CLI flags and config values are `f64`.

## Project-Specific Context

- **Supercar Theme**: Use technical, high-performance terminology in prose. Avoid generic marketing fluff.
- **Commit Format**: `feat/fix/docs(module): description`. Author: `bkataru <baalateja.k@gmail.com>`.

## Zine Website

The documentation website is in `website/` and built with Zine.
To rebuild and deploy:
```bash
cd website && zig build
cp -r zig-out/docs/. ../docs/
```

## MCP Module

- `src/mcp/server.zig` — JSON-RPC 2.0 over stdin/stdout; start with `powerglide mcp`
- `src/mcp/client.zig` — subprocess MCP client; connects to external MCP servers
- `src/mcp/tool_bridge.zig` — converts `McpTool` → `Tool`, prefixed `mcp_{server}_{tool}`
- Config key: `mcp_servers` array in `~/.config/powerglide/config.json`

## igllama / Local LLM

Full Qwen3.5 lineup (download with `igllama pull unsloth/Qwen3.5-<N>B-GGUF -f <file>`):

- `:8090` → `Qwen3.5-0.8B-Q8_0.gguf`    (`local` agent)
- `:8091` → `Qwen3.5-2B-Q8_0.gguf`      (`local2b` agent)
- `:8092` → `Qwen3.5-4B-Q8_0.gguf`      (`local4b` agent)
- `:8093` → `Qwen3.5-9B-UD-Q4_K_XL.gguf` (`local9b` agent)

Start with: `igllama api <model> --port <N> --no-think --max-tokens 512 --threads 4 --threads-batch 16 --ctx-size 2048 --mlock`

- `OpenAIClient.json_mode = true` → forces `response_format: {"type":"json_object"}` for constrained output
- Doctor scans `:8090–8099` automatically
- Trial harness: `zig build trial` — runs T01–T13 × all 4 endpoints

## Current Version

`0.2.5` — 195/195 tests passing, 0 leaks.

## Roadmap

1. ✅ Zig 0.15.2 compatibility
2. ✅ Multi-agent swarm implementation
3. ✅ Ralph Loop integration
4. ✅ Technical overhaul of website & prose (supercar theme)
5. ✅ Refactored velocity to multiplier model
6. ✅ TUI implementation (vxfw multi-agent dashboard)
7. ✅ MCP integration (`src/mcp/` — server, client, tool_bridge)
8. ✅ igllama integration — local Qwen3.5 agents, json_mode, port scanning
9. ✅ Session summary output on `powerglide run` completion
10. ✅ Showcase page — dogfooding case studies: full Qwen3.5 lineup (0.8B/2B/4B/9B)
11. ✅ Zig trial harness (`examples/trial.zig`) — T01–T13 × 4 weight classes at Q4/Q8
12. ✅ igllama json_mode patch — GBNF grammar constraint via `response_format` (v0.3.9)
13. ✅ BF16 trial harness (`examples/trial_bf16.zig`) — T01–T13 × 4 models at full precision
14. ✅ Security: grep/glob tools use direct argv (no shell interpolation of user input)
