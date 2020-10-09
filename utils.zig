const std = @import("std");

const Colors = enum(u8) {
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,
    default = 39,
};

/// Prints to stderr instead of stdout so that we can pipe stdout
///  normally, without the color codes being piped out as well.
pub fn setColor(color: Colors) void {
    const escape = [2]u8{ 27, 91 };
    print(escape ++ "{}m", .{@enumToInt(color)});
}

pub fn noOpSetColor(color: Colors) void {}

const stdout = std.io.getStdOut().outStream();
pub fn print(comptime fmt: []const u8, args: anytype) void {
    stdout.print(fmt, args) catch unreachable;
}

pub fn insertionSort(comptime T: type, arr: []T) void {
    var i: usize = 1;
    while (i < arr.len) : (i += 1) {
        var j = i;
        while (j > 0 and arr[j - 1].time > arr[j].time) : (j -= 1) {
            // Swap elements
            const temp = arr[j - 1];
            arr[j - 1] = arr[j];
            arr[j] = temp;
        }
    }
}

pub fn eql(a: [*:0]u8, b: []const u8) bool {
    return std.mem.eql(u8, std.mem.spanZ(a), b);
}
