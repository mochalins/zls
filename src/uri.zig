const std = @import("std");
const builtin = @import("builtin");

/// Returns a file URI from a path.
/// Caller owns the returned memory
pub fn fromPath(allocator: std.mem.Allocator, path: []const u8) error{OutOfMemory}![]u8 {
    if (path.len == 0) return try allocator.dupe(u8, "/");
    const prefix = if (builtin.os.tag == .windows) "file:///" else "file://";

    var buf: std.ArrayListUnmanaged(u8) = try .initCapacity(allocator, prefix.len + path.len);
    errdefer buf.deinit(allocator);

    buf.appendSliceAssumeCapacity(prefix);

    var start: usize = 0;
    for (path, 0..) |char, index| {
        switch (char) {
            // zig fmt: off
            'A'...'Z',
            'a'...'z',
            '0'...'9',
            '-', '.', '_', '~', '!',
            '$', '&', '\'','(', ')',
            '+', ',', ';', '=', '@',
            // zig fmt: on
            => continue,
            ':', '*' => if (builtin.os.tag != .windows) continue,
            else => {},
        }

        try buf.appendSlice(allocator, path[start..index]);
        if (std.fs.path.isSep(char)) {
            try buf.append(allocator, '/');
        } else {
            try buf.print(allocator, "%{X:0>2}", .{char});
        }
        start = index + 1;
    }
    try buf.appendSlice(allocator, path[start..]);

    // On windows, we need to lowercase the drive name.
    if (builtin.os.tag == .windows) {
        if (buf.items.len > prefix.len + 1 and
            std.ascii.isAlphanumeric(buf.items[prefix.len]) and
            std.mem.startsWith(u8, buf.items[prefix.len + 1 ..], "%3A"))
        {
            buf.items[prefix.len] = std.ascii.toLower(buf.items[prefix.len]);
        }
    }

    return buf.toOwnedSlice(allocator);
}

test fromPath {
    if (builtin.os.tag == .windows) {
        const fromPathWin = try fromPath(std.testing.allocator, "C:\\main.zig");
        defer std.testing.allocator.free(fromPathWin);
        try std.testing.expectEqualStrings("file:///c%3A/main.zig", fromPathWin);
    }

    if (builtin.os.tag != .windows) {
        const fromPathUnix = try fromPath(std.testing.allocator, "/home/main.zig");
        defer std.testing.allocator.free(fromPathUnix);
        try std.testing.expectEqualStrings("file:///home/main.zig", fromPathUnix);
    }
}

/// Parses a Uri and returns the unescaped path
/// Caller owns the returned memory
pub fn parse(allocator: std.mem.Allocator, str: []const u8) (std.Uri.ParseError || error{ UnsupportedScheme, OutOfMemory })![]u8 {
    var uri = try std.Uri.parse(str);
    if (!std.mem.eql(u8, uri.scheme, "file")) return error.UnsupportedScheme;
    if (builtin.os.tag == .windows and uri.path.percent_encoded.len != 0 and uri.path.percent_encoded[0] == '/') {
        uri.path.percent_encoded = uri.path.percent_encoded[1..];
    }
    var aw: std.io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    uri.path.formatRaw(&aw.writer) catch return error.OutOfMemory;
    return try aw.toOwnedSlice();
}
