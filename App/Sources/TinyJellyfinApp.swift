import AppKit
import JellyfinKit
import PlayerCore
import SwiftUI

@main
struct TinyJellyfinApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Tiny Jellyfin", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 480)
                .task { model.session.restore() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    // Tell the server before we go, so it stops transcoding for us.
                    model.player.stopForTermination()
                }
        }
        .commands {
            PlaybackCommands(controller: model.player)
        }

        Window("Player", id: AppModel.playerWindowID) {
            PlayerWindowView()
                .environment(model)
                .frame(minWidth: 480, minHeight: 270)
        }
        .defaultSize(width: 1280, height: 720)
        .windowStyle(.hiddenTitleBar)
    }
}
