/// powerglide × igllama — context length sensitivity harness
///
/// Measures how pass rate changes across ctx-size 512/1024/2048/4096 for the
/// 2B-Q6 sweet-spot model. The hypothesis: some T01-T17 failures on 2B are
/// context-limited rather than capacity-limited. Varying ctx-size isolates this.
///
/// All runs use the same 2B-Q6 GGUF; only --ctx-size changes between sweeps.
/// Sequential runs on :8090; the harness manages igllama lifecycle per ctx-size.
///
///   zig build ctx
///
const std = @import("std");
const http_mod = @import("powerglide").http;

// ── Configuration ─────────────────────────────────────────────────────────────

const WORKDIR      = "/root/powerglide";
const MODELS_DIR   = "/root/powerglide";
const IGLLAMA_BIN  = "/root/igllama/zig-out/bin/igllama";
const CTX_PORT: u16 = 8090;
const MAX_TURNS: u32 = 12;
const RESULT_TRUNC: usize = 900;
const MAX_TOKENS: u32 = 512;
const TASK_COOLDOWN_MS: u64 = 500;
const RETRY_DELAY_MS: u64 = 5_000;
const MAX_RETRIES: u32 = 3;
const HEALTH_POLL_MS: u64 = 2_000;
const HEALTH_TIMEOUT_S: u64 = 90;
const MODEL_COOLDOWN_MS: u64 = 2_000;

const TEMPERATURE: f64 = 0.7;
const TOP_P: f64 = 0.8;
const TOP_K: u32 = 20;
const MIN_P: f64 = 0.0;

const SEP_THIN  = "──────────────────────────────────────────────────────────────";
const SEP_THICK = "══════════════════════════════════════════════════════════════";
const SEP_BLOCK = "██████████████████████████████████████████████████████████████";

// Model under test — 2B-Q6 is the accuracy sweet spot for the 2B weight class.
const MODEL_FILE = MODELS_DIR ++ "/Qwen3.5-2B-Q6_K.gguf";
const MODEL_NAME = "2B-Q6";

// Context sizes to sweep. Igllama default is 2048.
const CTX_SIZES = [_]u32{ 512, 1024, 2048, 4096 };

// ── System prompt ─────────────────────────────────────────────────────────────

const SYSTEM_PROMPT =
    \\You are a coding assistant in an agentic tool loop.
    \\Each turn: output EXACTLY ONE JSON object. No markdown fences. No extra text.
    \\
    \\Available tools:
    \\  {"tool":"bash",  "args":{"command":"<shell command>"}}
    \\  {"tool":"read",  "args":{"path":"<file path>"}}
    \\  {"tool":"write", "args":{"path":"<path>","content":"<text>"}}
    \\  {"tool":"done",  "args":{"answer":"<your answer>"}}
    \\
    \\Rules:
    \\- Exactly ONE JSON object per turn, nothing else.
    \\- Use grep/head/tail/wc instead of reading whole files.
    \\- After you have the answer, call done immediately. Do not issue extra tool calls.
    \\- Working directory: /root/powerglide.
;

// ── Tasks (T01–T17 — same as trial.zig / trial_quant.zig) ────────────────────

const Task = struct {
    name: []const u8,
    prompt: []const u8,
};

const TASKS = [_]Task{
    .{
        .name = "T01 Grep: VERSION constant",
        .prompt = "bash: grep -n 'VERSION' src/main.zig | head -3\nReport the version string.",
    },
    .{
        .name = "T02 Count LoopState enum variants",
        .prompt =
        \\bash: sed -n '/LoopState = enum/,/^};/p' src/agent/loop.zig | grep -cE '^\s+[a-z_]+,$'
        \\Report the integer count of LoopState variants.
        ,
    },
    .{
        .name = "T03 Write + verify: Zig clamp",
        .prompt =
        \\Write /tmp/pg_clamp.zig with exactly:
        \\const std = @import("std");
        \\pub fn clamp(val: f64, lo: f64, hi: f64) f64 { return @min(@max(val, lo), hi); }
        \\Then bash: cat /tmp/pg_clamp.zig
        ,
    },
    .{
        .name = "T04 Read + Write: summarise swarm.zig",
        .prompt =
        \\bash: head -n 40 src/orchestrator/swarm.zig
        \\Write a 2-sentence summary to /tmp/swarm_zig.txt
        \\bash: cat /tmp/swarm_zig.txt
        ,
    },
    .{
        .name = "T05 Grep: TODO comments",
        .prompt = "bash: grep -rn 'TODO' src/ --include='*.zig' 2>/dev/null | wc -l\nReport the count.",
    },
    .{
        .name = "T06 Multi-file struct names",
        .prompt = "bash: grep -n 'pub const.*Client' src/models/anthropic.zig src/models/openai.zig\nReport the struct name from each file.",
    },
    .{
        .name = "T07 Count lines in loop.zig",
        .prompt = "bash: wc -l src/agent/loop.zig\nReport the line count.",
    },
    .{
        .name = "T08 List pub fn in router.zig",
        .prompt =
        \\bash: grep -n 'pub fn ' src/models/router.zig
        \\Report the function names. Call done immediately after this one tool call.
        ,
    },
    .{
        .name = "T09 Find max_steps default",
        .prompt = "bash: grep -n 'max_steps' src/agent/loop.zig | head -3\nWhat is the default value?",
    },
    .{
        .name = "T10 Write + run Python hello",
        .prompt =
        \\write: /tmp/pg_hello.py  content: print("hello from powerglide")
        \\bash: python3 /tmp/pg_hello.py
        \\Report what it printed.
        ,
    },
    .{
        .name = "T11 Summarise agent/ files",
        .prompt =
        \\bash: head -n 4 src/agent/loop.zig src/agent/manager.zig src/agent/session.zig
        \\Summarise each file in one sentence. Call done immediately.
        ,
    },
    .{
        .name = "T12 Arithmetic: compute delay_ms",
        .prompt =
        \\bash: grep -n 'velocity\|delay' src/orchestrator/swarm.zig | head -6
        \\If velocity=2.5, what is delay_ms using the formula delay_ms = 1000/velocity?
        ,
    },
    .{
        .name = "T13 Error recovery: bad path",
        .prompt =
        \\bash: cat /tmp/nonexistent_pg_file_xyz.txt
        \\The file does not exist. What did the error say? Then write "recovered" to /tmp/pg_recovery.txt and read it back.
        ,
    },
    .{
        .name = "T14 Code gen: write + fmt Zig fibonacci",
        .prompt =
        \\write: /tmp/pg_fib.zig  content:
        \\const std = @import("std");
        \\pub fn fib(n: u64) u64 { if (n <= 1) return n; return fib(n-1) + fib(n-2); }
        \\pub fn main() void { std.debug.print("{d}\n", .{fib(10)}); }
        \\Then: bash: /root/.local/share/mise/installs/zig/0.15.2/bin/zig fmt /tmp/pg_fib.zig && echo "fmt ok"
        ,
    },
    .{
        .name = "T15 JSON round-trip: write + read + verify",
        .prompt =
        \\write: /tmp/pg_data.json  content: {"project":"powerglide","version":"0.2.6","tasks":17}
        \\bash: python3 -c "import json; d=json.load(open('/tmp/pg_data.json')); print(d['project'], d['version'], d['tasks'])"
        \\Report all three values.
        ,
    },
    .{
        .name = "T16 Error recovery: observe exit 1 + fix",
        .prompt =
        \\bash: /root/.local/share/mise/installs/zig/0.15.2/bin/zig build-exe /tmp/nonexistent_pg.zig 2>&1 | head -3
        \\The command will fail. Report the error and explain in one sentence why it failed.
        ,
    },
    .{
        .name = "T17 Multi-source synthesis",
        .prompt =
        \\bash: head -n 2 src/agent/loop.zig
        \\bash: head -n 2 src/orchestrator/swarm.zig
        \\Synthesize: in one sentence, describe how loop.zig and swarm.zig relate to each other in the powerglide architecture.
        ,
    },
};

// ── igllama lifecycle ─────────────────────────────────────────────────────────

fn killIgllama(allocator: std.mem.Allocator) void {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "pkill", "-f", "igllama" },
    }) catch return;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    const killed = switch (result.term) {
        .Exited => |c| c == 0,
        else => false,
    };
    if (killed) std.Thread.sleep(3 * std.time.ns_per_s);
}

fn spawnIgllama(allocator: std.mem.Allocator, ctx_size: u32) !std.process.Child {
    const port_str = std.fmt.comptimePrint("{d}", .{CTX_PORT});
    const ctx_str = try std.fmt.allocPrint(allocator, "{d}", .{ctx_size});
    // Free after spawn — ctx_str must be alive during child.spawn() (passed to OS exec).
    // Explicit free (not defer) ensures we don't free before spawn returns.

    const argv = [_][]const u8{
        IGLLAMA_BIN, "api", MODEL_FILE,
        "--port", port_str,
        "--no-think",
        "--max-tokens", "512",
        "--threads", "4",
        "--threads-batch", "16",
        "--ctx-size", ctx_str,
    };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior  = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    allocator.free(ctx_str);
    return child;
}

fn waitForHealth(allocator: std.mem.Allocator, w: anytype) bool {
    var client = http_mod.HttpClient.init(allocator);
    defer client.deinit();
    const url = std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/health", .{CTX_PORT}) catch return false;
    defer allocator.free(url);

    const deadline = std.time.timestamp() + @as(i64, @intCast(HEALTH_TIMEOUT_S));
    while (std.time.timestamp() < deadline) {
        std.Thread.sleep(HEALTH_POLL_MS * std.time.ns_per_ms);
        var resp = client.get(url, &.{}) catch { w.print(".", .{}) catch {}; continue; };
        defer resp.deinit(allocator);
        if (resp.isSuccess() and std.mem.indexOf(u8, resp.body, "ok") != null) return true;
        w.print(".", .{}) catch {};
    }
    return false;
}

// ── HTTP helpers ──────────────────────────────────────────────────────────────

fn getString(val: std.json.Value, key: []const u8) ?[]const u8 {
    if (val != .object) return null;
    const v = val.object.get(key) orelse return null;
    if (v != .string) return null;
    return v.string;
}

fn escapeJsonString(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    for (s) |c| {
        switch (c) {
            '"'  => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => try out.append(allocator, c),
        }
    }
    return out.toOwnedSlice(allocator);
}

fn buildMessages(allocator: std.mem.Allocator, turns: []const []const u8) ![]u8 {
    var buf = std.ArrayList(u8){};
    try buf.appendSlice(allocator, "[");
    var first = true;
    for (turns, 0..) |t, i| {
        if (!first) try buf.appendSlice(allocator, ",");
        first = false;
        const role = if (i % 2 == 0) "user" else "assistant";
        const escaped = try escapeJsonString(allocator, t);
        defer allocator.free(escaped);
        const msg = try std.fmt.allocPrint(allocator,
            \\{{"role":"{s}","content":"{s}"}}
        , .{ role, escaped });
        defer allocator.free(msg);
        try buf.appendSlice(allocator, msg);
    }
    try buf.appendSlice(allocator, "]");
    return buf.toOwnedSlice(allocator);
}

fn chatOnce(allocator: std.mem.Allocator, sys_escaped: []const u8, turns: []const []const u8) ![]u8 {
    var client = http_mod.HttpClient.init(allocator);
    defer client.deinit();

    const msgs = try buildMessages(allocator, turns);
    defer allocator.free(msgs);

    const body = try std.fmt.allocPrint(allocator,
        \\{{"model":"local","messages":[{{"role":"system","content":"{s}"}},{s}],"temperature":{d:.1},"top_p":{d:.1},"top_k":{d},"min_p":{d:.1},"max_tokens":{d},"stream":false}}
    , .{ sys_escaped, msgs, TEMPERATURE, TOP_P, TOP_K, MIN_P, MAX_TOKENS });
    defer allocator.free(body);

    const url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/v1/chat/completions", .{CTX_PORT});
    defer allocator.free(url);

    const headers = [_]std.http.Header{
        .{ .name = "content-type", .value = "application/json" },
    };
    var resp = try client.post(url, &headers, body);
    defer resp.deinit(allocator);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp.body, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return error.BadResponse;
    const choices = parsed.value.object.get("choices") orelse return error.NoChoices;
    if (choices.array.items.len == 0) return error.EmptyChoices;
    const msg = choices.array.items[0].object.get("message") orelse return error.NoMessage;
    const content = getString(msg, "content") orelse return error.NoContent;
    return allocator.dupe(u8, content);
}

fn dispatch(allocator: std.mem.Allocator, tool: []const u8, args: std.json.Value) ![]u8 {
    if (std.mem.eql(u8, tool, "bash")) {
        const cmd = getString(args, "command") orelse return allocator.dupe(u8, "(missing command)");
        return runBash(allocator, cmd);
    } else if (std.mem.eql(u8, tool, "read")) {
        const path = getString(args, "path") orelse return allocator.dupe(u8, "(missing path)");
        return readFile(allocator, path);
    } else if (std.mem.eql(u8, tool, "write")) {
        const path    = getString(args, "path")    orelse return allocator.dupe(u8, "(missing path)");
        const content = getString(args, "content") orelse return allocator.dupe(u8, "(missing content)");
        return writeFile(allocator, path, content);
    }
    return allocator.dupe(u8, "(unknown tool)");
}

fn runBash(allocator: std.mem.Allocator, cmd: []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "/bin/sh", "-c", cmd },
        .cwd = WORKDIR,
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    const raw = if (result.stdout.len > 0) result.stdout else result.stderr;
    const trimmed = std.mem.trimRight(u8, raw, " \n\r");
    const rc: u8 = switch (result.term) { .Exited => |c| c, else => 1 };
    const full = if (rc != 0)
        try std.fmt.allocPrint(allocator, "{s}\n[exit {d}]", .{ trimmed, rc })
    else
        try allocator.dupe(u8, trimmed);
    if (full.len <= RESULT_TRUNC) return full;
    const truncated = try allocator.dupe(u8, full[0..RESULT_TRUNC]);
    allocator.free(full);
    return truncated;
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const safe = resolveSafePath(path) orelse return allocator.dupe(u8, "(path not allowed)");
    const f = std.fs.openFileAbsolute(safe, .{}) catch |e| {
        return std.fmt.allocPrint(allocator, "(open error: {})", .{e});
    };
    defer f.close();
    var buf: [RESULT_TRUNC]u8 = undefined;
    const n = try f.read(&buf);
    return allocator.dupe(u8, buf[0..n]);
}

fn writeFile(allocator: std.mem.Allocator, path: []const u8, content: []const u8) ![]u8 {
    _ = resolveSafePath(path) orelse return allocator.dupe(u8, "(path not allowed)");
    const f = std.fs.createFileAbsolute(path, .{}) catch |e| {
        return std.fmt.allocPrint(allocator, "(create error: {})", .{e});
    };
    defer f.close();
    try f.writeAll(content);
    return std.fmt.allocPrint(allocator, "wrote {d} bytes to {s}", .{ content.len, path });
}

fn resolveSafePath(path: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, path, "/tmp/") or
        std.mem.startsWith(u8, path, "/root/powerglide/") or
        std.mem.startsWith(u8, path, "src/") or
        std.mem.eql(u8, path, "src"))
    {
        return path;
    }
    return null;
}

// ── Task runner ───────────────────────────────────────────────────────────────

const TaskResult = struct {
    passed: bool,
    turns: u32,
    elapsed_ms: i64,

    fn deinit(_: *TaskResult, _: std.mem.Allocator) void {}
};

fn runTask(allocator: std.mem.Allocator, sys_escaped: []const u8, task: Task, w: anytype) !TaskResult {
    var turns = std.ArrayList([]const u8){};
    defer {
        for (turns.items) |t| allocator.free(t);
        turns.deinit(allocator);
    }

    const start = std.time.milliTimestamp();
    const first_msg = try allocator.dupe(u8, task.prompt);
    try turns.append(allocator, first_msg);

    var turn_count: u32 = 0;
    var passed = false;

    while (turn_count < MAX_TURNS) : (turn_count += 1) {
        var reply: []u8 = undefined;
        var attempt: u32 = 0;
        while (attempt < MAX_RETRIES) : (attempt += 1) {
            reply = chatOnce(allocator, sys_escaped, turns.items) catch |err| {
                try w.print("  [retry {d}/3 err={}]\n", .{ attempt + 1, err });
                std.Thread.sleep(RETRY_DELAY_MS * std.time.ns_per_ms);
                continue;
            };
            break;
        } else {
            try w.writeAll("  FAIL: max retries exhausted\n");
            break;
        }
        defer allocator.free(reply);

        const trimmed = std.mem.trim(u8, reply, " \t\n\r");

        // Find JSON object boundaries
        const obj_start = std.mem.indexOf(u8, trimmed, "{") orelse {
            try w.print("  FAIL: no JSON in reply: {s}\n", .{trimmed[0..@min(100, trimmed.len)]});
            break;
        };
        const obj_end = std.mem.lastIndexOf(u8, trimmed, "}") orelse {
            try w.writeAll("  FAIL: no closing }\n");
            break;
        };
        const json_slice = trimmed[obj_start .. obj_end + 1];

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_slice, .{}) catch {
            try w.print("  FAIL: invalid JSON: {s}\n", .{json_slice[0..@min(120, json_slice.len)]});
            break;
        };
        defer parsed.deinit();

        const root = parsed.value;
        const tool = getString(root, "tool") orelse blk: {
            if (root.object.get("args")) |_| break :blk "";
            break :blk "";
        };

        // Log the tool call
        {
            const args = blk: {
                if (root == .object) break :blk root.object.get("args") orelse root;
                break :blk root;
            };
            var args_buf = std.ArrayList(u8){};
            defer args_buf.deinit(allocator);
            try args_buf.writer(allocator).print("{f}", .{std.json.fmt(args, .{ .whitespace = .minified })});
            const args_str = try args_buf.toOwnedSlice(allocator);
            defer allocator.free(args_str);
            try w.print("  [{d}] {s}({s})\n", .{ turn_count + 1, tool, args_str[0..@min(80, args_str.len)] });

            if (std.mem.eql(u8, tool, "done")) {
                const answer: []const u8 = blk: {
                    if (args != .object) break :blk "";
                    const v = args.object.get("answer") orelse break :blk "";
                    if (v != .string) break :blk "";
                    break :blk v.string;
                };
                try w.print("  PASS answer={s}\n", .{answer[0..@min(120, answer.len)]});
                passed = true;
                break;
            }
        }

        // Execute tool
        const args_val = root.object.get("args") orelse std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
        const result = try dispatch(allocator, tool, args_val);
        defer allocator.free(result);
        try w.print("  result={s}\n", .{result[0..@min(200, result.len)]});

        // Append assistant reply + tool result as next user turn
        const assistant_turn = try allocator.dupe(u8, json_slice);
        try turns.append(allocator, assistant_turn);
        const user_turn = try std.fmt.allocPrint(allocator, "Tool result: {s}", .{result});
        try turns.append(allocator, user_turn);

        std.Thread.sleep(TASK_COOLDOWN_MS * std.time.ns_per_ms);
    }

    return TaskResult{
        .passed = passed,
        .turns = turn_count + 1,
        .elapsed_ms = std.time.milliTimestamp() - start,
    };
}

// ── Main ──────────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const w = std.fs.File.stdout().deprecatedWriter();

    // Cache escaped system prompt once — reused across all tasks and ctx-sizes.
    const sys_escaped = try escapeJsonString(allocator, SYSTEM_PROMPT);
    defer allocator.free(sys_escaped);

    try w.writeAll("\npowerglide x igllama — context length sensitivity\n");
    try w.print("Model: {s}   ctx-sizes: 512 / 1024 / 2048 / 4096   Tasks: T01-T{d}\n\n", .{ MODEL_NAME, TASKS.len });

    // results[ctx_idx][task_idx]
    var results: [CTX_SIZES.len][TASKS.len]?TaskResult = .{.{null} ** TASKS.len} ** CTX_SIZES.len;
    defer {
        for (&results) |*row| for (row) |*mr| if (mr.*) |*r| r.deinit(allocator);
    }

    for (CTX_SIZES, 0..) |ctx, ci| {
        try w.print("\n{s}\n", .{SEP_BLOCK});
        try w.print("  ctx-size={d}  model={s}\n", .{ ctx, MODEL_FILE });
        try w.print("{s}\n", .{SEP_BLOCK});

        try w.writeAll("  Stopping previous igllama...\n");
        killIgllama(allocator);
        std.Thread.sleep(MODEL_COOLDOWN_MS * std.time.ns_per_ms);

        try w.print("  Starting igllama with ctx-size={d}...\n", .{ctx});
        var child = spawnIgllama(allocator, ctx) catch |e| {
            try w.print("  SPAWN_ERR: {} -- skipping\n", .{e});
            continue;
        };
        defer _ = child.kill() catch {};

        try w.writeAll("  Waiting for health");
        const healthy = waitForHealth(allocator, w);
        try w.writeAll("\n");
        if (!healthy) {
            try w.writeAll("  Health: TIMEOUT -- skipping\n");
            continue;
        }
        try w.writeAll("  Health: OK\n");

        for (TASKS, 0..) |task, ti| {
            try w.print("\n{s}\n  {s}\n{s}\n", .{ SEP_THIN, task.name, SEP_THIN });
            std.Thread.sleep(TASK_COOLDOWN_MS * std.time.ns_per_ms);
            const r = runTask(allocator, sys_escaped, task, w) catch |err| blk: {
                try w.print("  RUN_ERR: {}\n", .{err});
                break :blk TaskResult{ .passed = false, .turns = 0, .elapsed_ms = 0 };
            };
            results[ci][ti] = r;
        }

    }

    // ── Results table ─────────────────────────────────────────────────────────
    try w.print("\n\n{s}\n", .{SEP_THICK});
    try w.writeAll("  CONTEXT LENGTH SENSITIVITY — 2B-Q6\n");
    try w.print("{s}\n\n", .{SEP_THICK});

    try w.print("{s:<10}  {s:>6}  {s:>6}  {s:>8}\n", .{ "ctx-size", "Passed", "Turns", "Time(s)" });
    try w.print("{s}\n", .{SEP_THIN});

    for (CTX_SIZES, 0..) |ctx, ci| {
        var passed_count: u32 = 0;
        var total_turns: u32 = 0;
        var total_ms: i64 = 0;
        for (results[ci]) |mr| {
            if (mr) |r| {
                if (r.passed) passed_count += 1;
                total_turns += r.turns;
                total_ms += r.elapsed_ms;
            }
        }
        try w.print("{d:<10}  {d:>2}/{d:<2}  {d:>6}  {d:>8}\n",
            .{ ctx, passed_count, TASKS.len, total_turns, @divTrunc(total_ms, 1000) });
    }

    try w.print("\n{s}\n", .{SEP_THIN});
    try w.writeAll("  Per-task breakdown:\n");
    try w.print("{s}\n", .{SEP_THIN});
    try w.print("{s:<35}", .{"Task"});
    for (CTX_SIZES) |ctx| try w.print("  {d:>4}", .{ctx});
    try w.writeAll("\n");
    try w.print("{s}\n", .{SEP_THIN});

    for (TASKS, 0..) |task, ti| {
        try w.print("{s:<35}", .{task.name[0..@min(35, task.name.len)]});
        for (0..CTX_SIZES.len) |ci| {
            const sym: []const u8 = if (results[ci][ti]) |r| (if (r.passed) " PASS" else " FAIL") else "  -- ";
            try w.writeAll(sym);
        }
        try w.writeAll("\n");
    }

    try w.print("\n{s}\n", .{SEP_THICK});
    try w.writeAll("  ctx_sensitivity complete.\n");
    try w.print("{s}\n\n", .{SEP_THICK});
}
