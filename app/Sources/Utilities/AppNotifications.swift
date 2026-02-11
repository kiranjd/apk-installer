import Foundation

extension Notification.Name {
    static let navigateToInstall = Notification.Name("APKInstaller.navigateToInstall")
    static let navigateToSettings = Notification.Name("APKInstaller.navigateToSettings")
    static let apkInstallDidSucceed = Notification.Name("APKInstaller.apkInstallDidSucceed")

    #if DEBUG
    static let snapshotInstallSelectedAPK = Notification.Name("APKInstaller.snapshotInstallSelectedAPK")
    #endif
}
