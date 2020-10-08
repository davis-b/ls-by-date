const std = @import("std");
const os = std.os;

const utils = @import("utils.zig");
// Shorthand for comparing a [*:0] to a []const u8
const eql = utils.eql;
const print = utils.print;
// Changes terminal output color by printing an escape sequence to stderr.
const setColor = utils.setColor;

const Files = std.ArrayList(File);
const File = struct {
    time: i128,
    name: []const u8,
    kind: std.fs.Dir.Entry.Kind,
};

const Args = struct {
    dir: []const u8 = "./",
    reverse: bool = false,
    recursive: bool = false,
    verbose: bool = false,
};

pub fn main() !void {
    const args = parseArgs(os.argv[1..os.argv.len]) orelse os.exit(2);

    var gp = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = &gp.allocator;
    var arena_allocator = std.heap.ArenaAllocator.init(allocator);
    defer arena_allocator.deinit();
    const arena = &arena_allocator.allocator;

    var files = Files.init(arena);

    if (args.recursive) {
        // Remove trailing '/' from path name.
        const dir = if (std.mem.endsWith(u8, args.dir, "/")) args.dir[0 .. args.dir.len - 1] else args.dir;
        try searchDirRecursively(dir[0..], &files, arena);
    } else {
        try searchDir(args.dir[0..], &files, arena);
    }

    if (args.verbose) {
        std.debug.warn("found {} files\n", .{files.items.len});
    }
    utils.insertionSort(File, files.items);
    if (args.reverse) {
        std.mem.reverse(File, files.items);
    }
    for (files.items) |file| {
        switch (file.kind) {
            .Directory => {
                setColor(.red);
                print("{}", .{file.name});
                setColor(.default);
                print("\n", .{});
            },
            .SymLink => {
                setColor(.green);
                print("{}", .{file.name});
                setColor(.default);
                print("\n", .{});
            },
            .File => {
                print("{}\n", .{file.name});
            },
            else => @panic("unexpected file type!"),
        }
    }
}

fn searchDir(path: []const u8, files: *Files, allocator: *std.mem.Allocator) !void {
    const fd = try os.open(path, 0, os.O_RDONLY);
    defer os.close(fd);
    var dir = std.fs.Dir{ .fd = fd };
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .File, .Directory, .SymLink => {
                const file = dir.openFile(entry.name, .{}) catch |err| switch (err) {
                    error.AccessDenied => continue,
                    else => return err,
                };
                defer file.close();
                const stat = try file.stat();
                const time = stat.mtime;
                var fname = try allocator.alloc(u8, entry.name.len);
                errdefer allocator.free(entry.name);
                std.mem.copy(u8, fname, entry.name);
                const f = File{
                    .time = time,
                    .name = fname,
                    .kind = entry.kind,
                };
                try files.append(f);
            },
            else => {},
        }
    }
}

fn searchDirRecursively(path: []const u8, files: *Files, allocator: *std.mem.Allocator) !void {
    var walker = try std.fs.walkPath(allocator, path);
    defer walker.deinit();
    while (true) {
        const maybe_file = walker.next() catch |err| switch (err) {
            error.AccessDenied => continue,
            else => return err,
        };
        const file = if (maybe_file) |f| f else break;
        switch (file.kind) {
            .File => {
                if (fileTime(file.path)) |time| {
                    const substring_index = std.mem.indexOf(u8, file.path, path);
                    const new_start = if (substring_index) |i| i + path.len + 1 else 0;

                    var fname = try allocator.alloc(u8, file.path.len - new_start);
                    std.mem.copy(u8, fname, file.path[new_start..]);
                    const f = File{
                        .time = time,
                        .name = fname,
                        .kind = file.kind,
                    };
                    try files.append(f);
                }
            },
            else => {},
        }
    }
}

fn fileTime(path: []const u8) ?isize {
    var stat: os.Stat = undefined;
    const p = os.toPosixPath(path) catch return null;
    const success = os.system.stat(p[0..], &stat);
    return if (success == 0) stat.mtim.tv_sec else null;
}

fn usage() void {
    print("Program prints files in directory, sorted by last modification time\n", .{});
    print("{} [-r -R -v] directory\n", .{os.argv[0]});
    print("-r to print in reversed order", .{});
    print("-R for recursive searching\n", .{});
    print("-v for verbose output\n", .{});
}

fn parseArgs(argv: [][*:0]u8) ?Args {
    var args = Args{};
    for (argv) |i| {
        if (eql(i, "-h") or eql(i, "--h") or eql(i, "-?") or eql(i, "--?") or eql(i, "-help") or eql(i, "--help")) {
            usage();
            return null;
        } else if (eql(i, "-r")) {
            args.reverse = true;
        } else if (eql(i, "-R")) {
            args.recursive = true;
        } else if (eql(i, "-v")) {
            args.verbose = true;
        } else {
            args.dir = std.mem.spanZ(i);
        }
    }
    return args;
}
