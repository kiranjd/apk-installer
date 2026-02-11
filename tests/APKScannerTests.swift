import XCTest
@testable import APKInstaller

final class APKScannerTests: XCTestCase {
    func testScannerFindsOnlyAPKFilesRecursively() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let firstAPK = root.appendingPathComponent("first.apk")
        let secondAPK = nested.appendingPathComponent("second.apk")
        let ignored = nested.appendingPathComponent("notes.txt")

        try Data("a".utf8).write(to: firstAPK)
        try Data("b".utf8).write(to: secondAPK)
        try Data("c".utf8).write(to: ignored)

        let files = try APKScanner.scan(in: root)
        let names = files.map { $0.name }

        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(names.contains("first.apk"))
        XCTAssertTrue(names.contains("second.apk"))
    }
}
