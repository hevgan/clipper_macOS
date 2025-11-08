import ServiceManagement

enum LoginItemManager {
    private static let helperIdentifier = "dev.clipper.app"
 
    static func enable() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
            } catch {
                NSLog("Failed to register login item: \(error.localizedDescription)")
            }
        } else {
            SMLoginItemSetEnabled(helperIdentifier as CFString, true)
        }
    }

    static func disable() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                NSLog("Failed to unregister login item: \(error.localizedDescription)")
            }
        } else {
            SMLoginItemSetEnabled(helperIdentifier as CFString, false)
        }
    }
}
