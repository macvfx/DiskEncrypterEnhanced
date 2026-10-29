import SwiftUI

@main
struct DiskEncrypterAccessApp: App {
    @StateObject private var model = AccessModel()

    var body: some Scene {
        WindowGroup("Disk Encrypter Access") {
            ContentView(model: model)
                .frame(minWidth: 620, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
    }
}
