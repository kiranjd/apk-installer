import Foundation
import CoreGraphics

enum AppConfig {
    static let productName = "APK Installer"
    static let windowWidth: CGFloat = 900
    static let windowHeight: CGFloat = 580

    static let sidebarWidth: CGFloat = 200
    static let detailPanelWidth: CGFloat = windowWidth - sidebarWidth
    static let detailPanelHeight: CGFloat = windowHeight

    static let installPanelWidth: CGFloat = detailPanelWidth
    static let installPanelHeight: CGFloat = detailPanelHeight

    static let defaultAppIdentifier = "com.company.app"

    static let securitySettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    static let adbHelpURL = "https://developer.android.com/studio/command-line/adb#Enabling"
}
