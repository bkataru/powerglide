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

## Roadmap

1. ✅ Zig 0.15.2 compatibility
2. ✅ Multi-agent swarm implementation
3. ✅ Ralph Loop integration
4. ✅ Technical overhaul of website & prose
5. ✅ Refactored velocity to multiplier model
6. ⏳ Finished TUI implementation
7. ⏳ MCP server integration
