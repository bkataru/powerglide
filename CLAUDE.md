# CLAUDE.md — Guide for Claude Code in powerglide

## Build Commands

- `zig build` — build the project
- `zig build test` — run all tests  
- `zig build run -- --help` — run powerglide with --help
- `zig build run -- --version` — run powerglide with --version

## Key Files

- `src/main.zig` — entry point and CLI dispatch
- `src/agent/loop.zig` — ralph loop state machine
- `src/terminal/pty.zig` — PTY management
- `src/models/router.zig` — multi-model routing
- `src/orchestrator/swarm.zig` — multi-agent coordination
- `build.zig` — build configuration with dependencies

## Zig 0.15.2 Notes

- **Reader/Writer API**: use `std.io.AnyReader` / `std.io.AnyWriter`
- **std.ArrayList**: `.append()` for single items, `.appendSlice()` for slices
- **Build deps**: `b.dependency()` pattern in build.zig
- **Zig stdlib**: `/root/.local/share/mise/installs/zig/0.15.2/lib/zig/std/`
- **ArenaAllocator**: Use `std.heap.ArenaAllocator` for temporary allocations
- **Process args**: Use `std.process.argsAlloc()` and `std.process.argsFree()`
- **Reserved keywords**: `error` is reserved; use alternatives like `failed` or `err`

## Commit Protocol

Always commit as:

```bash
git -c user.name="bkataru" -c user.email="baalateja.k@gmail.com" commit -m "..."
```

## Dependencies

- **zig-clap** — CLI argument parsing (https://github.com/Hejsil/zig-clap)
- **libvaxis** — TUI framework (https://github.com/rockorager/libvaxis)

Both are fetched via `zig fetch` and configured in `build.zig.zon`.

## Testing

Run tests with:

```bash
zig build test
```

All modules include placeholder tests that verify basic compilation.

## Common Patterns

```zig
// Creating an arena allocator
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const allocator = arena.allocator();

// HashMap usage
var map = std.StringHashMap(T).init(allocator);
defer map.deinit();
try map.put(key, value);

// ArrayList usage
var list = std.ArrayList(T).init(allocator);
defer list.deinit();
try list.append(item);
```

## Project Structure

powerglide follows a modular architecture:

1. **agent/** — Agent loop and session management
2. **terminal/** — PTY, exit codes, terminal pooling
3. **models/** — HTTP client, model APIs, routing
4. **memory/** — Memory store and context
5. **config/** — Configuration management
6. **tools/** — Tool interface and registry
7. **tui/** — Terminal UI
8. **orchestrator/** — Worker, monitor, swarm coordination