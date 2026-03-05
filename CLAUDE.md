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
- Trial harness: `zig build trial` — runs T01–T17 × all 4 endpoints
- Quant harness: `zig build trial-quant` — runs T01–T17 × 16 models: 0.8B-BF16 | 2B (Q4/Q5/Q6/Q8/BF16) | 4B (Q4/Q5/Q6/Q8/BF16) | 9B (Q4/Q5/Q6/Q8/BF16), sequential on :8090
- Bench harness: `zig build bench` — tokens/sec throughput benchmark, accurate via igllama v0.3.10 `usage.completion_tokens`

## Current Version

`0.3.0` — 195/195 tests passing, 0 leaks.

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
11. ✅ Zig trial harness (`examples/trial.zig`) — T01–T17 × 4 weight classes at Q4/Q8
12. ✅ igllama json_mode fix — streaming handler use-after-free (v0.3.10)
13. ✅ Security: grep/glob tools use direct argv (no shell interpolation of user input)
14. ✅ Quantization sensitivity harness (`examples/trial_quant.zig`) — Q4/Q5/Q6/Q8/BF16 on 2B+9B
15. ✅ BF16 precision trials added to quant harness — full precision curve documented in showcase
16. ✅ /simplify pass — removed debug print, fixed JSON round-trip in MCP client, escaped JSON output in registry
17. ✅ /security-review pass — MCP input validation hardened, OOM guard on readLine, JSON injection in listAsJson fixed
18. ✅ 0.8B-BF16 added to quant harness — all four weight classes now have BF16 coverage; 4B-BF16 confirmed 13/13
19. ✅ MCP server hardened — type assertion panic fixed, OOM guard on stdin buffer, error logging filtered
20. ✅ 4B quant curve completed — Q4/Q5/Q6 GGUFs downloaded, full Q4→BF16 curve measured; 4B saturated at Q4
21. ✅ T01–T17 extended to trial_quant.zig — all 17 agentic tasks now in quantization sensitivity harness
22. ✅ Throughput benchmark (`examples/bench.zig`) — tokens/sec × RAM measurement across Q4/Q8/BF16 per weight class; igllama v0.3.10 usage.completion_tokens fix integrated
23. ✅ igllama v0.3.10 — populate usage.completion_tokens in non-streaming responses (patched upstream, PR #82)
