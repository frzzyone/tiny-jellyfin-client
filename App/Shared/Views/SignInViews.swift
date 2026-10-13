import JellyfinKit
import SwiftUI

struct ServerEntryView: View {
    @Environment(AppModel.self) private var model
    let prefill: String
    let error: String?
    @State private var address = ""

    var body: some View {
        OnboardingCard(title: "Connect to Jellyfin", subtitle: "Enter the address of your Jellyfin server.") {
            TextField("Server address", text: $address, prompt: Text("jellyfin.example.com:8096"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(connect)
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            Button(action: connect) {
                if model.session.isBusy { ProgressView().controlSize(.small) } else { Text("Continue") }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || model.session.isBusy)
        }
        .onAppear { if address.isEmpty { address = prefill } }
        // The screen can already be up when the saved address arrives (session restore).
        .onChange(of: prefill) { _, new in if address.isEmpty { address = new } }
    }

    private func connect() {
        Task { await model.session.connect(address: address) }
    }
}

struct SignInView: View {
    @Environment(AppModel.self) private var model
    let server: ConnectedServer
    let username: String
    let error: String?
    @State private var name = ""
    @State private var password = ""

    var body: some View {
        OnboardingCard(title: "Sign in to \(server.name)", subtitle: server.url.absoluteString) {
            TextField("Username", text: $name).textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password).textFieldStyle(.roundedBorder).onSubmit(signIn)
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("Change Server") { model.session.changeServer() }
                Spacer()
                Button(action: signIn) {
                    if model.session.isBusy { ProgressView().controlSize(.small) } else { Text("Sign In") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || model.session.isBusy)
            }
        }
        .onAppear { if name.isEmpty { name = username } }
    }

    private func signIn() {
        let password = self.password
        Task {
            await model.session.signIn(username: name, password: password)
            // Every failed attempt clears the field, even when the message is the same as last time.
            if case .signIn(_, _, _?) = model.session.state { self.password = "" }
        }
    }
}

struct OnboardingCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
            content
        }
        .padding(28)
        .frame(maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrowserStyle.ground)
    }
}
