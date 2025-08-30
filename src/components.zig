// Position - simple but we'll use this everywhere
const Position = struct {
    x: i32,
    y: i32,

    pub fn distance(self: Position, other: Position) f32 {
        const dx = @as(f32, @floatFromInt(self.x - other.x));
        const dy = @as(f32, @floatFromInt(self.y - other.y));
        return @sqrt(dx * dx + dy * dy);
    }

    pub fn add(self: Position, other: Position) Position {
        return Position{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn equals(self: Position, other: Position) bool {
        return self.x == other.x and self.y == other.y;
    }
};

// Tile types for our game world
const TileType = enum(u8) {
    Empty = '.',
    Wall = '#',
    Door = '+',
    Water = '~',
    Grass = ',',
    Mountain = '^',

    pub fn isPassable(self: TileType) bool {
        return switch (self) {
            .Empty, .Door, .Grass => true,
            .Wall, .Water, .Mountain => false,
        };
    }

    pub fn getMovementCost(self: TileType) u8 {
        return switch (self) {
            .Empty => 1,
            .Door => 1,
            .Grass => 2,
            .Water => 255, // Impassable
            .Wall => 255, // Impassable
            .Mountain => 255,
        };
    }

    pub fn toChar(self: TileType) u8 {
        return @intFromEnum(self);
    }
};

// Game input - tagged union for different input types
// Tagged Unions: InputEvent shows how we can handle different input types safely. The compiler ensures we handle all cases.
const InputEvent = union(enum) {
    KeyPress: struct {
        key: u8,
        modifiers: u8, // Bit flags for shift, ctrl, etc.
    },
    MouseClick: struct {
        x: i32,
        y: i32,
        button: MouseButton,
    },
    Quit,

    const MouseButton = enum { Left, Right, Middle };

    pub fn format(self: InputEvent, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .KeyPress => |key_event| try writer.print("KeyPress(key={c}, mod=0x{X})", .{ key_event.key, key_event.modifiers }),
            .MouseClick => |mouse_event| try writer.print("MouseClick({}, {}, {})", .{ mouse_event.x, mouse_event.y, mouse_event.button }),
            .Quit => print("Quit"),
        }
    }
};

// Entity component system foundation
const ComponentType = enum {
    Position,
    Renderable,
    Health,
    AI,
    Player,
    Inventory,
};

// Components as structs
const PositionComponent = struct {
    pos: Position,
};

const RenderableComponent = struct {
    character: u8,
    color_fg: u8,
    color_bg: u8,
    z_order: i8, // For layering
};

const HealthComponent = struct {
    current: i32,
    maximum: i32,

    pub fn isDead(self: HealthComponent) bool {
        return self.current <= 0;
    }

    pub fn damage(self: *HealthComponent, amount: i32) void {
        self.current = @max(0, self.current - amount);
    }

    pub fn heal(self: *HealthComponent, amount: i32) void {
        self.current = @min(self.maximum, self.current + amount);
    }

    pub fn getHealthPercent(self: HealthComponent) f32 {
        if (self.maximum == 0) return 0.0;
        return @as(f32, @floatFromInt(self.current)) / @as(f32, @floatFromInt(self.maximum));
    }
};

const AIComponent = struct {
    ai_type: AIType,
    target: ?u32, // Entity ID
    state: AIState,

    const AIType = enum {
        Passive,
        Aggressive,
        Patrol,
        Guard,
    };

    const AIState = enum {
        Idle,
        Chasing,
        Attacking,
        Fleeing,
        Patrolling,
    };
};

const ComponentStorage = struct {
    const Self = @This();
    const ENTITY_COUNT = 10000;

    // Parallel arrays for cache efficiency
    positions: std.ArrayList(?PositionComponent),
    renderables: std.ArrayList(?RenderableComponent),
    healths: std.ArrayList(?HealthComponent),
    ais: std.ArrayList(?AIComponent),

    // Entity metadata
    entity_versions: [ENTITY_COUNT]u32, // For detecting stale entity IDs
    free_entities: std.ArrayList(u32),
    next_entity_id: u32,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var storage = Self{
            .positions = std.ArrayList(?PositionComponent).init(allocator),
            .renderables = std.ArrayList(?RenderableComponent).init(allocator),
            .healths = std.ArrayList(?HealthComponent).init(allocator),
            .ais = std.ArrayList(?AIComponent).init(allocator),
            .entity_versions = std.mem.zeroes([ENTITY_COUNT]u32),
            .free_entities = std.ArrayList(u32).init(allocator),
            .next_entity_id = 0,
            .allocator = allocator,
        };

        // Pre-allocate arrays
        try storage.positions.resize(ENTITY_COUNT);
        try storage.renderables.resize(ENTITY_COUNT);
        try storage.healths.resize(ENTITY_COUNT);
        try storage.ais.resize(ENTITY_COUNT);

        // Initialize all as null
        for (0..ENTITY_COUNT) |i| {
            storage.positions.items[i] = null;
            storage.renderables.items[i] = null;
            storage.healths.items[i] = null;
            storage.ais.items[i] = null;
        }

        return storage;
    }

    pub fn deinit(self: *Self) void {
        self.positions.deinit();
        self.renderables.deinit();
        self.healths.deinit();
        self.ais.deinit();
        self.free_entities.deinit();
    }

    pub fn createEntity(self: *Self) !u32 {
        var entity_id: u32 = undefined;

        if (self.free_entities.items.len > 0) {
            entity_id = self.free_entities.pop().?;
        } else {
            entity_id = self.next_entity_id;
            self.next_entity_id += 1;

            if (entity_id >= ENTITY_COUNT) {
                return error.OutOfEntitySlots;
            }
        }

        // Increment version to invalidate old references
        self.entity_versions[entity_id] += 1;

        return entity_id;
    }

    pub fn destroyEntity(self: *Self, entity_id: u32) !void {
        if (entity_id >= ENTITY_COUNT) return;

        // Remove all components
        self.positions.items[entity_id] = null;
        self.renderables.items[entity_id] = null;
        self.healths.items[entity_id] = null;
        self.ais.items[entity_id] = null;

        // Add to free list
        try self.free_entities.append(entity_id);
    }

    // Component accessors
    pub fn addPosition(self: *Self, entity_id: u32, pos: Position) void {
        if (entity_id < ENTITY_COUNT) {
            self.positions.items[entity_id] = PositionComponent{ .pos = pos };
        }
    }

    pub fn getPosition(self: *Self, entity_id: u32) ?*PositionComponent {
        if (entity_id >= ENTITY_COUNT) return null;
        if (self.positions.items[entity_id]) |*pos| return pos;
        return null;
    }

    pub fn addRenderable(self: *Self, entity_id: u32, character: u8, fg: u8, bg: u8) void {
        if (entity_id < ENTITY_COUNT) {
            self.renderables.items[entity_id] = RenderableComponent{
                .character = character,
                .color_fg = fg,
                .color_bg = bg,
                .z_order = 0,
            };
        }
    }

    pub fn addHealth(self: *Self, entity_id: u32, max_health: i32) void {
        if (entity_id < ENTITY_COUNT) {
            self.healths.items[entity_id] = HealthComponent{
                .current = max_health,
                .maximum = max_health,
            };
        }
    }
};

// Game state management
const GameState = enum {
    MainMenu,
    Playing,
    Paused,
    GameOver,
    Loading,
};

const Game = struct {
    const Self = @This();

    state: GameState,
    components: ComponentStorage,
    player_entity: ?u32,
    turn_count: u64,

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .state = .MainMenu,
            .components = try ComponentStorage.init(allocator),
            .player_entity = null,
            .turn_count = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.components.deinit();
    }

    pub fn createPlayer(self: *Self, pos: Position) !void {
        const player = try self.components.createEntity();

        self.components.addPosition(player, pos);
        self.components.addRenderable(player, '@', 15, 0); // White @ on black
        self.components.addHealth(player, 100);

        self.player_entity = player;
        self.state = .Playing;
    }

    pub fn createMonster(self: *Self, pos: Position, monster_type: u8) !u32 {
        const monster = try self.components.createEntity();

        self.components.addPosition(monster, pos);
        self.components.addRenderable(monster, monster_type, 12, 0); // Red on black
        self.components.addHealth(monster, 30);

        return monster;
    }

    pub fn processInput(self: *Self, input: InputEvent) !void {
        switch (self.state) {
            .Playing => {
                switch (input) {
                    .KeyPress => |key_event| {
                        if (self.player_entity) |player| {
                            if (self.components.getPosition(player)) |pos| {
                                const old_pos = pos.pos;
                                var new_pos = old_pos;

                                switch (key_event.key) {
                                    'w' => new_pos.y -= 1,
                                    's' => new_pos.y += 1,
                                    'a' => new_pos.x -= 1,
                                    'd' => new_pos.x += 1,
                                    'q' => self.state = .MainMenu,
                                    else => return, // No movement
                                }

                                // Simple bounds checking
                                if (new_pos.x >= 0 and new_pos.x < 80 and
                                    new_pos.y >= 0 and new_pos.y < 24)
                                {
                                    pos.pos = new_pos;
                                    self.turn_count += 1;
                                }
                            }
                        }
                    },
                    .Quit => self.state = .MainMenu,
                    else => {},
                }
            },
            .MainMenu => {
                switch (input) {
                    .KeyPress => |key_event| {
                        if (key_event.key == ' ') {
                            try self.createPlayer(Position{ .x = 40, .y = 12 });
                        }
                    },
                    .Quit => {}, // Handle quit at higher level
                    else => {},
                }
            },
            else => {},
        }
    }
};

pub fn demoComponents() !void {
    print("=== Game Data Structures Demo ===\n\n");

    // Initialize game
    var game = try Game.init(std.heap.page_allocator);
    defer game.deinit();

    d_print("Game initialized in state: {}\n", .{game.state});

    // Create some entities
    try game.createPlayer(Position{ .x = 10, .y = 10 });
    const orc = try game.createMonster(Position{ .x = 15, .y = 8 }, 'o');
    const goblin = try game.createMonster(Position{ .x = 5, .y = 12 }, 'g');

    d_print("Created player and 2 monsters {d}-{d}\n", .{ orc, goblin });

    // Simulate some input
    const inputs = [_]InputEvent{
        InputEvent{ .KeyPress = .{ .key = 'd', .modifiers = 0 } }, // Move right
        InputEvent{ .KeyPress = .{ .key = 's', .modifiers = 0 } }, // Move down
        InputEvent{ .KeyPress = .{ .key = 'w', .modifiers = 0 } }, // Move up
    };

    for (inputs) |input| {
        d_print("Processing input: {}\n", .{input});
        try game.processInput(input);

        if (game.player_entity) |player| {
            if (game.components.getPosition(player)) |pos| {
                d_print("Player position: ({}, {})\n", .{ pos.pos.x, pos.pos.y });
            }
        }
    }

    d_print("Turn count: {}\n", .{game.turn_count});

    // Demonstrate component queries
    print("\nActive entities:\n");
    for (0..game.components.next_entity_id) |i| {
        const entity_id = @as(u32, @intCast(i));

        const pos = game.components.positions.items[entity_id];
        const renderable = game.components.renderables.items[entity_id];
        const health = game.components.healths.items[entity_id];

        if (pos != null and renderable != null) {
            const char = renderable.?.character;
            const p = pos.?.pos;
            const hp = if (health) |h| h.current else -1;

            d_print("Entity {}: '{}' at ({}, {}) HP: {}\n", .{ entity_id, char, p.x, p.y, hp });
        }
    }
}

const std = @import("std");
const d_print = std.debug.print;

fn print(s: []const u8) void {
    d_print("{s}", .{s});
}
