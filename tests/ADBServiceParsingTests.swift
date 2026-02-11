import XCTest
@testable import APKInstaller

final class ADBServiceParsingTests: XCTestCase {
    func testParseDevicesOutput() {
        let output = """
        List of devices attached
        emulator-5554 device product:sdk_gphone model:Pixel_8 device:emu transport_id:1
        192.168.0.4:5555 unauthorized transport_id:2
        
        """

        let devices = ADBService.parseDevicesOutput(output)

        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0].id, "emulator-5554")
        XCTAssertEqual(devices[0].status, .device)
        XCTAssertEqual(devices[0].model, "Pixel_8")
        XCTAssertEqual(devices[1].status, .unauthorized)
    }

    func testParsePackageIdentifierFromBadging() throws {
        let output = """
        package: name='com.example.myapp' versionCode='1' versionName='1.0'
        sdkVersion:'24'
        """

        let package = try ADBService.parsePackageIdentifierFromBadging(output)
        XCTAssertEqual(package, "com.example.myapp")
    }

    func testParseADBVersionOutput() {
        let output = """
        Android Debug Bridge version 1.0.41
        Version 37.0.0-13894049
        Installed as /opt/homebrew/bin/adb
        """

        let version = ADBService.parseADBVersionOutput(output)
        XCTAssertEqual(version, "Android Debug Bridge version 1.0.41")
    }
}
