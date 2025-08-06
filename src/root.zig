const std = @import("std");

pub const SysError = error{Err};

pub fn writeStats(w: std.io.AnyWriter, timezone_offset: isize) !void {
    try writeSysInfoStats(w, " | ");
    try w.writeAll(" | ");
    try writeMemStats(w);
    try w.writeAll(" | ");
    try writeBatteryStats(w);
    try w.writeAll(" | ");
    try writeTimeStats(w, timezone_offset);
    try w.writeByte('\n');
}

fn writeSysInfoStats(w: std.io.AnyWriter, separator: []const u8) !void {
    const sysinfo = try sysInfo();
    try writeUptime(w, sysinfo.uptime);
    try w.writeAll(separator);
    try writeLoads(w, sysinfo.loads);
}

const MemStats = struct {
    available: usize,
    total: usize,
};

fn writeMemStats(w: std.io.AnyWriter) !void {
    const mem_stats = try memStats();
    const percentUsed = @divTrunc((mem_stats.total - mem_stats.available) * 100, mem_stats.total);
    try std.fmt.format(w, "mem: {d}%", .{percentUsed});
}

fn memStats() !MemStats {
    const meminfo_path = "/proc/meminfo";
    const f = try std.fs.openFileAbsolute(meminfo_path, .{ .mode = .read_only });
    defer f.close();
    const reader = f.reader();
    const buf_size = 100;
    var buf: [buf_size]u8 = undefined;
    const line_starts: [2][]const u8 = .{
        "MemTotal:",
        "MemAvailable:",
    };
    var stats: [line_starts.len]usize = undefined;

    while (true) {
        const line = try reader.readUntilDelimiterOrEof(buf[0..], '\n');
        if (line) |l| {
            for (line_starts, 0..) |start, i| {
                if (std.mem.startsWith(u8, l, start)) {
                    const str_val = std.mem.trim(u8, l[start.len + 1 ..], " \n");
                    var split = std.mem.splitSequence(u8, str_val, " ");
                    const val = try std.fmt.parseInt(usize, split.first(), 10);
                    const unit = split.next() orelse unreachable;
                    std.debug.assert(split.rest().len == 0);
                    stats[i] = val * mulitplierFromUnit(unit);
                }
            }
        } else break;
    }

    return .{
        .total = stats[0],
        .available = stats[1],
    };
}

fn mulitplierFromUnit(unit: []const u8) usize {
    if (std.mem.eql(u8, unit, "kB")) {
        return 1024;
    } else unreachable;
}

fn writeBatteryStats(w: std.io.AnyWriter) !void {
    try w.writeAll("battery: ");
    try writeBatteryCapacity(w);
    try w.writeAll("% ");
    try writeBatteryStatus(w);
}

fn writeBatteryCapacity(w: std.io.AnyWriter) !void {
    const batCapacityPath = "/sys/class/power_supply/BAT0/capacity";
    const f = try std.fs.openFileAbsolute(batCapacityPath, .{ .mode = .read_only });
    defer f.close();
    const reader = f.reader();
    const buf_size = 100;
    var buf: [buf_size]u8 = undefined;
    const bytes_read = try reader.readUntilDelimiter(&buf, '\n');
    try w.writeAll(bytes_read);
}

fn writeBatteryStatus(w: std.io.AnyWriter) !void {
    const batStatusPath = "/sys/class/power_supply/BAT0/status";
    const f = try std.fs.openFileAbsolute(batStatusPath, .{ .mode = .read_only });
    defer f.close();
    const reader = f.reader();
    const buf_size = 100;
    var buf: [buf_size]u8 = undefined;
    const bytes_read = try reader.readUntilDelimiter(&buf, '\n');
    try w.writeAll(bytes_read);
}

fn writeTimeStats(w: std.io.AnyWriter, timezone_offset: isize) !void {
    const timestamp = std.time.timestamp() + timezone_offset;
    const epoch_secs: u64 = @intCast(timestamp);
    const epoch_day = std.time.epoch.EpochDay{ .day = @intCast(epoch_secs / std.time.s_per_day) };
    const day_secs = std.time.epoch.DaySeconds{ .secs = @intCast(epoch_secs % std.time.s_per_day) };
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const year = year_day.year;
    const month = month_day.month.numeric();
    const day = month_day.day_index + 1; // day_index is zero-indexed so we have to add 1 to get the date
    const hour = day_secs.getHoursIntoDay();
    const minute = day_secs.getMinutesIntoHour();
    const sec = day_secs.getSecondsIntoMinute();
    try std.fmt.format(w, "{d}.{d:02}.{d:02} {d:02}:{d:02}:{d:02}", .{ year, month, day, hour, minute, sec });
}

fn sysInfo() !std.os.linux.Sysinfo {
    var info: std.os.linux.Sysinfo = undefined;
    try checkSysCallResult(std.os.linux.sysinfo(&info));
    return info;
}

fn writeUptime(w: std.io.AnyWriter, secs: isize) !void {
    try w.writeAll("up ");
    try writeTimeFromSecs(w, secs);
}

fn writeTimeFromSecs(w: std.io.AnyWriter, secs: isize) !void {
    const unit, const divisor: isize = switch (secs) {
        0...59 => .{ "seconds", 1 },
        60...3599 => .{ "minutes", 60 },
        3600...86399 => .{ "hours", 3600 },
        else => .{ "days", 86400 },
    };
    return std.fmt.format(w, "{} {s}", .{ @divTrunc(secs, divisor), unit });
}

fn checkSysCallResult(result: usize) !void {
    if (result > @as(usize, @bitCast(@as(isize, -4096)))) {
        // TODO: come back and do something with the actual errno
        // const errno = @as(i32, @bitCast(@as(u32, @truncate(result))));
        return SysError.Err;
    }
}

fn writeLoads(w: std.io.AnyWriter, loads: [3]usize) !void {
    const load1 = loads[0];
    const load5 = loads[1];
    const load15 = loads[2];
    return std.fmt.format(w, "load 1={d:.2} 5={d:.2} 15={d:.2}", .{
        floatifyLoad(load1),
        floatifyLoad(load5),
        floatifyLoad(load15),
    });
}

// load values are returned as an integer factored by 65536 to avoid any kind
// of floating point math in the kernel. This function converts these values
// to human-understandable laod values
fn floatifyLoad(loadInt: usize) f64 {
    return @as(f64, @floatFromInt(loadInt)) / 65536.0;
}
