import SwiftUI
import ServiceManagement

@main
struct DiskEncrypterAccessApp: App {
    @StateObject private var model = AccessModel()

    init() {
        guard CommandLine.arguments.contains("--unregister-helper-for-update") else { return }
        do {
            try SMAppService.daemon(plistName: HelperConstants.daemonPlistName).unregister()
            print("Privileged helper unregistered. The app bundle can now be replaced.")
            exit(EXIT_SUCCESS)
        } catch {
            fputs("Could not unregister privileged helper: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    var body: some Scene {
        WindowGroup("Disk Encrypter Access") {
            ContentView(model: model)
                .frame(minWidth: 620, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
    }
}
