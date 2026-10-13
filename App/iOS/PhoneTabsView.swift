import JellyfinKit
import SwiftUI

/// Home, one tab per library, Search.
struct PhoneTabsView: View {
    @Environment(AppModel.self) private var model
    let session: SignedInSession

    var body: some View {
        TabView {
            Text("Home").tabItem { Label("Home", systemImage: "house") }
        }
    }
}
