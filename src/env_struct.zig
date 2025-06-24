const std = @import("std");

fn parseValue(comptime FieldType: type, val: []const u8, env_map: ?std.process.EnvMap, allocator: std.mem.Allocator) !FieldType {
    const field_type_info = @typeInfo(FieldType);

    switch (field_type_info) {
        .@"struct" => {
            return try loadCore(FieldType, env_map, allocator);
        },
        else => {
            switch (FieldType) {
                []const u8 => return val,
                i32 => return try std.fmt.parseInt(i32, val, 10),
                i64 => return try std.fmt.parseInt(i64, val, 10),
                u32 => return try std.fmt.parseInt(u32, val, 10),
                u64 => return try std.fmt.parseInt(u64, val, 10),
                f32 => return try std.fmt.parseFloat(f32, val),
                f64 => return try std.fmt.parseFloat(f64, val),
                bool => {
                    var lower_buf: [4]u8 = undefined;
                    if (val.len <= lower_buf.len) {
                        for (val, 0..) |c, i| {
                            lower_buf[i] = std.ascii.toLower(c);
                        }
                        const lower = lower_buf[0..val.len];
                        return std.mem.eql(u8, lower, "true") or
                            std.mem.eql(u8, lower, "1") or
                            std.mem.eql(u8, lower, "yes");
                    } else {
                        return std.mem.eql(u8, val, "true") or
                            std.mem.eql(u8, val, "1") or
                            std.mem.eql(u8, val, "yes") or
                            std.mem.eql(u8, val, "TRUE") or
                            std.mem.eql(u8, val, "YES");
                    }
                },
                else => @compileError("Unsupported field type: " ++ @typeName(FieldType)),
            }
        },
    }
}

fn loadCore(comptime T: type, env_map: ?std.process.EnvMap, allocator: std.mem.Allocator) !T {
    var result: T = undefined;

    const type_info = @typeInfo(T);
    if (type_info != .@"struct") {
        @compileError("Expected a struct type");
    }

    if (!@hasDecl(T, "env")) {
        @compileError("Struct must have an 'env' declaration");
    }

    var owned_env_map: ?std.process.EnvMap = null;
    defer if (owned_env_map) |*map| map.deinit();

    const active_env_map = if (env_map) |map| map else blk: {
        owned_env_map = try std.process.getEnvMap(allocator);
        break :blk owned_env_map.?;
    };

    inline for (type_info.@"struct".fields) |field| {
        const env_decl = T.env;

        if (@hasField(@TypeOf(env_decl), field.name)) {
            const env_key = @field(env_decl, field.name);

            const field_type_info = @typeInfo(field.type);
            const is_optional = field_type_info == .optional;

            const default_value = field.defaultValue();

            if (field_type_info == .@"struct") {
                @field(result, field.name) = try parseValue(field.type, "", env_map, allocator);
            } else if (is_optional) {
                const child_type = field_type_info.optional.child;
                const child_type_info = @typeInfo(child_type);

                if (child_type_info == .@"struct") {
                    @field(result, field.name) = try parseValue(child_type, "", env_map, allocator);
                } else {
                    const value = active_env_map.get(env_key);
                    if (value) |val| {
                        @field(result, field.name) = try parseValue(child_type, val, env_map, allocator);
                    } else if (default_value) |def_val| {
                        @field(result, field.name) = def_val;
                    } else {
                        @field(result, field.name) = null;
                    }
                }
            } else {
                const value = active_env_map.get(env_key);
                if (value) |val| {
                    @field(result, field.name) = try parseValue(field.type, val, env_map, allocator);
                } else {
                    if (default_value) |def_val| {
                        @field(result, field.name) = def_val;
                    } else {
                        return error.MissingEnvironmentVariable;
                    }
                }
            }
        } else {
            const default_value = field.defaultValue();
            if (default_value) |def_val| {
                @field(result, field.name) = def_val;
            } else {
                const field_type_info = @typeInfo(field.type);
                if (field_type_info != .optional) {
                    @compileError("Field '" ++ field.name ++ "' has no default value and is not mapped to an environment variable");
                }
                @field(result, field.name) = null;
            }
        }
    }

    return result;
}

pub fn load(comptime T: type, allocator: std.mem.Allocator) !T {
    return try loadCore(T, null, allocator);
}

pub fn loadMap(comptime T: type, env_map: std.process.EnvMap, allocator: std.mem.Allocator) !T {
    return try loadCore(T, env_map, allocator);
}

// Test utilities
fn createTestEnvMap(allocator: std.mem.Allocator, env_vars: []const struct { key: []const u8, value: []const u8 }) !std.process.EnvMap {
    var env_map = std.process.EnvMap.init(allocator);
    for (env_vars) |env_var| {
        try env_map.put(env_var.key, env_var.value);
    }
    return env_map;
}

test "parse basic string value" {
    const TestConfig = struct {
        name: []const u8,

        const env = .{
            .name = "TEST_NAME",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "TEST_NAME", .value = "hello world" },
    });
    defer env_map.deinit();

    const config = try loadMap(TestConfig, env_map, allocator);
    try std.testing.expectEqualStrings("hello world", config.name);
}

test "parse integer values" {
    const TestConfig = struct {
        port: u32,
        timeout: i32,
        big_num: u64,
        negative: i64,

        const env = .{
            .port = "TEST_PORT",
            .timeout = "TEST_TIMEOUT",
            .big_num = "TEST_BIG_NUM",
            .negative = "TEST_NEGATIVE",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "TEST_PORT", .value = "8080" },
        .{ .key = "TEST_TIMEOUT", .value = "30" },
        .{ .key = "TEST_BIG_NUM", .value = "18446744073709551615" },
        .{ .key = "TEST_NEGATIVE", .value = "-42" },
    });
    defer env_map.deinit();

    const config = try loadMap(TestConfig, env_map, allocator);
    try std.testing.expectEqual(@as(u32, 8080), config.port);
    try std.testing.expectEqual(@as(i32, 30), config.timeout);
    try std.testing.expectEqual(@as(u64, 18446744073709551615), config.big_num);
    try std.testing.expectEqual(@as(i64, -42), config.negative);
}

test "parse float values" {
    const TestConfig = struct {
        ratio: f32,
        precision: f64,

        const env = .{
            .ratio = "TEST_RATIO",
            .precision = "TEST_PRECISION",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "TEST_RATIO", .value = "3.14" },
        .{ .key = "TEST_PRECISION", .value = "2.718281828459045" },
    });
    defer env_map.deinit();

    const config = try loadMap(TestConfig, env_map, allocator);
    try std.testing.expectApproxEqAbs(@as(f32, 3.14), config.ratio, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 2.718281828459045), config.precision, 0.000000000000001);
}

test "parse boolean values" {
    const TestConfig = struct {
        debug: bool,
        verbose: bool,
        enabled: bool,
        disabled: bool,

        const env = .{
            .debug = "TEST_DEBUG",
            .verbose = "TEST_VERBOSE",
            .enabled = "TEST_ENABLED",
            .disabled = "TEST_DISABLED",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "TEST_DEBUG", .value = "true" },
        .{ .key = "TEST_VERBOSE", .value = "1" },
        .{ .key = "TEST_ENABLED", .value = "YES" },
        .{ .key = "TEST_DISABLED", .value = "false" },
    });
    defer env_map.deinit();

    const config = try loadMap(TestConfig, env_map, allocator);
    try std.testing.expect(config.debug);
    try std.testing.expect(config.verbose);
    try std.testing.expect(config.enabled);
    try std.testing.expect(!config.disabled);
}

test "parse optional values" {
    const TestConfig = struct {
        required: []const u8,
        optional_present: ?[]const u8,
        optional_missing: ?i32,

        const env = .{
            .required = "TEST_REQUIRED",
            .optional_present = "TEST_OPTIONAL_PRESENT",
            .optional_missing = "TEST_OPTIONAL_MISSING",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "TEST_REQUIRED", .value = "must be here" },
        .{ .key = "TEST_OPTIONAL_PRESENT", .value = "i am here" },
    });
    defer env_map.deinit();

    const config = try loadMap(TestConfig, env_map, allocator);
    try std.testing.expectEqualStrings("must be here", config.required);
    try std.testing.expectEqualStrings("i am here", config.optional_present.?);
    try std.testing.expectEqual(@as(?i32, null), config.optional_missing);
}

test "parse values with defaults" {
    const TestConfig = struct {
        port: u32 = 3000,
        debug: bool = false,
        name: []const u8 = "default_name",

        const env = .{
            .port = "TEST_PORT_DEFAULT",
            .debug = "TEST_DEBUG_DEFAULT",
            .name = "TEST_NAME_DEFAULT",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{});
    defer env_map.deinit();

    const config = try loadMap(TestConfig, env_map, allocator);
    try std.testing.expectEqual(@as(u32, 3000), config.port);
    try std.testing.expect(!config.debug);
    try std.testing.expectEqualStrings("default_name", config.name);
}

test "parse optional fields with defaults when environment variable present" {
    const TestConfig = struct {
        port: u32 = 3000,
        timeout: ?i32 = 30,
        name: []const u8 = "default_name",

        const env = .{
            .port = "TEST_PORT",
            .timeout = "TEST_TIMEOUT",
            .name = "TEST_NAME",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "TEST_PORT", .value = "8080" },
        .{ .key = "TEST_TIMEOUT", .value = "60" },
    });
    defer env_map.deinit();

    const config = try loadMap(TestConfig, env_map, allocator);
    try std.testing.expectEqual(@as(u32, 8080), config.port);
    try std.testing.expectEqual(@as(?i32, 60), config.timeout);
    try std.testing.expectEqualStrings("default_name", config.name);
}

test "parse mixed optional and default fields" {
    const TestConfig = struct {
        required_field: []const u8,
        optional_field: ?[]const u8,
        default_field: u32 = 42,
        optional_with_default: ?i32 = 100,

        const env = .{
            .required_field = "REQUIRED",
            .optional_field = "OPTIONAL",
            .default_field = "DEFAULT",
            .optional_with_default = "OPTIONAL_DEFAULT",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "REQUIRED", .value = "present" },
    });
    defer env_map.deinit();

    const config = try loadMap(TestConfig, env_map, allocator);
    try std.testing.expectEqualStrings("present", config.required_field);
    try std.testing.expectEqual(@as(?[]const u8, null), config.optional_field);
    try std.testing.expectEqual(@as(u32, 42), config.default_field);
    try std.testing.expectEqual(@as(?i32, 100), config.optional_with_default);
}

test "parse nested struct" {
    const DatabaseConfig = struct {
        host: []const u8,
        port: u32,

        const env = .{
            .host = "DB_HOST",
            .port = "DB_PORT",
        };
    };

    const TestConfig = struct {
        app_name: []const u8,
        database: DatabaseConfig,

        const env = .{
            .app_name = "APP_NAME",
            .database = "",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "APP_NAME", .value = "my_app" },
        .{ .key = "DB_HOST", .value = "localhost" },
        .{ .key = "DB_PORT", .value = "5432" },
    });
    defer env_map.deinit();

    const config = try loadMap(TestConfig, env_map, allocator);
    try std.testing.expectEqualStrings("my_app", config.app_name);
    try std.testing.expectEqualStrings("localhost", config.database.host);
    try std.testing.expectEqual(@as(u32, 5432), config.database.port);
}

test "parse optional nested struct" {
    const CacheConfig = struct {
        enabled: bool,
        ttl: u32,

        const env = .{
            .enabled = "CACHE_ENABLED",
            .ttl = "CACHE_TTL",
        };
    };

    const TestConfig = struct {
        app_name: []const u8,
        cache: ?CacheConfig,

        const env = .{
            .app_name = "APP_NAME",
            .cache = "",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "APP_NAME", .value = "my_app" },
        .{ .key = "CACHE_ENABLED", .value = "true" },
        .{ .key = "CACHE_TTL", .value = "300" },
    });
    defer env_map.deinit();

    const config = try loadMap(TestConfig, env_map, allocator);
    try std.testing.expectEqualStrings("my_app", config.app_name);
    try std.testing.expect(config.cache != null);
    try std.testing.expect(config.cache.?.enabled);
    try std.testing.expectEqual(@as(u32, 300), config.cache.?.ttl);
}

test "missing required environment variable" {
    const TestConfig = struct {
        required_field: []const u8,

        const env = .{
            .required_field = "MISSING_VAR",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{});
    defer env_map.deinit();

    const result = loadMap(TestConfig, env_map, allocator);
    try std.testing.expectError(error.MissingEnvironmentVariable, result);
}

test "invalid integer parsing" {
    const TestConfig = struct {
        port: u32,

        const env = .{
            .port = "INVALID_PORT",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "INVALID_PORT", .value = "not_a_number" },
    });
    defer env_map.deinit();

    const result = loadMap(TestConfig, env_map, allocator);
    try std.testing.expectError(error.InvalidCharacter, result);
}

test "invalid float parsing" {
    const TestConfig = struct {
        ratio: f32,

        const env = .{
            .ratio = "INVALID_FLOAT",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "INVALID_FLOAT", .value = "not_a_float" },
    });
    defer env_map.deinit();

    const result = loadMap(TestConfig, env_map, allocator);
    try std.testing.expectError(error.InvalidCharacter, result);
}

test "field without env mapping is skipped" {
    const TestConfig = struct {
        mapped_field: []const u8,
        unmapped_field: []const u8 = "default",

        const env = .{
            .mapped_field = "MAPPED_FIELD",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "MAPPED_FIELD", .value = "mapped_value" },
    });
    defer env_map.deinit();

    const config = try loadMap(TestConfig, env_map, allocator);
    try std.testing.expectEqualStrings("mapped_value", config.mapped_field);
    try std.testing.expectEqualStrings("default", config.unmapped_field);
}

test "boolean case insensitive parsing" {
    const TestConfig = struct {
        flag1: bool,
        flag2: bool,
        flag3: bool,
        flag4: bool,

        const env = .{
            .flag1 = "FLAG1",
            .flag2 = "FLAG2",
            .flag3 = "FLAG3",
            .flag4 = "FLAG4",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "FLAG1", .value = "TRUE" },
        .{ .key = "FLAG2", .value = "True" },
        .{ .key = "FLAG3", .value = "YES" },
        .{ .key = "FLAG4", .value = "Yes" },
    });
    defer env_map.deinit();

    const config = try loadMap(TestConfig, env_map, allocator);
    try std.testing.expect(config.flag1);
    try std.testing.expect(config.flag2);
    try std.testing.expect(config.flag3);
    try std.testing.expect(config.flag4);
}

test "comprehensive real-world config example" {
    const DatabaseConfig = struct {
        host: []const u8,
        port: u32,
        username: []const u8,
        password: ?[]const u8,
        ssl_enabled: bool,

        const env = .{
            .host = "DB_HOST",
            .port = "DB_PORT",
            .username = "DB_USERNAME",
            .password = "DB_PASSWORD",
            .ssl_enabled = "DB_SSL_ENABLED",
        };
    };

    const RedisConfig = struct {
        url: []const u8,
        timeout: u32,

        const env = .{
            .url = "REDIS_URL",
            .timeout = "REDIS_TIMEOUT",
        };
    };

    const AppConfig = struct {
        app_name: []const u8,
        port: u32,
        debug: bool,
        database: DatabaseConfig,
        redis: ?RedisConfig,

        const env = .{
            .app_name = "APP_NAME",
            .port = "PORT",
            .debug = "DEBUG",
            .database = "",
            .redis = "",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "APP_NAME", .value = "my-awesome-app" },
        .{ .key = "PORT", .value = "8080" },
        .{ .key = "DEBUG", .value = "true" },
        .{ .key = "DB_HOST", .value = "localhost" },
        .{ .key = "DB_PORT", .value = "5432" },
        .{ .key = "DB_USERNAME", .value = "admin" },
        .{ .key = "DB_PASSWORD", .value = "secret123" },
        .{ .key = "DB_SSL_ENABLED", .value = "yes" },
        .{ .key = "REDIS_URL", .value = "redis://localhost:6379" },
        .{ .key = "REDIS_TIMEOUT", .value = "5000" },
    });
    defer env_map.deinit();

    const config = try loadMap(AppConfig, env_map, allocator);

    try std.testing.expectEqualStrings("my-awesome-app", config.app_name);
    try std.testing.expectEqual(@as(u32, 8080), config.port);
    try std.testing.expect(config.debug);

    try std.testing.expectEqualStrings("localhost", config.database.host);
    try std.testing.expectEqual(@as(u32, 5432), config.database.port);
    try std.testing.expectEqualStrings("admin", config.database.username);
    try std.testing.expectEqualStrings("secret123", config.database.password.?);
    try std.testing.expect(config.database.ssl_enabled);

    try std.testing.expect(config.redis != null);
    try std.testing.expectEqualStrings("redis://localhost:6379", config.redis.?.url);
    try std.testing.expectEqual(@as(u32, 5000), config.redis.?.timeout);
}

test "edge cases and error conditions" {
    const BigNumConfig = struct {
        max_u64: u64,
        min_i64: i64,

        const env = .{
            .max_u64 = "MAX_U64",
            .min_i64 = "MIN_I64",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "MAX_U64", .value = "18446744073709551615" },
        .{ .key = "MIN_I64", .value = "-9223372036854775808" },
    });
    defer env_map.deinit();

    const config = try loadMap(BigNumConfig, env_map, allocator);
    try std.testing.expectEqual(@as(u64, 18446744073709551615), config.max_u64);
    try std.testing.expectEqual(@as(i64, -9223372036854775808), config.min_i64);
}

test "boolean edge cases" {
    const BoolConfig = struct {
        flag_false1: bool,
        flag_false2: bool,
        flag_false3: bool,
        flag_false4: bool,

        const env = .{
            .flag_false1 = "FLAG_FALSE1",
            .flag_false2 = "FLAG_FALSE2",
            .flag_false3 = "FLAG_FALSE3",
            .flag_false4 = "FLAG_FALSE4",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "FLAG_FALSE1", .value = "false" },
        .{ .key = "FLAG_FALSE2", .value = "0" },
        .{ .key = "FLAG_FALSE3", .value = "no" },
        .{ .key = "FLAG_FALSE4", .value = "anything_else" },
    });
    defer env_map.deinit();

    const config = try loadMap(BoolConfig, env_map, allocator);
    try std.testing.expect(!config.flag_false1);
    try std.testing.expect(!config.flag_false2);
    try std.testing.expect(!config.flag_false3);
    try std.testing.expect(!config.flag_false4);
}
