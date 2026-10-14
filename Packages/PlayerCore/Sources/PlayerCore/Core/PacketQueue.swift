import Foundation

/// Bounded FIFO of packets for one stream. `push` blocks while the queue holds more than
/// `maxDuration` seconds or `maxBytes` bytes; `pop` never blocks.
final class PacketQueue: @unchecked Sendable {
    let maxDuration: Double
    let maxBytes: Int
    private let condition = NSCondition()
    private var packets: [Packet] = []
    private var head = 0
    private var bytes = 0
    private var closed = false
    private var ended = false
    /// Read from the engine's queue while the reader thread sets and clears it.
    var endOfStream: Bool { condition.lock(); defer { condition.unlock() }; return ended }

    /// Per queue. Two pipelines are alive during a quality switch, and iOS and tvOS give an app less memory,
    /// especially in Picture in Picture.
    #if os(iOS) || os(tvOS)
    static let defaultMaxBytes = 100 * 1024 * 1024
    #else
    static let defaultMaxBytes = 200 * 1024 * 1024
    #endif

    init(maxDuration: Double = 30, maxBytes: Int = PacketQueue.defaultMaxBytes) {
        self.maxDuration = maxDuration
        self.maxBytes = maxBytes
    }

    private var count: Int { packets.count - head }

    private var bufferedDuration: Double {
        guard count > 1 else { return 0 }
        return packets[packets.count - 1].time - packets[head].time
    }

    /// Returns false if the queue was closed or `shouldAbort` became true while waiting.
    @discardableResult
    func push(_ packet: Packet, shouldAbort: () -> Bool = { false }) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        while !closed && !shouldAbort() && count > 0 && (bufferedDuration >= maxDuration || bytes >= maxBytes) {
            _ = condition.wait(until: Date().addingTimeInterval(0.05))
        }
        if closed || shouldAbort() { return false }
        packets.append(packet)
        bytes += packet.size
        condition.broadcast()
        return true
    }

    func pop() -> Packet? {
        condition.lock()
        defer { condition.unlock() }
        guard head < packets.count else { return nil }
        let packet = packets[head]
        head += 1
        bytes -= packet.size
        if head > 256 && head * 2 > packets.count {
            packets.removeFirst(head)
            head = 0
        }
        condition.broadcast()
        return packet
    }

    func peek() -> Packet? {
        condition.lock(); defer { condition.unlock() }
        return head < packets.count ? packets[head] : nil
    }

    /// Drops packets from the front while `predicate` holds; returns how many were dropped.
    @discardableResult
    func dropWhile(_ predicate: (Packet) -> Bool) -> Int {
        condition.lock(); defer { condition.unlock() }
        var dropped = 0
        while head < packets.count && predicate(packets[head]) {
            bytes -= packets[head].size
            head += 1
            dropped += 1
        }
        condition.broadcast()
        return dropped
    }

    /// First queued packet matching `predicate`, without removing anything.
    func first(where predicate: (Packet) -> Bool) -> Packet? {
        condition.lock(); defer { condition.unlock() }
        return packets[head...].first(where: predicate)
    }

    var isEmpty: Bool { condition.lock(); defer { condition.unlock() }; return count == 0 }

    /// Seconds of media buffered ahead of the front.
    var duration: Double { condition.lock(); defer { condition.unlock() }; return bufferedDuration }

    /// Time of the last queued packet.
    var lastTime: Double? {
        condition.lock(); defer { condition.unlock() }
        return count > 0 ? packets[packets.count - 1].time : nil
    }

    func markEndOfStream() {
        condition.lock(); ended = true; condition.broadcast(); condition.unlock()
    }

    /// True once the reader hit the end and every packet was consumed.
    var isDrained: Bool { condition.lock(); defer { condition.unlock() }; return ended && count == 0 }

    func flush() {
        condition.lock()
        packets.removeAll()
        head = 0
        bytes = 0
        ended = false
        condition.broadcast()
        condition.unlock()
    }

    func close() {
        condition.lock(); closed = true; condition.broadcast(); condition.unlock()
    }
}
