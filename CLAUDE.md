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

- `local` agent → `Qwen3.5-0.8B-Q8_0.gguf` on `http://127.0.0.1:8090/v1`
- `local4b` agent → `Qwen3.5-4B-Q8_0.gguf` on `http://127.0.0.1:8091/v1`
- Start with: `igllama api <model.gguf> --port <N> --no-think`
- `OpenAIClient.json_mode = true` → forces `response_format: {"type":"json_object"}` for constrained output
- Doctor scans `:8090–8099` automatically

## Current Version

`0.2.2` — 195/195 tests passing, 0 leaks.

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
10. ✅ Showcase page — dogfooding case studies with 0.8B and 4B models
