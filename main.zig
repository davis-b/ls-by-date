const std = @import("std");
const os = std.os;

const Args = struct {
    dir: []const u8 = "./",
    reverse: bool = false,
    recursive: bool = false,
};

const File = struct {
    time: isize,
    path: []const u8,
    kind: std.fs.Dir.Entry.Kind,
};

pub fn main() !void {
    //
}
