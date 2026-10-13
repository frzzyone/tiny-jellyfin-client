import JellyfinKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        switch model.session.state {
        case .serverEntry(let prefill, let error):
            ServerEntryView(prefill: prefill, error: error)
        case .signIn(let server, let username, let error):
            SignInView(server: server, username: username, error: error)
        case .signedIn(let session):
            signedIn(session)
        }
    }

    @ViewBuilder
    private func signedIn(_ session: SignedInSession) -> some View {
        let view = BrowserView(session: session)
        #if DEBUG
        view.task { await DebugAutoplay.runIfRequested(model: model, openWindow: openWindow) }
        #else
        view
        #endif
    }
}
