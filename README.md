# @xarunoba/env-struct 🌱

![Static Badge](https://img.shields.io/badge/Made_with-%E2%9D%A4%EF%B8%8F-red?style=for-the-badge) ![Static Badge](https://img.shields.io/badge/Zig-0.14.1-orange?style=for-the-badge&logo=zig) ![GitHub License](https://img.shields.io/github/license/xarunoba/env-struct?style=for-the-badge)

**`env-struct`** — environment variables to typed structs

A Zig library for loading configuration from environment variables into typed structs with automatic parsing and validation. (Note: This library does not load environment variables from files. This only parses environment variables into a struct.)

## Why

Managing configuration in applications often involves dealing with environment variables that are just strings. This library provides a type-safe way to parse those environment variables into proper Zig types, ensuring your configuration is validated at load time and reducing runtime errors.

## Features

- ✅ **Type-safe**: Automatically parse environment variables into the correct types
- ✅ **Multiple types**: Strings, integers, floats, booleans, and nested structs
- ✅ **Optional fields**: Support for optional fields with defaults
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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try env_struct.load(Config, allocator);
    
    std.debug.print("App: {s}\n", .{config.name});
    std.debug.print("Port: {}\n", .{config.port});
}
```

Set environment variables:
```bash
export APP_NAME="My App"
export PORT="8080"
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

## Supported Types

| Type | Examples | Notes |
|------|----------|-------|
| `[]const u8` | `"hello"` | String values |
| `i32`, `u32`, `i64`, `u64` | `"42"`, `"-123"` | Integers |
| `f32`, `f64` | `"3.14"` | Floating point |
| `bool` | `"true"`, `"1"`, `"yes"` | Case-insensitive |
| `?T` | Any valid `T` or missing | Optional types |
| `struct` | N/A | Nested structs |

## API

### `load(comptime T: type, allocator: std.mem.Allocator) !T`
Load configuration from system environment variables.

### `loadMap(comptime T: type, env_map: std.process.EnvMap, allocator: std.mem.Allocator) !T`
Load configuration from a custom environment map.

## Requirements

Your struct must have an `env` declaration mapping field names to environment variable names:

```zig
const Config = struct {
    name: []const u8,        // Required - must have APP_NAME env var
    port: ?u32,              // Optional - can be missing
    timeout: f32 = 30.0,     // Has default - uses default if missing
    version: []const u8 = "1.0.0",  // Not mapped - must have default

    const env = .{
        .name = "APP_NAME",
        .port = "PORT", 
        .timeout = "TIMEOUT",
        // version not mapped, uses default
    };
};
```

## Building

```bash
zig build
```

## Testing

```bash
zig test src/env_struct.zig
```