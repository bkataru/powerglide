/// powerglide × igllama — throughput benchmark
///
/// Measures tokens/second for each Qwen3.5 model by running a fixed prompt
/// RUNS_PER_MODEL times and averaging. Uses non-streaming completion with
/// usage.completion_tokens from the API response for accurate token counts.
/// Reports a summary table: model | tokens/sec | file_size | RAM_MB.
///
///   zig build bench
///
/// Models benchmarked span the full Q4→BF16 precision curve for all four
/// weight classes, plus Q8 as the reference point.
const std = @import("std");
const http_mod = @import("powerglide").http;

// ── Configuration ─────────────────────────────────────────────────────────────

const WORKDIR    = "/root/powerglide";
const MODELS_DIR = "/root/powerglide";
const IGLLAMA_BIN = "/root/igllama/zig-out/bin/igllama";
const BENCH_PORT: u16 = 8090;
const MAX_TOKENS: u32 = 200;
const RUNS_PER_MODEL: u32 = 3;
const HEALTH_POLL_MS: u64  = 2_000;
const HEALTH_TIMEOUT_S: u64 = 90;
const MODEL_COOLDOWN_MS: u64 = 2_000;
const RUN_COOLDOWN_MS: u64   = 1_000;

const SEP_THIN  = "──────────────────────────────────────────────────────────────";
const SEP_THICK = "══════════════════════════════════════════════════════════════";
const SEP_BLOCK = "██████████████████████████████████████████████████████████████";

// Fixed prompt designed to produce a predictable, token-dense response.
// "Count to 50" generates ~100 tokens with minimal reasoning variance.
const BENCH_PROMPT = "Count from 1 to 50 using commas. Output only numbers.";

const BenchModel = struct {
    name:  []const u8,
    file:  []const u8,
    group: []const u8,
};

// Representative subset: Q4 (smallest), Q8 (reference), BF16 (full precision)
// for each weight class. Covers the accuracy-vs-speed tradeoff across all sizes.
const BENCH_MODELS = [_]BenchModel{
    .{ .name = "0.8B-Q8",  .file = MODELS_DIR ++ "/Qwen3.5-0.8B-Q8_0.gguf",      .group = "0.8B" },
    .{ .name = "0.8B-BF16",.file = MODELS_DIR ++ "/Qwen3.5-0.8B-BF16.gguf",      .group = "0.8B" },
    .{ .name = "2B-Q4",    .file = MODELS_DIR ++ "/Qwen3.5-2B-UD-Q4_K_XL.gguf",  .group = "2B" },
    .{ .name = "2B-Q8",    .file = MODELS_DIR ++ "/Qwen3.5-2B-Q8_0.gguf",        .group = "2B" },
    .{ .name = "2B-BF16",  .file = MODELS_DIR ++ "/Qwen3.5-2B-BF16.gguf",        .group = "2B" },
    .{ .name = "4B-Q4",    .file = MODELS_DIR ++ "/Qwen3.5-4B-Q4_K_M.gguf",      .group = "4B" },
    .{ .name = "4B-Q8",    .file = MODELS_DIR ++ "/Qwen3.5-4B-Q8_0.gguf",        .group = "4B" },
    .{ .name = "4B-BF16",  .file = MODELS_DIR ++ "/Qwen3.5-4B-BF16.gguf",        .group = "4B" },
    .{ .name = "9B-Q4",    .file = MODELS_DIR ++ "/Qwen3.5-9B-UD-Q4_K_XL.gguf",  .group = "9B" },
    .{ .name = "9B-Q8",    .file = MODELS_DIR ++ "/Qwen3.5-9B-Q8_0.gguf",        .group = "9B" },
    .{ .name = "9B-BF16",  .file = MODELS_DIR ++ "/Qwen3.5-9B-BF16.gguf",        .group = "9B" },
};

// ── igllama lifecycle ─────────────────────────────────────────────────────────

fn killIgllama(allocator: std.mem.Allocator) void {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "pkill", "-f", "igllama api" },
    }) catch return;
    allocator.free(result.stdout);
    allocator.free(result.stderr);
    const killed = switch (result.term) {
        .Exited => |c| c == 0,
        else => false,
    };
    if (killed) std.Thread.sleep(3 * std.time.ns_per_s);
}

fn spawnIgllama(allocator: std.mem.Allocator, model_file: []const u8) !std.process.Child {
    const port_str = std.fmt.comptimePrint("{d}", .{BENCH_PORT});
    const argv = [_][]const u8{
        IGLLAMA_BIN, "api", model_file,
        "--port", port_str,
        "--no-think",
        "--max-tokens", "256",
        "--threads", "4",
        "--threads-batch", "16",
        "--ctx-size", "1024",
    };
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior  = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    return child;
}

fn waitForHealth(allocator: std.mem.Allocator, w: anytype) bool {
    var client = http_mod.HttpClient.init(allocator);
    defer client.deinit();
    const url = std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/health", .{BENCH_PORT}) catch return false;
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

// ── Bench run ─────────────────────────────────────────────────────────────────

const ReqMsg    = struct { role: []const u8, content: []const u8 };
const ReqFormat = struct { @"type": []const u8 };
const Request   = struct {
    model: []const u8,
    max_tokens: u32,
    temperature: f64,
    top_p: f64,
    top_k: u32,
    min_p: f64,
    stream: bool,
    response_format: ReqFormat,
    messages: []const ReqMsg,
};

/// Run one completion against the bench endpoint.
/// Returns (completion_tokens, elapsed_ms). Caller owns nothing — all freed internally.
fn runOnce(allocator: std.mem.Allocator, model_file: []const u8) !struct { tokens: u32, elapsed_ms: i64 } {
    const messages = [_]ReqMsg{
        .{ .role = "user", .content = BENCH_PROMPT },
    };
    const req = Request{
        .model = model_file, .max_tokens = MAX_TOKENS,
        .temperature = 0.0, .top_p = 1.0, .top_k = 1, .min_p = 0.0,
        .stream = false,
        .response_format = .{ .@"type" = "text" },
        .messages = &messages,
    };

    var body_buf = std.ArrayList(u8){};
    defer body_buf.deinit(allocator);
    try body_buf.writer(allocator).print("{f}", .{std.json.fmt(req, .{})});
    const body = try body_buf.toOwnedSlice(allocator);
    defer allocator.free(body);

    const url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/v1/chat/completions", .{BENCH_PORT});
    defer allocator.free(url);

    const headers = [_]std.http.Header{ .{ .name = "content-type", .value = "application/json" } };
    var client = http_mod.HttpClient.init(allocator);
    defer client.deinit();

    const t0 = std.time.milliTimestamp();
    var resp = try client.post(url, &headers, body);
    defer resp.deinit(allocator);
    const elapsed_ms = std.time.milliTimestamp() - t0;

    if (!resp.isSuccess()) return error.HttpError;

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp.body, .{});
    defer parsed.deinit();

    // Prefer usage.completion_tokens (accurate from igllama v0.3.11+).
    // Fall back to content-length estimate (~4 bytes/token) for older builds.
    const completion_tokens: u32 = blk: {
        if (parsed.value.object.get("usage")) |usage| {
            if (usage == .object) {
                if (usage.object.get("completion_tokens")) |ct| {
                    if (ct == .integer and ct.integer > 0) break :blk @intCast(ct.integer);
                }
            }
        }
        const choices = parsed.value.object.get("choices") orelse break :blk 0;
        if (choices.array.items.len == 0) break :blk 0;
        const msg = choices.array.items[0].object.get("message") orelse break :blk 0;
        const content = msg.object.get("content") orelse break :blk 0;
        if (content != .string) break :blk 0;
        break :blk @intCast(content.string.len / 4);
    };

    return .{ .tokens = completion_tokens, .elapsed_ms = elapsed_ms };
}

// ── File size helper ──────────────────────────────────────────────────────────

fn fileSizeMB(path: []const u8) f64 {
    const f = std.fs.openFileAbsolute(path, .{}) catch return 0;
    defer f.close();
    const stat = f.stat() catch return 0;
    return @as(f64, @floatFromInt(stat.size)) / (1024.0 * 1024.0);
}

// ── RSS memory helper ─────────────────────────────────────────────────────────

/// Read igllama's VmRSS from /proc/<pid>/status. Returns MB or 0 on error.
fn readRssMB(allocator: std.mem.Allocator) f64 {
    // Find igllama api PID via pgrep.
    const r = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "pgrep", "-f", "igllama api" },
    }) catch return 0;
    defer allocator.free(r.stdout);
    defer allocator.free(r.stderr);
    const pid_str = std.mem.trimRight(u8, r.stdout, " \n\r");
    if (pid_str.len == 0) return 0;
    // Take first PID if multiple lines.
    const first_line = std.mem.sliceTo(pid_str, '\n');
    const pid = std.fmt.parseInt(u32, first_line, 10) catch return 0;
    const status_path = std.fmt.allocPrint(allocator, "/proc/{d}/status", .{pid}) catch return 0;
    defer allocator.free(status_path);
    const f = std.fs.openFileAbsolute(status_path, .{}) catch return 0;
    defer f.close();
    const data = f.readToEndAlloc(allocator, 64 * 1024) catch return 0;
    defer allocator.free(data);
    // Search for "VmRSS:    <N> kB"
    const needle = "VmRSS:";
    const pos = std.mem.indexOf(u8, data, needle) orelse return 0;
    const rest = data[pos + needle.len..];
    const trimmed = std.mem.trimLeft(u8, rest, " \t");
    const end = std.mem.indexOfAny(u8, trimmed, " \n\r\t") orelse trimmed.len;
    const kb = std.fmt.parseInt(u64, trimmed[0..end], 10) catch return 0;
    return @as(f64, @floatFromInt(kb)) / 1024.0;
}

// ── Main ─────────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const w = std.fs.File.stdout().deprecatedWriter();

    try w.writeAll("\npowerglide x igllama — throughput benchmark\n");
    try w.print("Prompt: \"{s}\"\n", .{BENCH_PROMPT});
    try w.print("Runs per model: {d}   max_tokens: {d}   temp: 0.0 (greedy)\n\n", .{ RUNS_PER_MODEL, MAX_TOKENS });

    const BenchResult = struct {
        tok_per_sec: f64,
        file_mb: f64,
        rss_mb: f64,
        skipped: bool,
    };
    var results: [BENCH_MODELS.len]BenchResult = undefined;
    for (&results) |*r| r.* = .{ .tok_per_sec = 0, .file_mb = 0, .rss_mb = 0, .skipped = true };

    for (BENCH_MODELS, 0..) |bm, mi| {
        try w.print("\n{s}\n  MODEL: {s}\n{s}\n", .{ SEP_BLOCK, bm.name, SEP_BLOCK });

        killIgllama(allocator);
        std.Thread.sleep(MODEL_COOLDOWN_MS * std.time.ns_per_ms);

        try w.print("  Starting igllama api {s}...\n", .{bm.file});
        var child = spawnIgllama(allocator, bm.file) catch |e| {
            try w.print("  SPAWN_ERR: {} -- skipping\n", .{e});
            continue;
        };
        defer _ = child.kill() catch {};

        try w.writeAll("  Waiting for health");
        if (!waitForHealth(allocator, w)) {
            try w.writeAll("\n  Health: TIMEOUT -- skipping\n");
            continue;
        }
        try w.writeAll("\n  Health: OK\n");

        // Read RAM after model load (before inference).
        const rss_mb = readRssMB(allocator);

        var total_tokens: u32 = 0;
        var total_ms: i64 = 0;
        var run_ok: u32 = 0;
        for (0..RUNS_PER_MODEL) |run_i| {
            std.Thread.sleep(RUN_COOLDOWN_MS * std.time.ns_per_ms);
            try w.print("  run {d}/{d}: ", .{ run_i + 1, RUNS_PER_MODEL });
            const r = runOnce(allocator, bm.file) catch |e| {
                try w.print("ERR({s})\n", .{@errorName(e)});
                continue;
            };
            const tps = if (r.elapsed_ms > 0)
                @as(f64, @floatFromInt(r.tokens)) * 1000.0 / @as(f64, @floatFromInt(r.elapsed_ms))
            else 0;
            try w.print("{d} tokens / {d:.1}s = {d:.1} tok/s\n", .{
                r.tokens,
                @as(f64, @floatFromInt(r.elapsed_ms)) / 1000.0,
                tps,
            });
            total_tokens += r.tokens;
            total_ms += r.elapsed_ms;
            run_ok += 1;
        }

        if (run_ok > 0) {
            const avg_tps = @as(f64, @floatFromInt(total_tokens)) * 1000.0 /
                @as(f64, @floatFromInt(total_ms));
            results[mi] = .{
                .tok_per_sec = avg_tps,
                .file_mb = fileSizeMB(bm.file),
                .rss_mb = rss_mb,
                .skipped = false,
            };
            try w.print("  avg: {d:.1} tok/s   RAM: {d:.0} MB\n", .{ avg_tps, rss_mb });
        }
    }

    // ── Summary table ──────────────────────────────────────────────────────────
    try w.print("\n\n{s}\n", .{SEP_THICK});
    try w.writeAll("  RESULTS — throughput benchmark (tokens/second, CPU-only inference)\n");
    try w.print("{s}\n\n", .{SEP_THICK});
    try w.writeAll("  Model         tok/s   File(GB)  RAM(GB)\n");
    try w.writeAll("  ─────────────────────────────────────────\n");

    var prev_group: []const u8 = "";
    for (BENCH_MODELS, 0..) |bm, mi| {
        if (!std.mem.eql(u8, bm.group, prev_group)) {
            try w.print("\n  [{s}]\n", .{bm.group});
            prev_group = bm.group;
        }
        const r = results[mi];
        if (r.skipped) {
            try w.print("  {s:<12}  SKIPPED\n", .{bm.name});
        } else {
            try w.print("  {s:<12}  {d:5.1}   {d:5.1}      {d:5.1}\n", .{
                bm.name, r.tok_per_sec,
                r.file_mb / 1024.0,
                r.rss_mb / 1024.0,
            });
        }
    }
    try w.writeAll("\n");
}
