import JellyfinKit
import SwiftUI
import TVServices

@main
struct TinyJellyfinTVApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .task {
                    model.player.beforePlay = DisplayMatch.apply
                    model.session.restore()
                    #if DEBUG
                    // Simulator hook: TJ_SERVER=<address> skips typing it with the remote.
                    if case .serverEntry = model.session.state, let address = ProcessInfo.processInfo.environment["TJ_SERVER"] {
                        await model.session.connect(address: address)
                    }
                    #endif
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    model.player.stopForTermination()
                }
        }
    }
}

/// Sign-in until there is a session, then the tabs.
struct TVRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.session.state {
            case .serverEntry(let prefill, let error):
                TVServerView(prefill: prefill, error: error)
            case .signIn(let server, let username, let error):
                TVSignInView(server: server, username: username, error: error)
            case .signedIn(let session):
                TVTabsView(session: session)
            }
        }
        .background(BrowserStyle.ground)
        // Signed out, or the token expired: take the last user's Continue Watching off the Top Shelf.
        .onChange(of: isSignedIn) { _, signedIn in
            if !signedIn { TVTopShelfContentProvider.topShelfContentDidChange() }
        }
    }

    private var isSignedIn: Bool {
        if case .signedIn = model.session.state { return true }
        return false
    }
}

/// The TV's sizes: posters 220 pt wide, stills 400, 90 pt side margins (the safe area's 80 plus a little).
enum TVStyle {
    static let posterWidth: CGFloat = 220
    static let stillWidth: CGFloat = 400
    static let side: CGFloat = 90
    static let cardGap: CGFloat = 48
}
