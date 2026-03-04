/// powerglide × igllama agentic trial harness
///
/// Runs T01–T13 across multiple Qwen3.5 local endpoints, measuring pass
/// rates, turn counts, and wall-clock latency. Reports a summary table.
///
///   zig build trial
///
/// Endpoints (start externally via igllama):
///   :8090  Qwen3.5-0.8B-Q8_0.gguf
///   :8091  Qwen3.5-4B-Q8_0.gguf
///   :8092  Qwen3.5-2B-UD-Q4_K_XL.gguf  (if downloaded)
///   :8093  qwen2.5-coder-0.5b-instruct-q8_0.gguf
///
/// igllama startup (tuned for CPU-only inference):
///   igllama api <model> --port N --no-think --max-tokens 512 \
///               --threads 4 --threads-batch 16 --ctx-size 2048 --mlock
const std = @import("std");
const http_mod = @import("powerglide").http;

// ── Configuration ─────────────────────────────────────────────────────────────

const WORKDIR = "/root/powerglide";
const MAX_TURNS: u32 = 12;
const RESULT_TRUNC: usize = 900;
const MAX_TOKENS: u32 = 512;
const TASK_COOLDOWN_MS: u64 = 3_000;
const RETRY_DELAY_MS: u64 = 5_000;
const MAX_RETRIES: u32 = 3;

// Optimal Qwen3.5 non-thinking (instruct) mode settings per Unsloth guide.
// For small models (0.8B/2B/4B): thinking is OFF by default.
// General-purpose coding tasks: temp=0.7, top_p=0.8, top_k=20, min_p=0.0
const TEMPERATURE: f64 = 0.7;
const TOP_P: f64 = 0.8;
const TOP_K: u32 = 20;
const MIN_P: f64 = 0.0;

const SEP_THIN = "──────────────────────────────────────────────────────────────";
const SEP_THICK = "══════════════════════════════════════════════════════════════";
const SEP_BLOCK = "██████████████████████████████████████████████████████████████";

const Endpoint = struct {
    name: []const u8,
    port: u16,
    model: []const u8,
};

const ENDPOINTS = [_]Endpoint{
    .{ .name = "0.8B-Q8",        .port = 8090, .model = "Qwen3.5-0.8B-Q8_0.gguf" },
    .{ .name = "4B-Q8",          .port = 8091, .model = "Qwen3.5-4B-Q8_0.gguf" },
    .{ .name = "2B-Q4",          .port = 8092, .model = "Qwen3.5-2B-UD-Q4_K_XL.gguf" },
    .{ .name = "0.5B-coder-Q8",  .port = 8093, .model = "qwen2.5-coder-0.5b-instruct-q8_0.gguf" },
};

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

// ── Tasks ─────────────────────────────────────────────────────────────────────

const Task = struct {
    name: []const u8,
    prompt: []const u8,
};

// Prompts are tuned based on observed failure modes from Python trial runs:
// T02: was failing because model used 'idle,' pattern and missed 10 variants.
//      Fix: use sed to extract the enum block first, then count.
// T08: was regressing to markdown after one tool call.
//      Fix: explicit "call done immediately after the grep result".
// T11: was hallucinating registry.zig.
//      Fix: read 3 known files in one combined head command.
// T13: same enum-count issue as T02.
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
        .name = "T12 Arithmetic: lines x2",
        .prompt =
        \\bash: wc -l src/agent/loop.zig
        \\bash: echo $((N * 2))   where N is the line count
        \\Report the result.
        ,
    },
    .{
        .name = "T13 Chain: count variants -> write",
        .prompt =
        \\bash: sed -n '/LoopState = enum/,/^};/p' src/agent/loop.zig | grep -cE '^\s+[a-z_]+,$'
        \\write: /tmp/loop_state_count.txt  content: <the integer you got>
        \\bash: cat /tmp/loop_state_count.txt
        ,
    },
};

// ── JSON request types (struct-based serialisation avoids ObjectMap bugs) ─────

const ReqFormat = struct { @"type": []const u8 };
const ReqMsg    = struct { role: []const u8, content: []const u8 };
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

// ── Message list ─────────────────────────────────────────────────────────────

/// A bounded list of messages with owned content strings.
const MsgList = struct {
    items: std.ArrayList(ReqMsg),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) MsgList {
        return .{
            .items = std.ArrayList(ReqMsg){},
            .allocator = allocator,
        };
    }

    fn deinit(self: *MsgList) void {
        for (self.items.items) |m| self.allocator.free(m.content);
        self.items.deinit(self.allocator);
    }

    fn append(self: *MsgList, role: []const u8, content: []const u8) !void {
        try self.items.append(self.allocator, .{
            .role = role,
            .content = try self.allocator.dupe(u8, content),
        });
    }

    fn slice(self: *const MsgList) []const ReqMsg {
        return self.items.items;
    }

};

// ── JSON utilities ────────────────────────────────────────────────────────────

/// Convert literal 2-char escape sequences (\n, \t, \r) to actual control chars.
/// igllama json_mode sometimes returns "\n" (backslash+n) instead of real newlines
/// between JSON tokens, which breaks parseFromSlice. Caller owns result.
fn unescapeControlChars(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\\' and i + 1 < s.len) {
            switch (s[i + 1]) {
                'n'  => { try out.append(allocator, '\n'); i += 1; continue; },
                't'  => { try out.append(allocator, '\t'); i += 1; continue; },
                'r'  => { try out.append(allocator, '\r'); i += 1; continue; },
                else => {},
            }
        }
        try out.append(allocator, s[i]);
    }
    return out.toOwnedSlice(allocator);
}

/// Try parsing s as JSON; on failure, unescape literal \n/\t/\r sequences and retry.
fn parseJsonValue(allocator: std.mem.Allocator, s: []const u8) !std.json.Parsed(std.json.Value) {
    if (std.json.parseFromSlice(std.json.Value, allocator, s, .{})) |p| return p else |_| {}
    const unesc = try unescapeControlChars(allocator, s);
    defer allocator.free(unesc);
    return std.json.parseFromSlice(std.json.Value, allocator, unesc, .{});
}

// ── JSON extraction ───────────────────────────────────────────────────────────

/// Find and return the first brace-balanced JSON object in `text`.
/// Caller owns the returned slice.
/// Fallback: if brace counting fails (0.8B double-escape bug), strip \" and retry.
fn extractJson(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    const start = std.mem.indexOfScalar(u8, text, '{') orelse return error.NoJson;
    if (tryExtract(allocator, text, start)) |s| return s;
    // Fallback: strip \" -> " and retry (0.8B outputs "args\":{ escaped keys)
    var fixed = std.ArrayList(u8){};
    defer fixed.deinit(allocator);
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (i + 1 < text.len and text[i] == '\\' and text[i + 1] == '"') {
            try fixed.append(allocator, '"');
            i += 1;
        } else {
            try fixed.append(allocator, text[i]);
        }
    }
    const new_start = std.mem.indexOfScalar(u8, fixed.items, '{') orelse return error.NoJson;
    return tryExtract(allocator, fixed.items, new_start) orelse error.UnmatchedBraces;
}

fn tryExtract(allocator: std.mem.Allocator, text: []const u8, start: usize) ?[]u8 {
    var depth: i32 = 0;
    var in_str = false;
    var esc = false;
    for (text[start..], start..) |ch, i| {
        if (esc)  { esc = false; continue; }
        if (ch == '\\' and in_str) { esc = true; continue; }
        if (ch == '"') { in_str = !in_str; continue; }
        if (in_str) continue;
        if (ch == '{') depth += 1;
        if (ch == '}') {
            depth -= 1;
            if (depth == 0) {
                return allocator.dupe(u8, text[start .. i + 1]) catch null;
            }
        }
    }
    return null;
}

// ── HTTP call ─────────────────────────────────────────────────────────────────

/// Send a chat request. Returns owned content string (caller frees).
fn callModel(
    allocator: std.mem.Allocator,
    port: u16,
    model: []const u8,
    messages: []const ReqMsg,
) ![]u8 {
    const req = Request{
        .model = model,
        .max_tokens = MAX_TOKENS,
        .temperature = TEMPERATURE,
        .top_p = TOP_P,
        .top_k = TOP_K,
        .min_p = MIN_P,
        .stream = false,
        .response_format = .{ .@"type" = "json_object" },
        .messages = messages,
    };

    var body_buf = std.ArrayList(u8){};
    defer body_buf.deinit(allocator);
    try body_buf.writer(allocator).print("{f}", .{std.json.fmt(req, .{})});
    const body = try body_buf.toOwnedSlice(allocator);
    defer allocator.free(body);

    const url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/v1/chat/completions", .{port});
    defer allocator.free(url);

    const headers = [_]std.http.Header{
        .{ .name = "content-type", .value = "application/json" },
    };

    var client = http_mod.HttpClient.init(allocator);
    defer client.deinit();

    var resp = try client.post(url, &headers, body);
    defer resp.deinit(allocator);

    if (!resp.isSuccess()) return error.HttpError;

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, resp.body, .{});
    defer parsed.deinit();

    const choices = parsed.value.object.get("choices") orelse return error.NoChoices;
    if (choices.array.items.len == 0) return error.EmptyChoices;
    const msg_obj = choices.array.items[0].object.get("message") orelse return error.NoMessage;
    const content_val = msg_obj.object.get("content") orelse return error.NoContent;
    const content = switch (content_val) {
        .string => |s| s,
        .null   => return error.NullContent,
        else    => return error.BadContent,
    };
    return allocator.dupe(u8, content);
}

fn callModelRetry(
    allocator: std.mem.Allocator,
    port: u16,
    model: []const u8,
    messages: []const ReqMsg,
    w: anytype,
) ![]u8 {
    var attempt: u32 = 0;
    while (attempt < MAX_RETRIES) : (attempt += 1) {
        const result = callModel(allocator, port, model, messages);
        if (result) |r| return r else |err| {
            if (attempt + 1 < MAX_RETRIES) {
                try w.print("(err={s}, retry {d})... ", .{ @errorName(err), attempt + 1 });
                std.Thread.sleep(RETRY_DELAY_MS * std.time.ns_per_ms);
            } else return err;
        }
    }
    return error.MaxRetries;
}

// ── Tool execution ────────────────────────────────────────────────────────────

fn runBash(allocator: std.mem.Allocator, command: []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "/bin/sh", "-c", command },
        .cwd = WORKDIR,
        .max_output_bytes = 1024 * 1024,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const raw = if (result.stdout.len > 0) result.stdout else result.stderr;
    const trimmed = std.mem.trimRight(u8, raw, " \n\r");
    const rc: u8 = switch (result.term) {
        .Exited => |c| c,
        else    => 1,
    };
    const full = if (rc != 0)
        try std.fmt.allocPrint(allocator, "{s}\n[exit {d}]", .{ trimmed, rc })
    else
        try allocator.dupe(u8, trimmed);
    if (full.len <= RESULT_TRUNC) return full;
    const trunc = try allocator.dupe(u8, full[0..RESULT_TRUNC]);
    allocator.free(full);
    return trunc;
}

fn runRead(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const abs = if (std.mem.startsWith(u8, path, "/"))
        try allocator.dupe(u8, path)
    else
        try std.fs.path.join(allocator, &.{ WORKDIR, path });
    defer allocator.free(abs);

    const file = std.fs.openFileAbsolute(abs, .{}) catch |e|
        return std.fmt.allocPrint(allocator, "ERROR opening {s}: {}", .{ abs, e });
    defer file.close();

    const data = file.readToEndAlloc(allocator, 1024 * 1024) catch |e|
        return std.fmt.allocPrint(allocator, "ERROR reading {s}: {}", .{ abs, e });
    defer allocator.free(data);

    if (data.len <= RESULT_TRUNC) return allocator.dupe(u8, data);
    return allocator.dupe(u8, data[0..RESULT_TRUNC]);
}

fn runWrite(allocator: std.mem.Allocator, path: []const u8, content: []const u8) ![]u8 {
    const abs = if (std.mem.startsWith(u8, path, "/"))
        try allocator.dupe(u8, path)
    else
        try std.fs.path.join(allocator, &.{ WORKDIR, path });
    defer allocator.free(abs);

    if (std.fs.path.dirname(abs)) |dir|
        std.fs.makeDirAbsolute(dir) catch {};

    const file = try std.fs.createFileAbsolute(abs, .{});
    defer file.close();
    try file.writeAll(content);
    return std.fmt.allocPrint(allocator, "OK: {d} bytes -> {s}", .{ content.len, abs });
}

fn dispatch(allocator: std.mem.Allocator, tool: []const u8, args: std.json.Value) ![]u8 {
    const getString = struct {
        fn f(v: std.json.Value, k: []const u8) ?[]const u8 {
            if (v != .object) return null;
            const val = v.object.get(k) orelse return null;
            return if (val == .string) val.string else null;
        }
    }.f;
    if (std.mem.eql(u8, tool, "bash")) {
        const cmd = getString(args, "command") orelse return allocator.dupe(u8, "(missing command)");
        return runBash(allocator, cmd) catch |e| std.fmt.allocPrint(allocator, "ERROR: {}", .{e});
    }
    if (std.mem.eql(u8, tool, "read")) {
        const path = getString(args, "path") orelse return allocator.dupe(u8, "(missing path)");
        return runRead(allocator, path) catch |e| std.fmt.allocPrint(allocator, "ERROR: {}", .{e});
    }
    if (std.mem.eql(u8, tool, "write")) {
        const path    = getString(args, "path")    orelse return allocator.dupe(u8, "(missing path)");
        const content = getString(args, "content") orelse return allocator.dupe(u8, "(missing content)");
        return runWrite(allocator, path, content) catch |e| std.fmt.allocPrint(allocator, "ERROR: {}", .{e});
    }
    return allocator.dupe(u8, "unknown tool");
}

// ── Task runner ───────────────────────────────────────────────────────────────

const TaskResult = struct {
    success: bool,
    turns: u32,
    elapsed_ms: i64,
    answer: ?[]u8, // owned

    fn deinit(self: *TaskResult, allocator: std.mem.Allocator) void {
        if (self.answer) |a| allocator.free(a);
    }
};

fn runTask(
    allocator: std.mem.Allocator,
    ep: Endpoint,
    task: Task,
    w: anytype,
) !TaskResult {
    const t_start = std.time.milliTimestamp();
    var msgs = MsgList.init(allocator);
    defer msgs.deinit();
    try msgs.append("system", SYSTEM_PROMPT);
    try msgs.append("user", task.prompt);

    var json_errs: u32 = 0;
    var turn: u32 = 0;
    while (turn < MAX_TURNS) : (turn += 1) {
        try w.print("  [t{d}] ", .{turn + 1});
        const tc = std.time.milliTimestamp();
        const raw = callModelRetry(allocator, ep.port, ep.model, msgs.slice(), w) catch |err| {
            try w.print("CALL_ERR({s})\n", .{@errorName(err)});
            break;
        };
        defer allocator.free(raw);
        const call_s = @as(f64, @floatFromInt(std.time.milliTimestamp() - tc)) / 1000.0;
        try w.print("{d:.1}s -> ", .{call_s});

        // Extract JSON
        const json_slice = extractJson(allocator, raw) catch {
            json_errs += 1;
            try w.print("JSON_ERR: {s}\n", .{raw[0..@min(60, raw.len)]});
            if (json_errs >= 2) break;
            try msgs.append("assistant", raw);
            try msgs.append("user", "Output ONLY one JSON object, no markdown, no extra text.");
            continue;
        };
        defer allocator.free(json_slice);
        json_errs = 0;

        // Parse JSON; fallback: unescape literal "\n" sequences first
        // (igllama json_mode sometimes emits literal "\n" between tokens).
        var parsed = parseJsonValue(allocator, json_slice) catch {
            json_errs += 1;
            try w.print("PARSE_ERR: {s}\n", .{json_slice[0..@min(60, json_slice.len)]});
            if (json_errs >= 2) break;
            try msgs.append("assistant", raw);
            try msgs.append("user", "Output ONLY one JSON object, no markdown, no extra text.");
            continue;
        };
        defer parsed.deinit();
        json_errs = 0;

        const root = parsed.value;
        const tool = blk: {
            if (root != .object) break :blk "";
            const v = root.object.get("tool") orelse break :blk "";
            break :blk if (v == .string) v.string else "";
        };
        // Fallback: some models put args at top level instead of nested in "args"
        const args = blk: {
            if (root != .object) break :blk std.json.Value{ .null = {} };
            break :blk root.object.get("args") orelse root;
        };

        // Log action
        var args_buf = std.ArrayList(u8){};
        defer args_buf.deinit(allocator);
        try args_buf.writer(allocator).print("{f}", .{std.json.fmt(args, .{ .whitespace = .minified })});
        const args_str = try args_buf.toOwnedSlice(allocator);
        defer allocator.free(args_str);
        try w.print("{s}({s})\n", .{ tool, args_str[0..@min(80, args_str.len)] });

        if (std.mem.eql(u8, tool, "done")) {
            const answer_s = blk: {
                if (args != .object) break :blk "";
                const v = args.object.get("answer") orelse break :blk "";
                break :blk if (v == .string) v.string else "";
            };
            try w.print("  OK: {s}\n", .{answer_s[0..@min(100, answer_s.len)]});
            return .{
                .success = true,
                .turns   = turn + 1,
                .elapsed_ms = std.time.milliTimestamp() - t_start,
                .answer  = try allocator.dupe(u8, answer_s),
            };
        }

        const result = try dispatch(allocator, tool, args);
        defer allocator.free(result);
        try w.print("      <- {s}\n", .{result[0..@min(140, result.len)]});

        try msgs.append("assistant", raw);
        // If tool was unrecognised, give a targeted correction instead of
        // feeding back "unknown tool" (which causes the 2B to escape-loop).
        const cont = if (std.mem.eql(u8, result, "unknown tool"))
            try allocator.dupe(u8,
                \\You must output a JSON tool call. Use one of:
                \\{"tool":"bash","args":{"command":"<cmd>"}}
                \\{"tool":"done","args":{"answer":"<answer>"}}
                \\Output ONLY the JSON object, nothing else.
            )
        else
            try std.fmt.allocPrint(allocator, "Result:\n{s}\n\nContinue.", .{result});
        defer allocator.free(cont);
        try msgs.append("user", cont);

        // Cap context: keep system+initial + last 4 pairs
        if (msgs.items.items.len > 2 + 8) {
            // Manual trim to keep first 2 + last 8 items
            const keep_front: usize = 2;
            const keep_back: usize  = 8;
            const total = msgs.items.items.len;
            if (total > keep_front + keep_back) {
                const drop_start = keep_front;
                const drop_end   = total - keep_back;
                for (msgs.items.items[drop_start..drop_end]) |m|
                    allocator.free(m.content);
                const tail = msgs.items.items[drop_end..];
                for (0..tail.len) |i|
                    msgs.items.items[drop_start + i] = tail[i];
                msgs.items.shrinkRetainingCapacity(drop_start + tail.len);
            }
        }
    }

    return .{
        .success    = false,
        .turns      = turn,
        .elapsed_ms = std.time.milliTimestamp() - t_start,
        .answer     = null,
    };
}

// ── Health check ─────────────────────────────────────────────────────────────

fn checkHealth(allocator: std.mem.Allocator, port: u16) bool {
    var client = http_mod.HttpClient.init(allocator);
    defer client.deinit();
    const url = std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/health", .{port}) catch return false;
    defer allocator.free(url);
    var resp = client.get(url, &.{}) catch return false;
    defer resp.deinit(allocator);
    return resp.isSuccess() and std.mem.indexOf(u8, resp.body, "ok") != null;
}

// ── Main ─────────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const w = std.fs.File.stdout().deprecatedWriter();

    try w.writeAll("\npowerglide x igllama — Zig trial harness\n");
    try w.print("Tasks: T01-T{d}   temp={d:.1} top_p={d:.1} top_k={d}\n\n",
        .{ TASKS.len, TEMPERATURE, TOP_P, TOP_K });

    // results[endpoint_idx][task_idx]
    var results: [ENDPOINTS.len][TASKS.len]?TaskResult = .{.{null} ** TASKS.len} ** ENDPOINTS.len;
    defer {
        for (&results) |*row| for (row) |*mr| if (mr.*) |*r| r.deinit(allocator);
    }

    for (ENDPOINTS, 0..) |ep, ei| {
        try w.print("\n{s}\n", .{SEP_BLOCK});
        try w.print("  MODEL: {s}  (:{d})  model={s}\n", .{ ep.name, ep.port, ep.model });
        try w.print("{s}\n", .{SEP_BLOCK});

        if (!checkHealth(allocator, ep.port)) {
            try w.writeAll("  Health: FAILED -- skipping\n");
            continue;
        }
        try w.writeAll("  Health: OK\n");

        for (TASKS, 0..) |task, ti| {
            try w.print("\n{s}\n  {s}\n{s}\n", .{ SEP_THIN, task.name, SEP_THIN });
            std.Thread.sleep(TASK_COOLDOWN_MS * std.time.ns_per_ms);

            const r = runTask(allocator, ep, task, w) catch |err| blk: {
                try w.print("  TASK_ERR: {s}\n", .{@errorName(err)});
                break :blk TaskResult{ .success = false, .turns = 0, .elapsed_ms = 0, .answer = null };
            };
            results[ei][ti] = r;
        }
    }

    // ── Summary ───────────────────────────────────────────────────────────────
    try w.print("\n\n{s}\n", .{SEP_THICK});
    try w.writeAll("  RESULTS -- powerglide x igllama Zig trial\n");
    try w.print("{s}\n", .{SEP_THICK});

    for (ENDPOINTS, 0..) |ep, ei| {
        if (results[ei][0] == null) {
            try w.print("\n  {s}: SKIPPED\n", .{ep.name});
            continue;
        }
        var passed: u32 = 0;
        var total_turns: u32 = 0;
        var total_ms: i64 = 0;
        for (results[ei]) |mr| if (mr) |r| {
            if (r.success) passed += 1;
            total_turns += r.turns;
            total_ms += r.elapsed_ms;
        };
        try w.print("\n  {s}: {d}/{d} passed  {d} turns  {d:.0}s\n",
            .{ ep.name, passed, TASKS.len, total_turns,
               @as(f64, @floatFromInt(total_ms)) / 1000.0 });
        for (TASKS, 0..) |task, ti| {
            if (results[ei][ti]) |r| {
                const sym: []const u8 = if (r.success) "+" else "-";
                try w.print("    {s}  {d:2}t  {d:5.1}s  {s}\n", .{
                    sym, r.turns,
                    @as(f64, @floatFromInt(r.elapsed_ms)) / 1000.0,
                    task.name,
                });
                if (r.answer) |a| if (a.len > 0)
                    try w.print("         -> {s}\n", .{a[0..@min(80, a.len)]});
            }
        }
    }
    try w.writeAll("\n");
}
