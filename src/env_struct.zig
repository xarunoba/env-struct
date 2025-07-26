//! Parse environment variables directly into typed Zig structs.
//!
//! Provides automatic type conversion and validation for strings, integers,
//! floats, booleans, and nested structs with support for optional fields,
//! custom mapping, and default values.
//!
//! Author: @xarunoba
//! Repository: https://github.com/xarunoba/env-struct.zig
//! License: MIT

const std = @import("std");

//==============================================================================
// Public API
//==============================================================================

pub fn load(comptime T: type, allocator: std.mem.Allocator) !T {
    return try loadCore(T, null, allocator);
}

pub fn loadMap(comptime T: type, env_map: std.process.EnvMap, allocator: std.mem.Allocator) !T {
    return try loadCore(T, env_map, allocator);
}

//==============================================================================
// Internal Functions
//==============================================================================

fn hasAnyEnvVars(comptime T: type, env_map: std.process.EnvMap) bool {
    const type_info = @typeInfo(T);
    if (type_info != .@"struct") return false;

    inline for (type_info.@"struct".fields) |field| {
        const env_key: ?[]const u8 = if (@hasDecl(T, "env") and @hasField(@TypeOf(T.env), field.name)) blk: {
            const mapped_key = @field(T.env, field.name);
            if (std.mem.eql(u8, mapped_key, "-")) {
                break :blk null;
            }
            break :blk mapped_key;
        } else field.name;

        const field_type_info = @typeInfo(field.type);

        if (env_key != null) {
            if (env_map.get(env_key.?)) |_| {
                return true;
            }
        }

        // Check nested structs recursively
        if (field_type_info == .@"struct") {
            if (hasAnyEnvVars(field.type, env_map)) {
                return true;
            }
        } else if (field_type_info == .optional) {
            const child_type = field_type_info.optional.child;
            const child_type_info = @typeInfo(child_type);
            if (child_type_info == .@"struct") {
                if (hasAnyEnvVars(child_type, env_map)) {
                    return true;
                }
            }
        }
    }
    return false;
}

fn parseValue(comptime FieldType: type, val: []const u8, env_map: ?std.process.EnvMap, allocator: std.mem.Allocator) !FieldType {
    const field_type_info = @typeInfo(FieldType);

    switch (field_type_info) {
        .@"struct" => {
            return try loadCore(FieldType, env_map, allocator);
        },
        else => {
            switch (FieldType) {
                []const u8 => return val,
                i8 => return try std.fmt.parseInt(i8, val, 10),
                i16 => return try std.fmt.parseInt(i16, val, 10),
                i32 => return try std.fmt.parseInt(i32, val, 10),
                i64 => return try std.fmt.parseInt(i64, val, 10),
                i128 => return try std.fmt.parseInt(i128, val, 10),
                isize => return try std.fmt.parseInt(isize, val, 10),
                u8 => return try std.fmt.parseInt(u8, val, 10),
                u16 => return try std.fmt.parseInt(u16, val, 10),
                u32 => return try std.fmt.parseInt(u32, val, 10),
                u64 => return try std.fmt.parseInt(u64, val, 10),
                u128 => return try std.fmt.parseInt(u128, val, 10),
                usize => return try std.fmt.parseInt(usize, val, 10),
                f16 => return try std.fmt.parseFloat(f16, val),
                f32 => return try std.fmt.parseFloat(f32, val),
                f64 => return try std.fmt.parseFloat(f64, val),
                f80 => return try std.fmt.parseFloat(f80, val),
                f128 => return try std.fmt.parseFloat(f128, val),
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

    var owned_env_map: ?std.process.EnvMap = null;
    defer if (owned_env_map) |*map| map.deinit();

    const active_env_map = if (env_map) |map| map else blk: {
        owned_env_map = try std.process.getEnvMap(allocator);
        break :blk owned_env_map.?;
    };

    inline for (type_info.@"struct".fields) |field| {
        const env_key: ?[]const u8 = if (@hasDecl(T, "env") and @hasField(@TypeOf(T.env), field.name)) blk: {
            const mapped_key = @field(T.env, field.name);
            if (std.mem.eql(u8, mapped_key, "-")) {
                break :blk null;
            }
            break :blk mapped_key;
        } else field.name;

        const field_type_info = @typeInfo(field.type);
        const is_optional = field_type_info == .optional;
        const default_value = field.defaultValue();

        if (field_type_info == .@"struct") {
            @field(result, field.name) = try parseValue(field.type, "", env_map, allocator);
        } else if (is_optional) {
            const child_type = field_type_info.optional.child;
            const child_type_info = @typeInfo(child_type);
            if (child_type_info == .@"struct") {
                if (hasAnyEnvVars(child_type, active_env_map)) {
                    @field(result, field.name) = try parseValue(child_type, "", env_map, allocator);
                } else if (default_value) |def_val| {
                    @field(result, field.name) = def_val;
                } else {
                    @field(result, field.name) = null;
                }
            } else if (env_key) |key| {
                const value = active_env_map.get(key);
                if (value) |val| {
                    @field(result, field.name) = try parseValue(child_type, val, env_map, allocator);
                } else if (default_value) |def_val| {
                    @field(result, field.name) = def_val;
                } else {
                    @field(result, field.name) = null;
                }
            } else {
                if (default_value) |def_val| {
                    @field(result, field.name) = def_val;
                } else {
                    @field(result, field.name) = null;
                }
            }
        } else if (env_key) |key| {
            const value = active_env_map.get(key);
            if (value) |val| {
                @field(result, field.name) = try parseValue(field.type, val, env_map, allocator);
            } else {
                if (default_value) |def_val| {
                    @field(result, field.name) = def_val;
                } else {
                    return error.MissingEnvironmentVariable;
                }
            }
        } else {
            if (default_value) |def_val| {
                @field(result, field.name) = def_val;
            } else {
                const field_type_info_check = @typeInfo(field.type);
                if (field_type_info_check == .optional) {
                    @field(result, field.name) = null;
                } else {
                    return error.MissingEnvironmentVariable;
                }
            }
        }
    }

    return result;
}

//==============================================================================
// Test Utilities
//==============================================================================

fn createTestEnvMap(allocator: std.mem.Allocator, env_vars: []const struct { key: []const u8, value: []const u8 }) !std.process.EnvMap {
    var env_map = std.process.EnvMap.init(allocator);
    for (env_vars) |env_var| {
        try env_map.put(env_var.key, env_var.value);
    }
    return env_map;
}

//==============================================================================
// Tests
//==============================================================================

test "parse primitive types" {
    const TestConfig = struct {
        name: []const u8,
        port: u32,
        timeout: i32,
        big_num: u64,
        negative: i64,
        ratio: f32,
        precision: f64,
        debug: bool,
        verbose: bool,
        enabled: bool,
        disabled: bool,
        flag_true1: bool,
        flag_true2: bool,
        flag_true3: bool,
        flag_true4: bool,
        flag_true5: bool,
        flag_false1: bool,
        flag_false2: bool,
        flag_false3: bool,
        flag_false4: bool,
        val_i8: i8,
        val_i16: i16,
        val_i32: i32,
        val_i64: i64,
        val_i128: i128,
        val_isize: isize,
        val_u8: u8,
        val_u16: u16,
        val_u32: u32,
        val_u64: u64,
        val_u128: u128,
        val_usize: usize,
        val_f16: f16,
        val_f80: f80,
        val_f128: f128,
        database_url_upper: []const u8,
        database_url_lower: []const u8,

        const env = .{
            .name = "TEST_NAME",
            .port = "TEST_PORT",
            .timeout = "TEST_TIMEOUT",
            .big_num = "TEST_BIG_NUM",
            .negative = "TEST_NEGATIVE",
            .ratio = "TEST_RATIO",
            .precision = "TEST_PRECISION",
            .debug = "TEST_DEBUG",
            .verbose = "TEST_VERBOSE",
            .enabled = "TEST_ENABLED",
            .disabled = "TEST_DISABLED",
            .flag_true1 = "FLAG_TRUE1",
            .flag_true2 = "FLAG_TRUE2",
            .flag_true3 = "FLAG_TRUE3",
            .flag_true4 = "FLAG_TRUE4",
            .flag_true5 = "FLAG_TRUE5",
            .flag_false1 = "FLAG_FALSE1",
            .flag_false2 = "FLAG_FALSE2",
            .flag_false3 = "FLAG_FALSE3",
            .flag_false4 = "FLAG_FALSE4",
            .val_i8 = "VAL_I8",
            .val_i16 = "VAL_I16",
            .val_i32 = "VAL_I32",
            .val_i64 = "VAL_I64",
            .val_i128 = "VAL_I128",
            .val_isize = "VAL_ISIZE",
            .val_u8 = "VAL_U8",
            .val_u16 = "VAL_U16",
            .val_u32 = "VAL_U32",
            .val_u64 = "VAL_U64",
            .val_u128 = "VAL_U128",
            .val_usize = "VAL_USIZE",
            .val_f16 = "VAL_F16",
            .val_f80 = "VAL_F80",
            .val_f128 = "VAL_F128",
            .database_url_upper = "DATABASE_URL",
            .database_url_lower = "database_url",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "TEST_NAME", .value = "hello world" },
        .{ .key = "TEST_PORT", .value = "8080" },
        .{ .key = "TEST_TIMEOUT", .value = "30" },
        .{ .key = "TEST_BIG_NUM", .value = "18446744073709551615" },
        .{ .key = "TEST_NEGATIVE", .value = "-42" },
        .{ .key = "TEST_RATIO", .value = "3.14" },
        .{ .key = "TEST_PRECISION", .value = "2.718281828459045" },
        .{ .key = "TEST_DEBUG", .value = "true" },
        .{ .key = "TEST_VERBOSE", .value = "1" },
        .{ .key = "TEST_ENABLED", .value = "YES" },
        .{ .key = "TEST_DISABLED", .value = "false" },
        .{ .key = "FLAG_TRUE1", .value = "true" },
        .{ .key = "FLAG_TRUE2", .value = "TRUE" },
        .{ .key = "FLAG_TRUE3", .value = "1" },
        .{ .key = "FLAG_TRUE4", .value = "yes" },
        .{ .key = "FLAG_TRUE5", .value = "YES" },
        .{ .key = "FLAG_FALSE1", .value = "false" },
        .{ .key = "FLAG_FALSE2", .value = "0" },
        .{ .key = "FLAG_FALSE3", .value = "no" },
        .{ .key = "FLAG_FALSE4", .value = "anything_else" },
        .{ .key = "VAL_I8", .value = "-128" },
        .{ .key = "VAL_I16", .value = "-32768" },
        .{ .key = "VAL_I32", .value = "-2147483648" },
        .{ .key = "VAL_I64", .value = "-9223372036854775808" },
        .{ .key = "VAL_I128", .value = "-170141183460469231731687303715884105728" },
        .{ .key = "VAL_ISIZE", .value = "-1000" },
        .{ .key = "VAL_U8", .value = "255" },
        .{ .key = "VAL_U16", .value = "65535" },
        .{ .key = "VAL_U32", .value = "4294967295" },
        .{ .key = "VAL_U64", .value = "18446744073709551615" },
        .{ .key = "VAL_U128", .value = "340282366920938463463374607431768211455" },
        .{ .key = "VAL_USIZE", .value = "1000" },
        .{ .key = "VAL_F16", .value = "0.333" },
        .{ .key = "VAL_F80", .value = "3.141592653589793" },
        .{ .key = "VAL_F128", .value = "2.71828182845904523536028747135266250" },
        .{ .key = "database_url", .value = "postgres://lower" },
    });
    defer env_map.deinit();
    const config = try loadMap(TestConfig, env_map, allocator);

    try std.testing.expectEqualStrings("hello world", config.name);
    try std.testing.expectEqual(@as(u32, 8080), config.port);
    try std.testing.expectEqual(@as(i32, 30), config.timeout);
    try std.testing.expectEqual(@as(u64, 18446744073709551615), config.big_num);
    try std.testing.expectEqual(@as(i64, -42), config.negative);
    try std.testing.expectApproxEqAbs(@as(f32, 3.14), config.ratio, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 2.718281828459045), config.precision, 0.000000000000001);
    try std.testing.expect(config.debug);
    try std.testing.expect(config.verbose);
    try std.testing.expect(config.enabled);
    try std.testing.expect(!config.disabled);
    try std.testing.expect(config.flag_true1);
    try std.testing.expect(config.flag_true2);
    try std.testing.expect(config.flag_true3);
    try std.testing.expect(config.flag_true4);
    try std.testing.expect(config.flag_true5);
    try std.testing.expect(!config.flag_false1);
    try std.testing.expect(!config.flag_false2);
    try std.testing.expect(!config.flag_false3);
    try std.testing.expect(!config.flag_false4);
    try std.testing.expectEqual(@as(i8, -128), config.val_i8);
    try std.testing.expectEqual(@as(i16, -32768), config.val_i16);
    try std.testing.expectEqual(@as(i32, -2147483648), config.val_i32);
    try std.testing.expectEqual(@as(i64, -9223372036854775808), config.val_i64);
    try std.testing.expectEqual(@as(i128, -170141183460469231731687303715884105728), config.val_i128);
    try std.testing.expectEqual(@as(isize, -1000), config.val_isize);
    try std.testing.expectEqual(@as(u8, 255), config.val_u8);
    try std.testing.expectEqual(@as(u16, 65535), config.val_u16);
    try std.testing.expectEqual(@as(u32, 4294967295), config.val_u32);
    try std.testing.expectEqual(@as(u64, 18446744073709551615), config.val_u64);
    try std.testing.expectEqual(@as(u128, 340282366920938463463374607431768211455), config.val_u128);
    try std.testing.expectEqual(@as(usize, 1000), config.val_usize);
    try std.testing.expectApproxEqAbs(@as(f16, 0.333), config.val_f16, 0.001);
    try std.testing.expectApproxEqAbs(@as(f80, 3.141592653589793), config.val_f80, 1e-15);
    try std.testing.expectApproxEqAbs(@as(f128, 2.71828182845904523536028747135266250), config.val_f128, 1e-30);

    if (@import("builtin").os.tag == .windows) {
        try std.testing.expect(config.database_url_upper.len > 0);
        try std.testing.expect(config.database_url_lower.len > 0);
    } else {
        try std.testing.expectEqualStrings("postgres://upper", config.database_url_upper);
        try std.testing.expectEqualStrings("postgres://lower", config.database_url_lower);
    }
}

test "optional and default value handling" {
    const TestConfig = struct {
        required: []const u8,
        optional_present: ?[]const u8,
        optional_missing: ?i32,
        default_used: u32 = 3000,
        default_overridden: bool = false,
        optional_with_default: ?i32 = 100,

        const env = .{
            .required = "TEST_REQUIRED",
            .optional_present = "TEST_OPTIONAL_PRESENT",
            .optional_missing = "TEST_OPTIONAL_MISSING",
            .default_used = "TEST_DEFAULT_USED",
            .default_overridden = "TEST_DEFAULT_OVERRIDDEN",
            .optional_with_default = "TEST_OPTIONAL_WITH_DEFAULT",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "TEST_REQUIRED", .value = "must be here" },
        .{ .key = "TEST_OPTIONAL_PRESENT", .value = "i am here" },
        .{ .key = "TEST_DEFAULT_OVERRIDDEN", .value = "true" },
    });
    defer env_map.deinit();

    const config = try loadMap(TestConfig, env_map, allocator);
    try std.testing.expectEqualStrings("must be here", config.required);
    try std.testing.expectEqualStrings("i am here", config.optional_present.?);
    try std.testing.expectEqual(@as(?i32, null), config.optional_missing);
    try std.testing.expectEqual(@as(u32, 3000), config.default_used);
    try std.testing.expect(config.default_overridden);
    try std.testing.expectEqual(@as(?i32, 100), config.optional_with_default);
}

test "field mapping and skipping" {
    const TestConfig = struct {
        mapped_field: []const u8,
        unmapped_field: []const u8 = "default",
        skipped_field: []const u8 = "default_value",
        skipped_optional: ?[]const u8,
        skipped_with_default: ?u32 = 42,

        const env = .{
            .mapped_field = "MAPPED_FIELD",
            .skipped_field = "-",
            .skipped_optional = "-",
            .skipped_with_default = "-",
        };
    };

    const allocator = std.testing.allocator;

    var env_map = try createTestEnvMap(allocator, &.{
        .{ .key = "MAPPED_FIELD", .value = "mapped_value" },
        .{ .key = "unmapped_field", .value = "env_value" },
        .{ .key = "skipped_field", .value = "should_not_be_used" },
        .{ .key = "skipped_optional", .value = "should_not_be_used" },
        .{ .key = "skipped_with_default", .value = "999" },
    });
    defer env_map.deinit();

    const config = try loadMap(TestConfig, env_map, allocator);
    try std.testing.expectEqualStrings("mapped_value", config.mapped_field);
    try std.testing.expectEqualStrings("env_value", config.unmapped_field);
    try std.testing.expectEqualStrings("default_value", config.skipped_field);
    try std.testing.expectEqual(@as(?[]const u8, null), config.skipped_optional);
    try std.testing.expectEqual(@as(?u32, 42), config.skipped_with_default);
}

test "nested struct parsing" {
    const MetricsConfig = struct {
        enabled: bool,
        port: u32 = 9090,
        timeout: u32 = 5000,

        const env = .{
            .enabled = "METRICS_ENABLED",
            .port = "METRICS_PORT",
            .timeout = "METRICS_TIMEOUT",
        };
    };

    const LoggingConfig = struct {
        level: []const u8,
        file_path: ?[]const u8,
        max_size: u32,

        const env = .{
            .level = "LOG_LEVEL",
            .file_path = "LOG_FILE_PATH",
            .max_size = "LOG_MAX_SIZE",
        };
    };

    const MonitoringConfig = struct {
        alert_threshold: f32,
        metrics: ?MetricsConfig,
        logging: LoggingConfig,

        const env = .{
            .alert_threshold = "MONITORING_ALERT_THRESHOLD",
            .metrics = "",
            .logging = "",
        };
    };

    const AppConfig = struct {
        app_name: []const u8,
        version: []const u8,
        monitoring: ?MonitoringConfig,
        debug: bool,

        const env = .{
            .app_name = "APP_NAME",
            .version = "APP_VERSION",
            .monitoring = "",
            .debug = "DEBUG",
        };
    };

    const allocator = std.testing.allocator;

    {
        var env_map = try createTestEnvMap(allocator, &.{
            .{ .key = "APP_NAME", .value = "nested-app" },
            .{ .key = "APP_VERSION", .value = "1.0.0" },
            .{ .key = "DEBUG", .value = "true" },
            .{ .key = "MONITORING_ALERT_THRESHOLD", .value = "95.5" },
            .{ .key = "LOG_LEVEL", .value = "info" },
            .{ .key = "LOG_FILE_PATH", .value = "/var/log/app.log" },
            .{ .key = "LOG_MAX_SIZE", .value = "10485760" },
            .{ .key = "METRICS_ENABLED", .value = "true" },
            .{ .key = "METRICS_PORT", .value = "9090" },
        });
        defer env_map.deinit();
        const config = try loadMap(AppConfig, env_map, allocator);

        try std.testing.expectEqualStrings("nested-app", config.app_name);
        try std.testing.expectEqualStrings("1.0.0", config.version);
        try std.testing.expect(config.debug);

        try std.testing.expect(config.monitoring != null);
        try std.testing.expectApproxEqAbs(@as(f32, 95.5), config.monitoring.?.alert_threshold, 0.001);

        try std.testing.expectEqualStrings("info", config.monitoring.?.logging.level);
        try std.testing.expectEqualStrings("/var/log/app.log", config.monitoring.?.logging.file_path.?);
        try std.testing.expectEqual(@as(u32, 10485760), config.monitoring.?.logging.max_size);

        try std.testing.expect(config.monitoring.?.metrics != null);
        try std.testing.expect(config.monitoring.?.metrics.?.enabled);
        try std.testing.expectEqual(@as(u32, 9090), config.monitoring.?.metrics.?.port);
        try std.testing.expectEqual(@as(u32, 5000), config.monitoring.?.metrics.?.timeout);
    }

    {
        var env_map = try createTestEnvMap(allocator, &.{
            .{ .key = "APP_NAME", .value = "simple-app" },
            .{ .key = "APP_VERSION", .value = "2.0.0" },
            .{ .key = "DEBUG", .value = "false" },
        });
        defer env_map.deinit();

        const config = try loadMap(AppConfig, env_map, allocator);

        try std.testing.expectEqualStrings("simple-app", config.app_name);
        try std.testing.expectEqualStrings("2.0.0", config.version);
        try std.testing.expect(!config.debug);
        try std.testing.expect(config.monitoring == null);
    }

    {
        var env_map = try createTestEnvMap(allocator, &.{
            .{ .key = "APP_NAME", .value = "partial-app" },
            .{ .key = "APP_VERSION", .value = "1.5.0" },
            .{ .key = "DEBUG", .value = "true" },
            .{ .key = "MONITORING_ALERT_THRESHOLD", .value = "80.0" },
            .{ .key = "LOG_LEVEL", .value = "warn" },
            .{ .key = "LOG_MAX_SIZE", .value = "5242880" },
        });
        defer env_map.deinit();

        const config = try loadMap(AppConfig, env_map, allocator);
        try std.testing.expectEqualStrings("partial-app", config.app_name);
        try std.testing.expect(config.monitoring != null);
        try std.testing.expectApproxEqAbs(@as(f32, 80.0), config.monitoring.?.alert_threshold, 0.001);

        try std.testing.expectEqualStrings("warn", config.monitoring.?.logging.level);
        try std.testing.expectEqual(@as(?[]const u8, null), config.monitoring.?.logging.file_path);
        try std.testing.expectEqual(@as(u32, 5242880), config.monitoring.?.logging.max_size);

        try std.testing.expect(config.monitoring.?.metrics == null);
    }

    {
        var env_map = try createTestEnvMap(allocator, &.{
            .{ .key = "APP_NAME", .value = "defaults-app" },
            .{ .key = "APP_VERSION", .value = "3.0.0" },
            .{ .key = "DEBUG", .value = "false" },
            .{ .key = "MONITORING_ALERT_THRESHOLD", .value = "70.0" },
            .{ .key = "LOG_LEVEL", .value = "error" },
            .{ .key = "LOG_MAX_SIZE", .value = "1048576" },
            .{ .key = "METRICS_ENABLED", .value = "false" },
        });
        defer env_map.deinit();

        const config = try loadMap(AppConfig, env_map, allocator);
        try std.testing.expect(config.monitoring != null);
        try std.testing.expect(config.monitoring.?.metrics != null);
        try std.testing.expect(!config.monitoring.?.metrics.?.enabled);
        try std.testing.expectEqual(@as(u32, 9090), config.monitoring.?.metrics.?.port);
        try std.testing.expectEqual(@as(u32, 5000), config.monitoring.?.metrics.?.timeout);
    }

    {
        var env_map = try createTestEnvMap(allocator, &.{
            .{ .key = "APP_NAME", .value = "partial-redis-app" },
            .{ .key = "APP_VERSION", .value = "1.0.0" },
            .{ .key = "DEBUG", .value = "false" },
            .{ .key = "METRICS_TIMEOUT", .value = "3000" },
        });
        defer env_map.deinit();

        const result = loadMap(AppConfig, env_map, allocator);
        try std.testing.expectError(error.MissingEnvironmentVariable, result);
    }
}

test "case sensitivity of mapped keys" {
    const TestConfig = struct {
        value: []const u8,
        const env = .{ .value = "MY_VAR" };
    };
    const allocator = std.testing.allocator;

    var env_map_wrong_case = try createTestEnvMap(allocator, &.{
        .{ .key = "my_var", .value = "some value" },
    });
    defer env_map_wrong_case.deinit();

    // On Windows, environment variable names are case-insensitive
    // On Unix-like systems, they are case-sensitive
    if (@import("builtin").os.tag == .windows) {
        const config = try loadMap(TestConfig, env_map_wrong_case, allocator);
        try std.testing.expectEqualStrings("some value", config.value);
    } else {
        try std.testing.expectError(error.MissingEnvironmentVariable, loadMap(TestConfig, env_map_wrong_case, allocator));
    }

    var env_map_correct_case = try createTestEnvMap(allocator, &.{
        .{ .key = "MY_VAR", .value = "correct value" },
    });
    defer env_map_correct_case.deinit();

    const config = try loadMap(TestConfig, env_map_correct_case, allocator);
    try std.testing.expectEqualStrings("correct value", config.value);
}

test "error handling" {
    const allocator = std.testing.allocator;

    {
        const TestConfig = struct {
            required_field: []const u8,
            const env = .{ .required_field = "MISSING_VAR" };
        };

        var env_map = try createTestEnvMap(allocator, &.{});
        defer env_map.deinit();

        const result = loadMap(TestConfig, env_map, allocator);
        try std.testing.expectError(error.MissingEnvironmentVariable, result);
    }

    {
        const TestConfig = struct {
            port: u32,
            const env = .{ .port = "INVALID_PORT" };
        };

        var env_map = try createTestEnvMap(allocator, &.{
            .{ .key = "INVALID_PORT", .value = "not_a_number" },
        });
        defer env_map.deinit();

        const result = loadMap(TestConfig, env_map, allocator);
        try std.testing.expectError(error.InvalidCharacter, result);
    }

    {
        const TestConfig = struct {
            ratio: f32,
            const env = .{ .ratio = "INVALID_FLOAT" };
        };

        var env_map = try createTestEnvMap(allocator, &.{
            .{ .key = "INVALID_FLOAT", .value = "not_a_float" },
        });
        defer env_map.deinit();

        const result = loadMap(TestConfig, env_map, allocator);
        try std.testing.expectError(error.InvalidCharacter, result);
    }

    {
        const TestConfig = struct {
            required_field: []const u8,
            const env = .{ .required_field = "-" };
        };

        var env_map = try createTestEnvMap(allocator, &.{});
        defer env_map.deinit();

        const result = loadMap(TestConfig, env_map, allocator);
        try std.testing.expectError(error.MissingEnvironmentVariable, result);
    }
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
