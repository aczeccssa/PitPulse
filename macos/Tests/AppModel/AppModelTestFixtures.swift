import XCTest
@testable import SharedData
@testable import PitPulseDesktop

final class MutableResultsFixture: @unchecked Sendable {
    let lock = NSLock()
    var revision = 1
    var shouldFail = false

    func update(revision: Int, shouldFail: Bool = false) {
        lock.lock()
        self.revision = revision
        self.shouldFail = shouldFail
        lock.unlock()
    }

    func snapshot() -> (Int, Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (revision, shouldFail)
    }
}

final class MutableMeetingFixture: @unchecked Sendable {
    let lock = NSLock()
    var meeting: Meeting

    init(_ meeting: Meeting) { self.meeting = meeting }
    var value: Meeting {
        get { lock.lock(); defer { lock.unlock() }; return meeting }
        set { lock.lock(); meeting = newValue; lock.unlock() }
    }
}

final class RequestCounter: @unchecked Sendable {
    let lock = NSLock()
    var count = 0
    var requestTimes: [UInt64] = []

    var timestamps: [UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return requestTimes
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        requestTimes.append(DispatchTime.now().uptimeNanoseconds)
        lock.unlock()
    }
}

final class RequestLog: @unchecked Sendable {
    let lock = NSLock()
    var requests: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func append(_ value: String) {
        lock.lock()
        requests.append(value)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        requests.removeAll()
        lock.unlock()
    }
}
