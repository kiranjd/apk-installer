import XCTest
@testable import APKInstaller

final class CommandRunnerTests: XCTestCase {
    func testCommandRunnerReturnsStdout() async throws {
        let result = try await CommandRunner.run(
            executable: "/bin/echo",
            arguments: ["hello"],
            timeout: 5
        )

        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testCommandRunnerTimesOut() async {
        do {
            _ = try await CommandRunner.run(
                executable: "/bin/sleep",
                arguments: ["2"],
                timeout: 0.1
            )
            XCTFail("Expected timeout")
        } catch let error as CommandRunnerError {
            guard case .timedOut = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCommandRunnerHandlesLargeStdoutWithoutDeadlock() async throws {
        let result = try await CommandRunner.run(
            executable: "/bin/zsh",
            arguments: ["-lc", "yes deadlock-test | head -n 200000"],
            timeout: 5
        )

        XCTAssertTrue(result.stdout.count > 1_000_000)
        XCTAssertEqual(result.exitCode, 0)
    }
}
