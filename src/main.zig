// ANSI escape sequences are special character codes that control terminal behavior.
//They all start with the ESC character (ASCII 27) followed by [ and then command codes.

const d_print = std.debug.print;

fn print(s: []const u8) void {
    d_print("{s}", .{s});
}

fn enableUtf8() void {
    if (builtin.target.os.tag == .windows) {
        // Use Win32 calls to switch console to UTF-8 and enable VT processing

        // Set input/output code page to UTF-8
        // UINT SetConsoleOutputCP(UINT wCodePageID);
        _ = c.SetConsoleOutputCP(65001);
        _ = c.SetConsoleCP(65001);

        // Try to enable virtual terminal processing so ANSI escapes work reliably
        const hOut = c.GetStdHandle(c.STD_OUTPUT_HANDLE);
        var mode: u32 = 0;
        if (c.GetConsoleMode(hOut, &mode) != 0) {
            const ENABLE_VIRTUAL_TERMINAL_PROCESSING: u32 = 0x0004;
            _ = c.SetConsoleMode(hOut, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
        }
    } else {
        // Ask libc to use the environment locale (so printf/term use UTF-8)
        const c2 = @cImport({
            @cInclude("locale.h");
        });
        // setlocale returns a C string, ignore return here
        _ = c2.setlocale(c2.LC_ALL, "");
    }
}

const ESC = "\x1B";
const CSI = ESC ++ "[";

// Cursor movement
const CURSOR_HOME = CSI ++ "H";
const CURSOR_UP = CSI ++ "A";
const CURSOR_DOWN = CSI ++ "B";
const CURSOR_RIGHT = CSI ++ "C";
const CURSOR_LEFT = CSI ++ "D";

// Screen control
const CLEAR_SCREEN = CSI ++ "2J";
const CLEAR_LINE = CSI ++ "2K";
const HIDE_CURSOR = CSI ++ "?25l";
const SHOW_CURSOR = CSI ++ "?25h";

// Colors (4-bit standard colors)
const RESET = CSI ++ "0m";
const RED = CSI ++ "31m";
const GREEN = CSI ++ "32m";
const YELLOW = CSI ++ "33m";
const BLUE = CSI ++ "34m";
const MAGENTA = CSI ++ "35m";
const CYAN = CSI ++ "36m";
const WHITE = CSI ++ "37m";

// Background colors
const BG_RED = CSI ++ "41m";
const BG_GREEN = CSI ++ "42m";
const BG_BLUE = CSI ++ "44m";

const os = std.os;

const TerminalMode = struct {
    const Self = @This();
    // In Zig, termios refers to the functionality for controlling terminal interface attributes, similar to the termios API found in C and POSIX systems. This is crucial for low-level terminal manipulation, such as setting raw mode for reading individual key presses without requiring an Enter key press, or controlling input/output buffering and echoing.

    original_termios: if (builtin.os.tag == .linux or builtin.os.tag == .macos) std.posix.termios else void,

    win_in_handle: if (builtin.os.tag == .windows) c.HANDLE else void,
    win_orig_in_mode: if (builtin.os.tag == .windows) c.DWORD else void,
    win_out_handle: if (builtin.os.tag == .windows) c.HANDLE else void,
    win_orig_out_mode: if (builtin.os.tag == .windows) c.DWORD else void,

    pub fn Init() !Self {
        var mode = Self{
            .original_termios = undefined,
            .win_in_handle = undefined,
            .win_orig_in_mode = undefined,
            .win_out_handle = undefined,
            .win_orig_out_mode = undefined,
        };
        if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
            // Get current terminal attributes
            mode.original_termios = try os.tcgetattr(std.os.STDIN_FILENO);

            // Create new attributes for raw mode
            var raw = mode.original_termios;

            // Disable canonical mode (line buffering)
            raw.lflag &= ~@as(u32, os.system.ICANON);
            // Disable echo
            raw.lflag &= ~@as(u32, os.system.ECHO);
            // Disable Ctrl+C and Ctrl+Z signals
            raw.lflag &= ~@as(u32, os.system.ISIG);
            // Disable processing of input characters
            raw.iflag &= ~@as(u32, os.system.IXON);
            raw.iflag &= ~@as(u32, os.system.ICRNL);
            // Disable output processing
            raw.oflag &= ~@as(u32, os.system.OPOST);

            // Set minimum number of characters for non-canonical read
            raw.cc[os.system.VMIN] = 0; // Don't wait for characters
            raw.cc[os.system.VTIME] = 1; // Wait 100ms max

            // Apply new attributes
            try os.tcsetattr(std.os.STDIN_FILENO, os.system.TCSA.FLUSH, raw);
        } else if (builtin.os.tag == .windows) {

            // Windows console handling via Win32 API
            const hIn = c.GetStdHandle(c.STD_INPUT_HANDLE);
            const hOut = c.GetStdHandle(c.STD_OUTPUT_HANDLE);

            if (hIn == c.INVALID_HANDLE_VALUE or hOut == c.INVALID_HANDLE_VALUE) {
                return error.InvalidStdHandle;
            }

            var inMode: c.DWORD = 0;
            if (c.GetConsoleMode(hIn, &inMode) == 0) {
                return error.GetConsoleModeFailed;
            }

            // Save original input mode
            mode.win_in_handle = hIn;
            mode.win_orig_in_mode = inMode;

            // turn off line input, echo, processed input (Ctrl-C handling)
            // boolean or:src\main.zig:133:65: error: expected type 'bool', found 'c_int'
            //             const newInMode: c.DWORD = inMode & ~(@as(c.DWORD, c.ENABLE_LINE_INPUT or c.ENABLE_ECHO_INPUT or c.ENABLE_PROCESSED_INPUT));
            //                                                                ~^~~~~~~~~~~~~~~~~~
            // referenced by:
            //     main: src\main.zig:223:46
            //     main: C:\ProgramData\chocolatey\lib\zig\tools\zig-windows-x86_64-0.14.0\lib\std\start.zig:656:37
            //     3 reference(s) hidden; use '-freference-trace=5' to see all references

            // bitwise or |
            const newInMode: c.DWORD = inMode & ~(@as(c.DWORD, c.ENABLE_LINE_INPUT | c.ENABLE_ECHO_INPUT | c.ENABLE_PROCESSED_INPUT));
            if (c.SetConsoleMode(hIn, newInMode) == 0) {
                return error.SetConsoleModeFailed;
            }

            // Output: enable virtual terminal processing so ANSI escapes work
            var outMode: c.DWORD = 0;
            if (c.GetConsoleMode(hOut, &outMode) == 0) {
                // Try to restore input on failure before returning
                _ = c.SetConsoleMode(hIn, mode.win_orig_in_mode);
                return error.GetConsoleModeFailed;
            }
            mode.win_out_handle = hOut;
            mode.win_orig_out_mode = outMode;

            const vt_flag: c.DWORD = @as(c.DWORD, c.ENABLE_VIRTUAL_TERMINAL_PROCESSING);
            if ((outMode & vt_flag) == 0) {
                if (c.SetConsoleMode(hOut, outMode | vt_flag) == 0) {
                    // restore input before failing
                    _ = c.SetConsoleMode(hIn, mode.win_orig_in_mode);
                    return error.SetConsoleModeFailed;
                }
            }

            return mode;
        }
        // default for other oses
        return mode;
    }

    pub fn deinit(self: *Self) void {
        if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
            // Restore original terminal settings
            os.tcsetattr(std.os.STDIN_FILENO, os.system.TCSA.FLUSH, self.original_termios) catch {};
        } else if (builtin.os.tag == .windows) {
            // Restore windows console modes (best-effort)
            if (self.win_in_handle != c.INVALID_HANDLE_VALUE) {
                _ = c.SetConsoleMode(self.win_in_handle, self.win_orig_in_mode);
            }
            if (self.win_out_handle != c.INVALID_HANDLE_VALUE) {
                _ = c.SetConsoleMode(self.win_out_handle, self.win_orig_out_mode);
            }
        }
    }
};

// key definitions

const Key = enum {
    Unknown,
    Escape,
    Enter,
    Space,
    Backspace,
    Tab,
    ArrowUp,
    ArrowDown,
    ArrowLeft,
    ArrowRight,
    Character,

    pub fn fromByte(byte: u8) Key {
        return switch (byte) {
            27 => .Escape,
            13, 10 => .Enter,
            32 => .Space,
            127, 8 => .Backspace,
            9 => .Tab,
            else => if (byte >= 32 and byte <= 126) .Character else .Unknown,
        };
    }
};

// input

const InputReader = struct {
    const Self = @This();

    pub fn readKey() !?struct { key: Key, char: u8 } {
        // const stdout = std.io.getStdOut().writer();
        const stdin = std.io.getStdIn().reader();
        var buffer: [8]u8 = undefined;

        const bytes_read = stdin.read(&buffer) catch |err| switch (err) {
            error.WouldBlock => return null, // No input available
            else => return err,
        };

        if (bytes_read == 0) return null;

        const first_byte = buffer[0];

        // Handle escape sequences (arrow keys, function keys, etc.)
        if (first_byte == 27 and bytes_read > 1) {
            if (buffer[1] == '[' and bytes_read >= 3) {
                return switch (buffer[2]) {
                    'A' => .{ .key = .ArrowUp, .char = 0 },
                    'B' => .{ .key = .ArrowDown, .char = 0 },
                    'C' => .{ .key = .ArrowRight, .char = 0 },
                    'D' => .{ .key = .ArrowLeft, .char = 0 },
                    else => .{ .key = .Unknown, .char = 0 },
                };
            }
            return .{ .key = .Escape, .char = first_byte };
        }

        return .{ .key = Key.fromByte(first_byte), .char = first_byte };
    }
};

const Color = struct {
    const Self = @This();

    pub fn color4bit(allocator: std.mem.Allocator, color: u8) ![]u8 {
        // 30..37 are the 4-bit foreground codes
        return try std.fmt.allocPrint(allocator, "\x1b[{}m", .{30 + color});
    }

    pub fn color8bit(allocator: std.mem.Allocator, color: u8) ![]u8 {
        return try std.fmt.allocPrint(allocator, "\x1b[38;5;{}m", .{color});
    }

    pub fn colorRGB(allocator: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
        return try std.fmt.allocPrint(allocator, "\x1b[38;2;{};{};{}m", .{ r, g, b });
    }

    pub fn bgColor4bit(allocator: std.mem.Allocator, color: u8) ![]u8 {
        return try std.fmt.allocPrint(allocator, "\x1b[{}m", .{40 + color});
    }

    pub fn bgColor8bit(allocator: std.mem.Allocator, color: u8) ![]u8 {
        return try std.fmt.allocPrint(allocator, "\x1b[48;5;{}m", .{color});
    }

    pub fn bgColorRGB(allocator: std.mem.Allocator, r: u8, g: u8, b: u8) ![]u8 {
        return try std.fmt.allocPrint(allocator, "\x1b[48;2;{};{};{}m", .{ r, g, b });
    }
};

fn moveCursor(row: u16, col: u16) void {
    d_print(CSI ++ "{d}H", .{row});
    if (col > 1) {
        var i: u16 = 1;
        while (i < col) : (i += 1) {
            d_print("{s}", .{CURSOR_RIGHT});
        }
    }
}

fn setCursor(row: u16, col: u16) void {
    d_print(CSI ++ "{d};{d}H", .{ row, col });
}

pub fn main() !void {
    var terminal_mode = try TerminalMode.Init();
    defer terminal_mode.deinit();
    enableUtf8();
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator: std.mem.Allocator = gpa.allocator();

    print(CLEAR_SCREEN ++ CURSOR_HOME ++ HIDE_CURSOR);

    setCursor(2, 10);
    print(GREEN ++ "+------------+" ++ RESET);

    setCursor(3, 10);
    print(GREEN ++ "|" ++ YELLOW ++ "  TERMINAL  " ++ GREEN ++ "|" ++ RESET);

    setCursor(4, 10);
    print(GREEN ++ "|" ++ YELLOW ++ "   MAGIC!   " ++ GREEN ++ "|" ++ RESET);

    setCursor(5, 10);
    print(GREEN ++ "+------------+" ++ RESET);

    // Demonstrate colors
    setCursor(7, 10);
    print(RED ++ "Red text" ++ RESET);

    setCursor(8, 10);
    print(BG_BLUE ++ WHITE ++ "White on blue" ++ RESET);

    // Draw a simple "game world"
    setCursor(10, 10);
    print("Simple world:");

    var y: u16 = 11;
    while (y <= 15) : (y += 1) {
        setCursor(y, 10);
        var x: u16 = 0;
        while (x < 20) : (x += 1) {
            if (y == 11 or y == 15 or x == 0 or x == 19) {
                print(GREEN ++ "#" ++ RESET);
            } else if (y == 13 and x == 10) {
                print(YELLOW ++ "@" ++ RESET); // Player
            } else if (y == 12 and x == 15) {
                print(RED ++ "E" ++ RESET); // Enemy
            } else {
                print(".");
            }
        }
    }

    // Show cursor position info
    setCursor(17, 10);
    print("@ = Player, E = Enemy, # = Wall");

    setCursor(19, 1);
    print(CLEAR_SCREEN ++ CURSOR_HOME ++ HIDE_CURSOR);
    setCursor(2, 1);
    print("4-bit colors (16 colors):");
    setCursor(3, 1);

    var i: u8 = 0;
    while (i < 8) : (i += 1) {
        const color = try Color.color4bit(allocator, i);
        // print expects a comptime fmt string; pass runtime slices with {s}
        std.debug.print("{s}||{s}", .{ color, RESET });
        allocator.free(color); // free after use
    }

    std.debug.print("  ", .{}); // spacer

    // print with background color applied (foreground color + background 7)
    i = 0;
    while (i < 8) : (i += 1) {
        const fg = try Color.color4bit(allocator, i);
        const bg = try Color.bgColor4bit(allocator, 7);
        std.debug.print("{s}{s}█{s}", .{ fg, bg, RESET });
        allocator.free(fg);
        allocator.free(bg);
    }

    std.debug.print("{s}\n", .{SHOW_CURSOR});
    setCursor(5, 1);
    print("8-bit colors (256 colors) - Sample:");

    // Standard colors (0-15)
    setCursor(6, 1);
    i = 0;
    while (i < 16) : (i += 1) {
        const fg = try Color.color8bit(allocator, i);
        d_print("{s}█{s}", .{ fg, RESET });
        allocator.free(fg);
    }

    // 216 color cube (16-231)
    var row: u16 = 7;
    var color: u16 = 16;
    while (row < 13) : (row += 1) {
        setCursor(row, 1);
        var col: u16 = 0;
        while (col < 36 and color < 232) : ({
            col += 1;
            color += 1;
        }) {
            const fg = try Color.color8bit(allocator, @intCast(color));
            d_print("{s}|{s}", .{ fg, RESET });
            allocator.free(fg);
        }
    }

    // Grayscale (232-255)
    setCursor(13, 1);
    i = 232;
    while (i < 255) : (i += 1) {
        const fg = try Color.color8bit(allocator, i);
        d_print("{s}|{s}", .{ fg, RESET });
        allocator.free(fg);
    }

    // // Demonstrate 24-bit RGB colors
    // setCursor(15, 1);
    // print("24-bit RGB colors (16.7 million colors):");
    // setCursor(16, 1);

    // // Gradient example
    // var x: u16 = 0;
    // while (x < 50) : (x += 1) {
    //     const r = @as(u8, @intCast((x * 255) / 50));
    //     const g = @as(u8, @intCast(((50 - x) * 255) / 50));
    //     const b: u8 = 128;
    //     // print(Color.colorRGB(allocator, r, g, b) ++ "█" ++ RESET);
    //     d_print("{s}|{s}", .{ Color.colorRGB(allocator, r, g, b), RESET });
    // }

    // setCursor(17, 1);
    // // Rainbow gradient
    // x = 0;
    // while (x < 50) : (x += 1) {
    //     const hue = @as(f32, @floatFromInt(x)) / 50.0 * 360.0;
    //     const rgb = hsvToRgb(hue, 1.0, 1.0);
    //     // print(Color.colorRGB(allocator, rgb[0], rgb[1], rgb[2]) ++ "█" ++ RESET);
    //     d_print("{s}|{s}", .{ Color.colorRGB(allocator, rgb[0], rgb[1], rgb[2]), RESET });
    // }

    // // Game-like color demonstration
    // setCursor(19, 1);
    // print("Game colors in action:");

    // setCursor(20, 1);
    // // Health bar
    // print("Health: [");
    // i = 0;
    // while (i < 10) : (i += 1) {
    //     if (i < 7) {
    //         // print(Color.colorRGB(allocator, 255, 0, 0) ++ "█" ++ RESET);
    //         d_print("{s}|{s}", .{ Color.colorRGB(allocator, 255, 0, 0), RESET });
    //     } else {
    //         // print(Color.colorRGB(allocator, 64, 64, 64) ++ "█" ++ RESET);
    //         d_print("{s}|{s}", .{ Color.colorRGB(allocator, 64, 64, 64), RESET });
    //     }
    // }
    // print("] 70/100");

    // setCursor(21, 1);
    // // Mana bar
    // print("Mana:   [");
    // i = 0;
    // while (i < 10) : (i += 1) {
    //     if (i < 5) {
    //         // print(Color.colorRGB(allocator, 0, 0, 255) ++ "█" ++ RESET);
    //         d_print("{s}|{s}", .{ Color.colorRGB(allocator, 0, 0, 255), RESET });
    //     } else {
    //         // print(Color.colorRGB(allocator, 32, 32, 64) ++ "█" ++ RESET);
    //         d_print("{s}|{s}", .{ Color.colorRGB(allocator, 32, 32, 64), RESET });
    //     }
    // }
    // print("] 50/100");

    // setCursor(23, 1);
    // print("Different terrains:");
    // setCursor(24, 1);
    // // print(Color.colorRGB(allocator, 34, 139, 34) ++ "Forest" ++ RESET ++ "  ");
    // d_print("{s}{s}{s}", .{ Color.colorRGB(allocator, 34, 139, 34), "Forest", RESET });

    // // print(Color.colorRGB(allocator, 210, 180, 140) ++ "Desert" ++ RESET ++ "  ");
    // d_print("{s}{s}{s}", .{ Color.colorRGB(allocator, 34, 139, 34), "Desert", RESET });

    // // print(Color.colorRGB(allocator, 70, 130, 180) ++ "Water" ++ RESET ++ "  ");
    // d_print("{s}{s}{s}", .{ Color.colorRGB(allocator, 70, 130, 180), "Water", RESET });

    // // print(Color.colorRGB(allocator, 139, 69, 19) ++ "Mountain" ++ RESET);
    // d_print("{s}{s}{s}", .{ Color.colorRGB(allocator, 139, 69, 19), "Mountain", RESET });

    // setCursor(26, 1);
    print(CLEAR_SCREEN ++ CURSOR_HOME ++ HIDE_CURSOR);
    // Simple player position
    var player_x: i16 = 10;
    var player_y: i16 = 10;

    // Game world
    const world_width = 20;
    const world_height = 10;

    setCursor(1, 1);
    print("Raw Input Demo - Use arrow keys to move, ESC to quit");
    setCursor(2, 1);
    print("Press any key to see key codes");

    var running = true;
    while (running) {
        drawWorld(world_width, world_height, player_x, player_y);
        // Show current position
        setCursor(world_height + 5, 1);
        d_print("Player position: ({}, {})", .{ player_x, player_y });

        if (try InputReader.readKey()) |input| {
            setCursor(world_height + 6, 1);
            d_print("Last key: {} (char: {})", .{ input.key, input.char });

            switch (input.key) {
                .Escape => running = false,
                .ArrowUp => {
                    if (player_y > 0) player_y -= 1;
                },
                .ArrowDown => {
                    if (player_y < world_height - 1) player_y += 1;
                },
                .ArrowLeft => {
                    if (player_x > 0) player_x -= 1;
                },
                .ArrowRight => {
                    if (player_x < world_width - 1) player_x += 1;
                },
                .Character => {
                    // Handle WASD movement as well
                    switch (input.char) {
                        'w', 'W' => {
                            if (player_y > 0) player_y -= 1;
                        },
                        's', 'S' => {
                            if (player_y < world_height - 1) player_y += 1;
                        },
                        'a', 'A' => {
                            if (player_x > 0) player_x -= 1;
                        },
                        'd', 'D' => {
                            if (player_x < world_width - 1) player_x += 1;
                        },
                        'q', 'Q' => running = false,
                        else => {},
                    }
                },
                else => {},
            }
        }
        std.time.sleep(16_000_000); // ~60 FPS
    }
    print(SHOW_CURSOR ++ RESET);
    setCursor(world_height + 8, 1);
    print("Thanks for playing!");
    try entities.demonstrateAllocators();
    try entities.demonstrateErrorHandling();
    try components.demoComponents();
    // try comptimedemo.demoComptime();
    try naiverender.demoNaiverender();
}

fn drawWorld(width: i16, height: i16, player_x: i16, player_y: i16) void {
    var y: i16 = 0;
    while (y < height) : (y += 1) {
        setCursor(@intCast(y + 4), 5);
        var x: i16 = 0;
        while (x < width) : (x += 1) {
            if (x == player_x and y == player_y) {
                print(YELLOW ++ "@" ++ RESET);
            } else if (y == 0 or y == height - 1 or x == 0 or x == width - 1) {
                print(GREEN ++ "#" ++ RESET);
            } else {
                print(".");
            }
        }
    }
}

// HSV to RGB conversion for rainbow effects
fn hsvToRgb(h: f32, s: f32, v: f32) [3]u8 {
    const c1 = v * s;
    const x = c1 * (1 - @abs(@mod(h / 60.0, 2.0) - 1));
    const m = v - c1;

    var r: f32 = 0;
    var g: f32 = 0;
    var b: f32 = 0;

    if (h < 60) {
        r = c1;
        g = x;
        b = 0;
    } else if (h < 120) {
        r = x;
        g = c1;
        b = 0;
    } else if (h < 180) {
        r = 0;
        g = c1;
        b = x;
    } else if (h < 240) {
        r = 0;
        g = x;
        b = c1;
    } else if (h < 300) {
        r = x;
        g = 0;
        b = c1;
    } else {
        r = c1;
        g = 0;
        b = x;
    }

    return [3]u8{
        @as(u8, @intFromFloat((r + m) * 255)),
        @as(u8, @intFromFloat((g + m) * 255)),
        @as(u8, @intFromFloat((b + m) * 255)),
    };
}

const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("windows.h");
});

// TODO: move to game.zig

const entities = @import("./entities.zig");
const components = @import("./components.zig");
const comptimedemo = @import("./comptime.zig");
const naiverender = @import("./naiverendering.zig");
// ANSI Constants: We define escape sequences as compile-time string constants. The CSI (Control Sequence Introducer) \x1B[ is the start of most ANSI commands.
// Cursor Control: setCursor(row, col) uses the H command to position the cursor anywhere on screen. This is crucial for building our game world.
// Color System: We're using 4-bit colors (the original 16-color terminal palette). Each color has a foreground (31m for red) and background variant (41m for red background).
