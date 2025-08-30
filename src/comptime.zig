// Generic 2D grid - the foundation of our game world
fn Grid(comptime T: type, comptime width: usize, comptime height: usize) type {
    return struct {
        const Self = @This();

        data: [height][width]T,

        pub fn init(default_value: T) Self {
            return Self{
                .data = [_][width]T{[_]T{default_value} ** width} ** height,
            };
        }

        pub fn get(self: *const Self, x: usize, y: usize) ?T {
            if (x >= width or y >= height) return null;
            return self.data[y][x];
        }

        pub fn set(self: *Self, x: usize, y: usize, value: T) bool {
            if (x >= width or y >= height) return false;
            self.data[y][x] = value;
            return true;
        }

        pub fn isValid(self: *const Self, x: i32, y: i32) bool {
            _ = self; // Grid size is comptime-known
            return x >= 0 and y >= 0 and x < width and y < height;
        }

        pub fn fill(self: *Self, value: T) void {
            for (&self.data) |*row| {
                for (row) |*cell| {
                    cell.* = value;
                }
            }
        }

        // Comptime method to get grid info
        pub fn getInfo() GridInfo {
            return GridInfo{
                .width = width,
                .height = height,
                .total_cells = width * height,
                .cell_size = @sizeOf(T),
                .total_bytes = width * height * @sizeOf(T),
            };
        }
    };
}

const GridInfo = struct {
    width: usize,
    height: usize,
    total_cells: usize,
    cell_size: usize,
    total_bytes: usize,
};

// Comptime string building for debug output
fn buildDebugString(comptime prefix: []const u8, comptime items: []const []const u8) []const u8 {
    comptime {
        var result: []const u8 = prefix ++ ": ";
        for (items, 0..) |item, i| {
            result = result ++ item;
            if (i < items.len - 1) {
                result = result ++ ", ";
            }
        }
        return result;
    }
}

// Generic event system using comptime
fn EventSystem(comptime EventTypes: []const type) type {
    return struct {
        const Self = @This();

        // Generate handler arrays for each event type at compile time
        const HandlerStorage = blk: {
            var fields: [EventTypes.len]std.builtin.Type.StructField = undefined;

            for (EventTypes, 0..) |EventType, i| {
                const HandlerFn = *const fn (EventType) void;
                const HandlerList = std.ArrayList(HandlerFn);

                fields[i] = std.builtin.Type.StructField{
                    .name = std.fmt.comptimePrint("handlers_{}", .{i}),
                    .type = HandlerList,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(HandlerList),
                };
            }

            break :blk @Type(std.builtin.Type{
                .@"struct" = .{
                    .layout = .auto,
                    .fields = &fields,
                    .decls = &[_]std.builtin.Type.Declaration{},
                    .is_tuple = false,
                },
            });
        };

        handlers: HandlerStorage,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            var system = Self{
                .handlers = undefined,
                .allocator = allocator,
            };

            // Initialize all handler arrays
            inline for (EventTypes, 0..) |_, i| {
                @field(system.handlers, std.fmt.comptimePrint("handlers_{}", .{i})) =
                    std.ArrayList(@TypeOf(@field(system.handlers, std.fmt.comptimePrint("handlers_{}", .{i})).items[0])).init(allocator);
            }

            return system;
        }

        pub fn deinit(self: *Self) void {
            inline for (EventTypes, 0..) |_, i| {
                @field(self.handlers, std.fmt.comptimePrint("handlers_{}", .{i})).deinit();
            }
        }

        pub fn subscribe(self: *Self, comptime EventType: type, handler: *const fn (EventType) void) !void {
            const type_index = comptime blk: {
                for (EventTypes, 0..) |T, i| {
                    if (T == EventType) break :blk i;
                }
                @compileError("Event type not supported by this system");
            };

            try @field(self.handlers, std.fmt.comptimePrint("handlers_{}", .{type_index})).append(handler);
        }

        pub fn emit(self: *Self, event: anytype) void {
            const EventType = @TypeOf(event);
            const type_index = comptime blk: {
                for (EventTypes, 0..) |T, i| {
                    if (T == EventType) break :blk i;
                }
                @compileError("Event type not supported by this system");
            };

            const handlers = @field(self.handlers, std.fmt.comptimePrint("handlers_{}", .{type_index}));
            for (handlers.items) |handler| {
                handler(event);
            }
        }
    };
}

// Game-specific types for our event system
const PlayerMoveEvent = struct {
    old_pos: struct { x: i32, y: i32 },
    new_pos: struct { x: i32, y: i32 },
};

const CombatEvent = struct {
    attacker_id: u32,
    defender_id: u32,
    damage: i32,
};

const PickupEvent = struct {
    player_id: u32,
    item_id: u32,
    item_name: []const u8,
};

// Comptime validation and optimization
const GameConfig = struct {
    max_entities: comptime_int,
    world_width: comptime_int,
    world_height: comptime_int,
    max_inventory_size: comptime_int,

    // Comptime validation
    comptime {
        if (@This().max_entities <= 0 or @This().max_entities > 100000) {
            @compileError("max_entities must be between 1 and 100000");
        }
        if (@This().world_width <= 0 or @This().world_height <= 0) {
            @compileError("World dimensions must be positive");
        }
        if (@This().world_width * @This().world_height > 1000000) {
            @compileError("World too large - would use too much memory");
        }
    }

    pub fn getMemoryUsage() comptime_int {
        const entity_bytes = @This().max_entities * 64; // Rough estimate per entity
        const world_bytes = @This().world_width * @This().world_height * 4; // 4 bytes per tile
        return entity_bytes + world_bytes;
    }

    pub fn isSmallWorld() bool {
        return @This().world_width * @This().world_height < 10000;
    }
};

// Template specialization based on comptime parameters
fn PathfindingAlgorithm(comptime config: GameConfig) type {
    return struct {
        pub fn findPath(start_x: i32, start_y: i32, end_x: i32, end_y: i32) ?[]const struct { x: i32, y: i32 } {
            // Choose algorithm based on world size at compile time
            if (config.isSmallWorld()) {
                return findPathAStar(start_x, start_y, end_x, end_y);
            } else {
                return findPathJPS(start_x, start_y, end_x, end_y); // Jump Point Search for large worlds
            }
        }

        fn findPathAStar(start_x: i32, start_y: i32, end_x: i32, end_y: i32) ?[]const struct { x: i32, y: i32 } {
            _ = start_x;
            _ = start_y;
            _ = end_x;
            _ = end_y;
            // A* implementation for small worlds
            return null; // Placeholder
        }

        fn findPathJPS(start_x: i32, start_y: i32, end_x: i32, end_y: i32) ?[]const struct { x: i32, y: i32 } {
            _ = start_x;
            _ = start_y;
            _ = end_x;
            _ = end_y;
            // Jump Point Search implementation for large worlds
            return null; // Placeholder
        }
    };
}

// Comptime code generation for component systems
fn generateComponentMask(comptime component_types: []const type) type {
    const bit_count = component_types.len;

    if (bit_count <= 8) {
        return u8;
    } else if (bit_count <= 16) {
        return u16;
    } else if (bit_count <= 32) {
        return u32;
    } else if (bit_count <= 64) {
        return u64;
    } else {
        @compileError("Too many component types - maximum 64 supported");
    }
}

pub fn demoComptime() !void {
    print("=== Comptime & Generic Programming Demo ===\n\n");

    // 1. Generic Grid System
    print("1. Generic Grids:\n");

    // Different grid types created at compile time
    const TileGrid = Grid(u8, 80, 24); // Terminal-sized tile map
    const HeightGrid = Grid(f32, 100, 100); // Height map for terrain
    const EntityGrid = Grid(?u32, 50, 50); // Sparse entity positions

    var tile_map = TileGrid.init('.');
    var height_map = HeightGrid.init(0.0);
    var entity_map = EntityGrid.init(null);

    // Set some values
    _ = tile_map.set(10, 5, '#');
    _ = height_map.set(25, 25, 100.5);
    _ = entity_map.set(15, 15, 42);

    d_print("Tile at (10,5): {c}\n", .{tile_map.get(10, 5) orelse '?'});
    d_print("Height at (25,25): {d:.1}\n", .{height_map.get(25, 25) orelse 0});
    d_print("Entity at (15,15): {?}\n", .{entity_map.get(15, 15) orelse null});

    // Comptime grid info
    const tile_info = TileGrid.getInfo();
    d_print("TileGrid: {}x{} = {} cells, {} bytes total\n", .{ tile_info.width, tile_info.height, tile_info.total_cells, tile_info.total_bytes });

    // 2. Comptime String Building
    print("\n2. Comptime String Generation:\n");
    const debug_msg = comptime buildDebugString("GameStats", &[_][]const u8{ "HP: 100", "MP: 50", "Level: 5" });
    d_print("{s}\n", .{debug_msg});

    // 3. Generic Event System
    print("\n3. Event System:\n");
    const GameEvents = EventSystem(&[_]type{ PlayerMoveEvent, CombatEvent, PickupEvent });
    var event_system = GameEvents.init(std.heap.page_allocator);
    defer event_system.deinit();

    // Subscribe to events
    const moveHandler = struct {
        fn handle(event: PlayerMoveEvent) void {
            print("Player moved from ({},{}) to ({},{})\n", .{ event.old_pos.x, event.old_pos.y, event.new_pos.x, event.new_pos.y });
        }
    }.handle;

    const combatHandler = struct {
        fn handle(event: CombatEvent) void {
            print("Entity {} attacks {} for {} damage!\n", .{ event.attacker_id, event.defender_id, event.damage });
        }
    }.handle;

    try event_system.subscribe(PlayerMoveEvent, moveHandler);
    try event_system.subscribe(CombatEvent, combatHandler);

    // Emit events
    event_system.emit(PlayerMoveEvent{
        .old_pos = .{ .x = 10, .y = 10 },
        .new_pos = .{ .x = 11, .y = 10 },
    });

    event_system.emit(CombatEvent{
        .attacker_id = 1,
        .defender_id = 2,
        .damage = 25,
    });

    // 4. Comptime Configuration & Optimization
    print("\n4. Comptime Configuration:\n");

    const small_game_config = GameConfig{
        .max_entities = 1000,
        .world_width = 80,
        .world_height = 24,
        .max_inventory_size = 20,
    };

    const large_game_config = GameConfig{
        .max_entities = 50000,
        .world_width = 500,
        .world_height = 500,
        .max_inventory_size = 100,
    };

    d_print("Small game memory usage: {} bytes\n", .{small_game_config.getMemoryUsage()});
    d_print("Large game memory usage: {} bytes\n", .{large_game_config.getMemoryUsage()});

    d_print("Small world uses optimized pathfinding: {}\n", .{small_game_config.isSmallWorld()});
    d_print("Large world uses optimized pathfinding: {}\n", .{large_game_config.isSmallWorld()});

    // 5. Component Mask Generation
    d_print("\n5. Component System Optimization:\n");

    const ComponentTypes = [_]type{
        struct {}, struct {}, struct {}, // Position, Renderable, Health
        struct {}, struct {}, struct {}, // AI, Player, Inventory
    };

    const ComponentMask = generateComponentMask(&ComponentTypes);
    d_print("Component mask type for {} components: {}\n", .{ ComponentTypes.len, ComponentMask });
    d_print("Mask size: {} bits\n", .{@bitSizeOf(ComponentMask)});

    print("\n=== Comptime Benefits ===\n");
    print("• Zero runtime cost for configuration\n");
    print("• Compile-time error checking\n");
    print("• Automatic code specialization\n");
    print("• Type-safe generic programming\n");
    print("• Memory layout optimization\n");
}

const std = @import("std");
const d_print = std.debug.print;

fn print(s: []const u8) void {
    d_print("{s}", .{s});
}
