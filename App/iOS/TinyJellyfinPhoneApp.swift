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
                .task { model.session.restore() }
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
