# @xarunoba/env-struct 🌱

![Static Badge](https://img.shields.io/badge/Made_with-%E2%9D%A4%EF%B8%8F-red?style=for-the-badge) ![Static Badge](https://img.shields.io/badge/Zig-0.14.1-orange?style=for-the-badge&logo=zig) ![GitHub License](https://img.shields.io/github/license/xarunoba/env-struct?style=for-the-badge)

**`env-struct`** — environment variables to typed structs

A Zig library for parsing environment variables directly into typed structs, providing automatic type conversion and validation. (Note: This library does not read environment variables from files; it only parses existing environment variables into a struct.)

## Why

Managing configuration with environment variables is common, but environment variables are always strings and require manual parsing and validation. `env-struct` eliminates boilerplate by mapping environment variables directly to typed Zig structs, providing automatic type conversion and validation at load time. This approach improves safety, reduces errors, and makes configuration handling more robust and maintainable.

## Features

- ✅ **Type-safe**: Automatically parse environment variables into the correct types
- ✅ **Multiple types**: Strings, integers, floats, booleans, and nested structs
- ✅ **Optional fields**: Support for optional fields with defaults
- ✅ **Flexible mapping**: Fields map to their names by default, optional custom mapping
- ✅ **Skip fields**: Map fields to "-" to explicitly skip environment variable lookup
- ✅ **Flexible boolean parsing**: Parse "true", "1", "yes" (case-insensitive) as true
- ✅ **Custom environment maps**: Load from custom maps for testing

## Installation

Add this library to your project using `zig fetch`:

```bash
zig fetch --save "git+https://github.com/xarunoba/env-struct#main"
```

Then in your `build.zig`:

```zig
const env_struct = b.dependency("env_struct", .{});
exe.root_module.addImport("env_struct", env_struct.module("env_struct"));
```

## Usage

```zig
const std = @import("std");
const env_struct = @import("env_struct");

const Config = struct {
    APP_NAME: []const u8,    // Maps to "APP_NAME" env var
    PORT: u32,               // Maps to "PORT" env var
    DEBUG: bool = false,     // Maps to "DEBUG" env var, defaults to false
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try env_struct.load(Config, allocator);
    
    std.debug.print("App: {s}\n", .{config.APP_NAME});
    std.debug.print("Port: {}\n", .{config.PORT});
}
```

Set environment variables:
```bash
export APP_NAME="My App"
export PORT="8080"
```

### Custom Mapping

```zig
const Config = struct {
    name: []const u8,
    port: u32,
    debug: bool = false,
    timeout: ?f32 = null,

    const env = .{
        .name = "APP_NAME",
        .port = "PORT",
        .debug = "DEBUG",
        .timeout = "TIMEOUT",
    };
};

const config = try env_struct.load(Config, allocator);
```

Set environment variables:
```bash
export APP_NAME="My App"
export PORT="8080"
```

### Advanced Usage

```zig
const Config = struct {
    app_name: []const u8,           // Maps to "app_name" env var
    custom_port: u32,               // Maps to "PORT" env var (custom mapping)
    debug: bool = false,            // Maps to "debug" env var, uses default
    internal_field: []const u8 = "computed",  // Skipped from env lookup
    optional_feature: ?u32,         // Maps to "optional_feature", can be null

    const env = .{
        .custom_port = "PORT",      // Custom environment variable name
        .internal_field = "-",      // Skip environment variable lookup
    };
};
```

### Nested Structs & Custom Environment Maps

```zig
const DatabaseConfig = struct {
    host: []const u8,
    port: u32 = 5432,

    const env = .{
        .host = "DB_HOST",
        .port = "DB_PORT",
    };
};

const ServerConfig = struct {
    host: []const u8 = "localhost",
    port: u32,
    database: DatabaseConfig,

    const env = .{
        .host = "SERVER_HOST",
        .port = "SERVER_PORT",
    };
};

// Load from system environment
const config = try env_struct.load(ServerConfig, allocator);

// Or load from custom environment map (useful for testing)
var custom_env = std.process.EnvMap.init(allocator);
defer custom_env.deinit();
try custom_env.put("SERVER_PORT", "3000");
const test_config = try env_struct.loadMap(ServerConfig, custom_env, allocator);
```

## Mapping Rules

Fields are mapped to environment variables with these behaviors:

- **Default mapping**: Fields automatically map to environment variables with the same name
- **Custom mapping**: Use the `env` declaration to map fields to different environment variable names  
- **Skip mapping**: Map a field to `"-"` to skip environment variable lookup (must have default values or be optional)
- **Field requirements**: Fields without default values must either have corresponding environment variables or be optional
- **Optional env declaration**: The `env` declaration is only needed for custom mappings or skipping fields

```zig
const Config = struct {
    app_name: []const u8,           // Maps to "app_name" env var
    custom_port: u32,               // Maps to "PORT" env var  
    skipped_field: []const u8 = "default",  // No env var lookup
    
    const env = .{
        .custom_port = "PORT",      // Custom mapping
        .skipped_field = "-",       // Skip mapping
        // app_name uses default mapping
    };
};
```

## Supported Types

| Type | Examples | Notes |
|------|----------|-------|
| `[]const u8` | `"hello"` | String values |
| `i8`, `i16`, `i32`, `i64`, `i128`, `isize` | `"42"`, `"-123"` | Signed integers |
| `u8`, `u16`, `u32`, `u64`, `u128`, `usize` | `"42"`, `"255"` | Unsigned integers |
| `f32`, `f64` | `"3.14"` | Floating point |
| `bool` | `"true"`, `"1"`, `"yes"` | Case-insensitive |
| `?T` | Any valid `T` or missing | Optional types |
| `struct` | N/A | Nested structs |

## API

### `load(comptime T: type, allocator: std.mem.Allocator) !T`
Load configuration from system environment variables.

### `loadMap(comptime T: type, env_map: std.process.EnvMap, allocator: std.mem.Allocator) !T`
Load configuration from a custom environment map.

## Building

```bash
zig build
```

## Testing

```bash
zig test src/env_struct.zig
```