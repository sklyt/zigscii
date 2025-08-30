// https://chatgpt.com/c/68b2e0e2-5f40-832c-800c-54c3668642dd firefox
// C-compatible structures
const CPosition = extern struct {
    x: f64,
    y: f64,

    pub fn distance(self: CPosition, other: CPosition) f64 {
        const dx = self.x - other.x;
        const dy = self.y - other.y;
        return sqrt(dx * dx + dy * dy);
    }

    pub fn angle(self: CPosition, other: CPosition) f64 {
        return atan2(other.y - self.y, other.x - self.x);
    }
};

// Wrapper for C string operations with Zig safety
const CString = struct {
    const Self = @This();

    ptr: [*:0]u8,
    len: usize,
    owned: bool,

    pub fn fromSlice(allocator: std.mem.Allocator, slice: []const u8) !Self {
        const c_str = try allocator.allocSentinel(u8, slice.len, 0);
        @memcpy(c_str[0..slice.len], slice);

        return Self{
            .ptr = c_str.ptr,
            .len = slice.len,
            .owned = true,
        };
    }

    pub fn fromCString(c_str: [*:0]const u8) Self {
        return Self{
            .ptr = @constCast(c_str),
            .len = strlen(c_str),
            .owned = false,
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        if (self.owned) {
            allocator.free(self.ptr[0 .. self.len + 1]);
        }
    }

    pub fn toSlice(self: Self) []const u8 {
        return self.ptr[0..self.len];
    }

    pub fn equals(self: Self, other: Self) bool {
        return strcmp(self.ptr, other.ptr) == 0;
    }
};

// High-performance timer using C functions
const HighResTimer = struct {
    const Self = @This();

    start_time: std.os.timespec,

    pub fn start() Self {
        var timer = Self{
            .start_time = undefined,
        };

        // Use platform-specific high-resolution timer
        if (builtin.os.tag == .linux) {
            _ = linux.clock_gettime(linux.CLOCK.MONOTONIC, &timer.start_time);
        } else {
            // Fallback to standard time
            timer.start_time = std.os.timespec{
                .tv_sec = std.time.timestamp(),
                .tv_nsec = 0,
            };
        }

        return timer;
    }

    pub fn elapsedNanos(self: Self) u64 {
        var current_time: std.os.timespec = undefined;

        if (builtin.os.tag == .linux) {
            _ = linux.clock_gettime(linux.CLOCK.MONOTONIC, &current_time);
        } else {
            current_time = std.os.timespec{
                .tv_sec = std.time.timestamp(),
                .tv_nsec = 0,
            };
        }

        const sec_diff = @as(u64, @intCast(current_time.tv_sec - self.start_time.tv_sec));
        const nsec_diff = @as(i64, current_time.tv_nsec - self.start_time.tv_nsec);

        return sec_diff * 1_000_000_000 + @as(u64, @intCast(nsec_diff));
    }

    pub fn elapsedMillis(self: Self) f64 {
        return @as(f64, @floatFromInt(self.elapsedNanos())) / 1_000_000.0;
    }
};

// Game math utilities using C math functions
const GameMath = struct {
    const PI = 3.14159265358979323846;

    pub fn lerp(a: f64, b: f64, t: f64) f64 {
        return a + t * (b - a);
    }

    pub fn smoothstep(edge0: f64, edge1: f64, x: f64) f64 {
        const t = std.math.clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
        return t * t * (3.0 - 2.0 * t);
    }

    pub fn wrapAngle(angle: f64) f64 {
        var result = angle;
        while (result > PI) result -= 2.0 * PI;
        while (result < -PI) result += 2.0 * PI;
        return result;
    }

    pub fn vectorLength(x: f64, y: f64) f64 {
        return sqrt(x * x + y * y);
    }

    pub fn normalize(x: *f64, y: *f64) void {
        const len = vectorLength(x.*, y.*);
        if (len > 0.0) {
            x.* /= len;
            y.* /= len;
        }
    }

    // Perlin noise using C math functions (simplified version)
    pub fn noise2D(x: f64, y: f64) f64 {
        // Simplified noise - in real games you'd use a proper noise library
        const sin_x = sin(x * 12.9898);
        const sin_y = sin(y * 78.233);
        const dot = sin_x * sin_y;
        const fract = dot * 43758.5453 - @floor(dot * 43758.5453);
        return fract * 2.0 - 1.0; // Map to [-1, 1]
    }
};

// Memory-mapped file for fast level loading (C-style approach)
const MemoryMappedFile = struct {
    const Self = @This();

    data: []u8,
    size: usize,

    pub fn open(path: [*:0]const u8) !Self {
        const file = std.fs.cwd().openFileZ(path, .{}) catch return error.FileNotFound;
        defer file.close();

        const size = try file.getEndPos();
        const data = try std.os.mmap(
            null,
            size,
            std.os.PROT.READ,
            std.os.MAP.PRIVATE,
            file.handle,
            0,
        );

        return Self{
            .data = data,
            .size = size,
        };
    }

    pub fn close(self: Self) void {
        std.os.munmap(self.data);
    }

    pub fn readU32(self: Self, offset: usize) ?u32 {
        if (offset + 4 > self.size) return null;
        return std.mem.readIntLittle(u32, self.data[offset .. offset + 4]);
    }

    pub fn readString(self: Self, offset: usize, len: usize) ?[]const u8 {
        if (offset + len > self.size) return null;
        return self.data[offset .. offset + len];
    }
};

// Performance profiler using C timing
const Profiler = struct {
    const Self = @This();
    const MAX_SAMPLES = 1000;

    samples: [MAX_SAMPLES]f64,
    sample_count: usize,
    timer: HighResTimer,

    pub fn init() Self {
        return Self{
            .samples = std.mem.zeroes([MAX_SAMPLES]f64),
            .sample_count = 0,
            .timer = undefined,
        };
    }

    pub fn startFrame(self: *Self) void {
        self.timer = HighResTimer.start();
    }

    pub fn endFrame(self: *Self) void {
        const elapsed = self.timer.elapsedMillis();

        if (self.sample_count < MAX_SAMPLES) {
            self.samples[self.sample_count] = elapsed;
            self.sample_count += 1;
        } else {
            // Circular buffer
            const index = self.sample_count % MAX_SAMPLES;
            self.samples[index] = elapsed;
            self.sample_count += 1;
        }
    }

    pub fn getAverageFrameTime(self: Self) f64 {
        if (self.sample_count == 0) return 0.0;

        var sum: f64 = 0.0;
        const count = @min(self.sample_count, MAX_SAMPLES);

        for (0..count) |i| {
            sum += self.samples[i];
        }

        return sum / @as(f64, @floatFromInt(count));
    }

    pub fn getFPS(self: Self) f64 {
        const avg_frame_time = self.getAverageFrameTime();
        if (avg_frame_time > 0.0) {
            return 1000.0 / avg_frame_time;
        }
        return 0.0;
    }
};

pub fn demoCInterop() !void {
    print("=== C Interop & System Integration Demo ===\n\n");

    // 1. C Math Functions
    print("1. C Math Integration:\n");

    var pos1 = CPosition{ .x = 0.0, .y = 0.0 };
    var pos2 = CPosition{ .x = 3.0, .y = 4.0 };

    const distance = pos1.distance(pos2);
    const angle = pos1.angle(pos2);

    print("Distance between ({d:.1}, {d:.1}) and ({d:.1}, {d:.1}): {d:.2}\n", .{ pos1.x, pos1.y, pos2.x, pos2.y, distance });
    print("Angle: {d:.2} radians ({d:.1} degrees)\n", .{ angle, angle * 180.0 / GameMath.PI });

    // 2. String Interop
    print("\n2. C String Integration:\n");

    const zig_string = "Hello from Zig!";
    var c_string = try CString.fromSlice(std.heap.page_allocator, zig_string);
    defer c_string.deinit(std.heap.page_allocator);

    print("Original: {s}\n", .{zig_string});
    print("C string length: {}\n", .{c_string.len});
    print("Back to slice: {s}\n", .{c_string.toSlice()});

    // 3. High-Resolution Timing
    print("\n3. High-Resolution Timing:\n");

    var profiler = Profiler.init();

    // Simulate some game frames
    for (0..10) |frame| {
        profiler.startFrame();

        // Simulate work
        var sum: f64 = 0.0;
        for (0..100000) |i| {
            sum += sin(@as(f64, @floatFromInt(i)) / 1000.0);
        }

        profiler.endFrame();

        if (frame % 3 == 0) {
            print("Frame {}: {d:.2}ms (FPS: {d:.1})\n", .{ frame, profiler.timer.elapsedMillis(), profiler.getFPS() });
        }

        _ = sum; // Prevent optimization
    }

    print("Average frame time: {d:.2}ms\n", .{profiler.getAverageFrameTime()});
    print("Average FPS: {d:.1}\n", .{profiler.getFPS()});

    // 4. Game Math with C Functions
    print("\n4. Game Math:\n");

    // Movement vector
    var move_x: f64 = 5.0;
    var move_y: f64 = 12.0;
    const original_length = GameMath.vectorLength(move_x, move_y);

    print("Original vector: ({d:.2}, {d:.2}), length: {d:.2}\n", .{ move_x, move_y, original_length });

    GameMath.normalize(&move_x, &move_y);
    print("Normalized: ({d:.2}, {d:.2}), length: {d:.2}\n", .{ move_x, move_y, GameMath.vectorLength(move_x, move_y) });

    // Noise generation
    print("Noise samples: ");
    for (0..5) |i| {
        const x = @as(f64, @floatFromInt(i)) * 0.1;
        const y = 0.0;
        const noise = GameMath.noise2D(x, y);
        print("{d:.2} ", .{noise});
    }
    print("\n");

    // 5. Performance Considerations
    print("\n5. Performance Analysis:\n");

    // Compare Zig vs C math performance
    const iterations = 1000000;

    var timer = HighResTimer.start();
    var zig_result: f64 = 0.0;
    for (0..iterations) |i| {
        const val = @as(f64, @floatFromInt(i)) / 1000.0;
        zig_result += @sin(val); // Zig's built-in sin
    }
    const zig_time = timer.elapsedMillis();

    timer = HighResTimer.start();
    var c_result: f64 = 0.0;
    for (0..iterations) |i| {
        const val = @as(f64, @floatFromInt(i)) / 1000.0;
        c_result += sin(val); // C's sin function
    }
    const c_time = timer.elapsedMillis();

    print("Sin performance test ({} iterations):\n", .{iterations});
    print("Zig built-in: {d:.2}ms, result: {d:.6}\n", .{ zig_time, zig_result });
    print("C library:    {d:.2}ms, result: {d:.6}\n", .{ c_time, c_result });
    print("Difference:   {d:.2}ms ({d:.1}% ", .{ @abs(zig_time - c_time), @abs(zig_time - c_time) / @min(zig_time, c_time) * 100.0 });

    if (zig_time < c_time) {
        print("faster with Zig)\n");
    } else {
        print("faster with C)\n");
    }

    print("\n=== C Interop Best Practices ===\n");
    print("• Use 'extern' for C function declarations\n");
    print("• 'extern struct' ensures C-compatible memory layout\n");
    print("• Wrap C strings in safe Zig types\n");
    print("• Use Zig's error handling even with C functions\n");
    print("• Profile both C and Zig implementations\n");
    print("• Memory-map files for high-performance I/O\n");
    print("• Prefer Zig's built-ins when performance is similar\n");
}

const std = @import("std");
const builtin = @import("builtin");
const c = std.c;

// Import C standard library functions
extern "c" fn malloc(size: c_ulong) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn memset(ptr: ?*anyopaque, value: c_int, size: c_ulong) ?*anyopaque;
extern "c" fn strlen(str: [*:0]const u8) c_ulong;
extern "c" fn strcmp(str1: [*:0]const u8, str2: [*:0]const u8) c_int;

// Math functions for game calculations
extern "c" fn sin(x: f64) f64;
extern "c" fn cos(x: f64) f64;
extern "c" fn sqrt(x: f64) f64;
extern "c" fn atan2(y: f64, x: f64) f64;

// System-specific functions for high-resolution timing
const linux = std.os.linux;

const d_print = std.debug.print;

fn print(s: []const u8) void {
    d_print("{s}", .{s});
}
