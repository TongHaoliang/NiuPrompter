import Foundation

enum TestCounter { nonisolated(unsafe) static var count = 0 }

func checkEqual<Value: Equatable>(_ actual: Value, _ expected: Value, _ name: String) throws {
    TestCounter.count += 1
    guard actual == expected else {
        throw TestFailure(message: "\(name): expected \(expected), got \(actual)")
    }
}

func checkTrue(_ condition: @autoclosure () -> Bool, _ name: String) throws {
    TestCounter.count += 1
    guard condition() else { throw TestFailure(message: name) }
}

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    init(message: String) { self.message = message }
    var description: String { message }
}
