const std = @import("std");

const statprint = @import("root.zig");
const timezone_offset = -4 * 3600;

pub fn main() !void {
    var buf = std.io.bufferedWriter(std.io.getStdOut().writer());
    _ = try statprint.writeStats(buf.writer().any(), timezone_offset);
    defer buf.flush() catch |err| {
        std.log.err("Failed to flush buffer: {}", .{err});
    };
}
