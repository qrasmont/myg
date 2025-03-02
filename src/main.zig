const std = @import("std");

/// A display manager for showing MQTT topics and their values on a terminal screen.
/// Each topic has a dedicated position, and only values are redrawn when updated.
pub const MqttDisplay = struct {
    /// Stores information about each topic's display position
    topics: std.StringHashMap(TopicInfo),

    /// Memory allocator
    allocator: std.mem.Allocator,

    /// Terminal output
    writer: std.fs.File.Writer,

    /// Next available row for new topics
    next_row: usize,

    /// Information about a topic's display position
    const TopicInfo = struct {
        /// Screen row where this topic is displayed (1-based)
        row: usize,

        /// Column where the value starts (after topic name and colon)
        value_column: usize,

        /// Current value being displayed
        value: []u8,
    };

    /// Initialize a new MQTT topic display manager
    pub fn init(allocator: std.mem.Allocator, writer: std.fs.File.Writer) MqttDisplay {
        return MqttDisplay{
            .topics = std.StringHashMap(TopicInfo).init(allocator),
            .allocator = allocator,
            .writer = writer,
            .next_row = 1,
        };
    }

    /// Release all resources used by the display manager
    pub fn deinit(self: *MqttDisplay) void {
        // Free all values and keys
        var it = self.topics.iterator();
        while (it.next()) |entry| {
            // Free the value string in TopicInfo
            self.allocator.free(entry.value_ptr.value);

            // Free the topic string (key)
            self.allocator.free(entry.key_ptr.*);
        }

        // Free the hash map itself
        self.topics.deinit();
    }

    /// Configure the terminal for display
    pub fn setupTerminal(self: *MqttDisplay) !void {
        // Use alternative screen buffer
        try self.writer.writeAll("\x1B[?1049h");

        // Clear the screen
        try self.writer.writeAll("\x1B[2J");

        // Hide cursor
        try self.writer.writeAll("\x1B[?25l");

        return;
    }

    /// Restore the terminal to its normal state
    pub fn restoreTerminal(self: *MqttDisplay) !void {
        // Show cursor
        try self.writer.writeAll("\x1B[?25h");

        // Return to main screen buffer
        try self.writer.writeAll("\x1B[?1049l");

        return;
    }

    /// Update a topic with a new value
    /// If the topic doesn't exist yet, it will be added to the display
    pub fn updateTopic(self: *MqttDisplay, topic: []const u8, value: []const u8) !void {
        if (self.topics.getPtr(topic)) |info| {
            // Topic exists, just update the value part

            // Free old value and duplicate new one
            self.allocator.free(info.value);
            info.value = try self.allocator.dupe(u8, value);

            // Redraw only the value part
            try self.redrawTopicValue(topic);
        } else {
            // New topic, need to add it
            const topic_duped = try self.allocator.dupe(u8, topic);
            errdefer self.allocator.free(topic_duped);

            const value_duped = try self.allocator.dupe(u8, value);
            errdefer self.allocator.free(value_duped);

            // Store topic display information
            try self.topics.put(topic_duped, TopicInfo{
                .row = self.next_row,
                .value_column = topic.len + 3, // After topic name and ": "
                .value = value_duped,
            });

            // Draw the full topic line
            try self.drawFullTopic(topic_duped);

            // Next topic will go on the next row
            self.next_row += 1;
        }
    }

    /// Draw both the topic name and its value
    fn drawFullTopic(self: *MqttDisplay, topic: []const u8) !void {
        const info = self.topics.get(topic).?;

        // Position cursor at the start of this topic's row
        try self.writer.print("\x1B[{d};1H", .{info.row});

        // Draw the topic name (fixed part)
        try self.writer.print("{s}: ", .{topic});

        // Draw the value (changing part)
        try self.writer.print("{s}", .{info.value});
    }

    /// Redraw just the value part of a topic
    fn redrawTopicValue(self: *MqttDisplay, topic: []const u8) !void {
        const info = self.topics.get(topic).?;

        // Position cursor at the start of the value
        try self.writer.print("\x1B[{d};{d}H", .{ info.row, info.value_column });

        // Clear to the end of line
        try self.writer.writeAll("\x1B[K");

        // Write the new value
        try self.writer.print("{s}", .{info.value});
    }

    /// Clear screen and redraw all topics
    pub fn redrawAll(self: *MqttDisplay) !void {
        // Clear the screen
        try self.writer.writeAll("\x1B[2J");

        // Draw each topic
        var it = self.topics.iterator();
        while (it.next()) |entry| {
            try self.drawFullTopic(entry.key_ptr.*);
        }
    }

    /// Get number of topics currently being displayed
    pub fn topicCount(self: *const MqttDisplay) usize {
        return self.topics.count();
    }
};

/// Example of how to use the topic display
pub fn testMqttDisplay() !void {
    // Setup memory allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get output stream
    const stdout = std.io.getStdOut();
    const writer = stdout.writer();

    // Create display manager
    var display = MqttDisplay.init(allocator, writer);
    defer display.deinit();

    // Setup terminal for TUI
    try display.setupTerminal();
    defer display.restoreTerminal() catch {};

    // Add some initial topics
    try display.updateTopic("sensor/temperature", "22.5°C");
    try display.updateTopic("sensor/humidity", "45%");
    try display.updateTopic("device/status", "online");

    // Simulate some updates
    const updates = [_][2][]const u8{
        .{ "sensor/temperature", "23.1°C" },
        .{ "sensor/humidity", "47%" },
        .{ "device/status", "active" },
        .{ "sensor/pressure", "1013 hPa" }, // New topic
        .{ "sensor/temperature", "22.8°C" },
        .{ "network/status", "connected" }, // New topic
    };

    for (updates) |update| {
        // Wait a bit between updates
        std.time.sleep(800 * std.time.ns_per_ms);

        // Update the topic
        try display.updateTopic(update[0], update[1]);
    }

    // Show exit message
    try writer.print("\x1B[{d};1H\x1B[KPress any key to exit...", .{display.next_row + 2});

    // Wait for user input
    var buffer: [1]u8 = undefined;
    _ = try std.io.getStdIn().read(&buffer);
}

pub fn main() !void {
    try testMqttDisplay();
}

test "MqttDisplay basic functionality" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // Create a temporary file for testing output
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var tmp_file = try tmp_dir.dir.createFile("test.txt", .{});
    defer tmp_file.close();

    // Create display manager
    var display = MqttDisplay.init(allocator, tmp_file.writer());
    defer display.deinit();

    // Add some topics
    try display.updateTopic("test/topic1", "value1");
    try display.updateTopic("test/topic2", "value2");

    // Verify topic count
    try testing.expectEqual(@as(usize, 2), display.topicCount());

    // Update an existing topic
    try display.updateTopic("test/topic1", "updated");

    // Count should stay the same
    try testing.expectEqual(@as(usize, 2), display.topicCount());

    // Add a new topic
    try display.updateTopic("test/topic3", "value3");

    // Count should increase
    try testing.expectEqual(@as(usize, 3), display.topicCount());

    // Check next_row value (should be 4 as we've added 3 topics)
    try testing.expectEqual(@as(usize, 4), display.next_row);
}
