import JellyfinKit
import SwiftUI

@main
struct TinyJellyfinPhoneApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .task {
                    model.session.restore()
                    #if DEBUG
                    // Simulator hook: TJ_SERVER=<address> TJ_USER=<name> signs in with an empty
                    // password (the demo server's account), for screenshots.
                    let env = ProcessInfo.processInfo.environment
                    if case .serverEntry = model.session.state, let address = env["TJ_SERVER"] {
                        await model.session.connect(address: address)
                        if let user = env["TJ_USER"] { await model.session.signIn(username: user, password: "") }
                    }
                    #endif
                }
                // Swiped away from the app switcher mid-film (background audio keeps the app
                // running): tell the server, or it keeps transcoding for nobody.
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    model.player.stopForTermination()
                }
        }
    }
}

/// Sign-in until there is a session, then the tabs.
struct PhoneRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.session.state {
        case .serverEntry(let prefill, let error):
            ServerEntryView(prefill: prefill, error: error)
        case .signIn(let server, let username, let error):
            SignInView(server: server, username: username, error: error)
        case .signedIn(let session):
            PhoneTabsView(session: session)
        }
    }
}
