import AppKit
import JellyfinKit
import PlayerCore
import SwiftUI

@main
struct TinyJellyfinApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Tinyfin", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    // A test host must not ask the Keychain for the token: the debug binary's
                    // signature changes with every build, so each run would show an access prompt.
                    let env = ProcessInfo.processInfo.environment
                    #if DEBUG
                    if let address = env["TJ_SERVER"] {
                        await model.session.connect(address: address)
                        if let user = env["TJ_USER"] { await model.session.signIn(username: user, password: "") }
                        return
                    }
                    #endif
                    if env["XCTestConfigurationFilePath"] == nil { model.session.restore() }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    // Tell the server before we go, so it stops transcoding for us.
                    model.player.stopForTermination()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            PlaybackCommands(controller: model.player)
            CommandGroup(after: .appInfo) { AcknowledgementsCommand() }
        }

        Window("Acknowledgements", id: "acknowledgements") {
            AcknowledgementsView().frame(minWidth: 560, minHeight: 400)
        }
        .defaultSize(width: 680, height: 640)

        Window("Player", id: AppModel.playerWindowID) {
            PlayerWindowView()
                .environment(model)
                .frame(minWidth: 480, minHeight: 270)
        }
        .defaultSize(width: 1280, height: 720)
        .windowStyle(.hiddenTitleBar)
    }
}

struct AcknowledgementsCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Acknowledgements") { openWindow(id: "acknowledgements") }
    }
}
