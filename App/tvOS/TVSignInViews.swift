import JellyfinKit
import SwiftUI

/// The server address, typed once with the remote (or the keyboard the iPhone offers).
struct TVServerView: View {
    @Environment(AppModel.self) private var model
    let prefill: String
    let error: String?
    @State private var address = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            TVBrand()
            Text("Server").font(.system(size: 26)).foregroundStyle(BrowserStyle.dim).padding(.top, 30)
            TextField("jellyfin.example.com", text: $address)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .onSubmit(connect)
            if let error {
                Text(error).font(.system(size: 24)).foregroundStyle(.red)
            }
            Button(action: connect) {
                if model.session.isBusy { ProgressView() } else { Text("Continue") }
            }
            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || model.session.isBusy)
            Text("Typed once, with the remote or the keyboard that appears on your iPhone.")
                .font(.system(size: 22)).foregroundStyle(BrowserStyle.muted)
        }
        .frame(width: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if address.isEmpty { address = prefill } }
        .onChange(of: prefill) { _, new in if address.isEmpty { address = new } }
    }

    private func connect() {
        Task { await model.session.connect(address: address) }
    }
}

/// The server on the left; on the right a Quick Connect code to approve in another Jellyfin app,
/// or the username and password when Quick Connect is off or the person prefers it.
struct TVSignInView: View {
    @Environment(AppModel.self) private var model
    let server: ConnectedServer
    let username: String
    let error: String?
    @State private var usePassword = false
    @FocusState private var passwordButtonFocused: Bool

    private var showsPassword: Bool { usePassword || model.session.quickConnect == .unavailable }

    var body: some View {
        HStack(alignment: .center, spacing: 120) {
            VStack(alignment: .leading, spacing: 22) {
                TVBrand()
                Text("Server").font(.system(size: 26)).foregroundStyle(BrowserStyle.dim).padding(.top, 30)
                Text(server.name).font(.system(size: 34, weight: .semibold)).foregroundStyle(BrowserStyle.text)
                Text(server.url.absoluteString).font(.system(size: 24)).foregroundStyle(BrowserStyle.muted)
                Button("Change Server") { model.session.changeServer() }.padding(.top, 10)
            }
            .frame(width: 640, alignment: .leading)

            Rectangle().fill(BrowserStyle.line).frame(width: 2, height: 520)

            Group {
                if showsPassword {
                    TVPasswordForm(username: username, error: error)
                } else {
                    quickConnect
                }
            }
            .frame(width: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Not Change Server: one stray click there would throw the code away.
        .defaultFocus($passwordButtonFocused, true)
        // Polls while the code is up; leaving the screen (signed in, or Change Server) cancels it.
        .task(id: showsPassword) {
            if !showsPassword { await model.session.runQuickConnect() }
        }
    }

    private var quickConnect: some View {
        VStack(alignment: .leading, spacing: 26) {
            Text("Sign in from your phone").font(.system(size: 44, weight: .bold)).foregroundStyle(BrowserStyle.text)
            if let error {
                Text(error).font(.system(size: 24)).foregroundStyle(.red)
            }
            (Text("In Jellyfin on your phone or the web, open your profile › ")
                + Text("Quick Connect").bold().foregroundColor(BrowserStyle.text)
                + Text(" and enter this code."))
                .font(.system(size: 26)).foregroundStyle(BrowserStyle.dim).lineSpacing(6)
            if case .waiting(let code) = model.session.quickConnect {
                HStack(spacing: 14) {
                    ForEach(Array(code.enumerated()), id: \.offset) { _, digit in
                        Text(String(digit))
                            .font(.system(size: 72, weight: .bold).monospacedDigit())
                            .foregroundStyle(BrowserStyle.text)
                            .frame(width: 96, height: 128)
                            .background(BrowserStyle.raised, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(white: 0.25), lineWidth: 2))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Waiting for approval…").font(.system(size: 22)).foregroundStyle(BrowserStyle.muted)
                }
            } else {
                ProgressView().frame(height: 128)
            }
            Button("Use a password instead") { usePassword = true }
                .focused($passwordButtonFocused)
                .padding(.top, 10)
        }
    }
}

private struct TVPasswordForm: View {
    @Environment(AppModel.self) private var model
    let username: String
    let error: String?
    @State private var name = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Sign in").font(.system(size: 44, weight: .bold)).foregroundStyle(BrowserStyle.text)
            TextField("Username", text: $name)
                .textContentType(.username)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(.password)
                .onSubmit(signIn)
            if let error {
                Text(error).font(.system(size: 24)).foregroundStyle(.red)
            }
            Button(action: signIn) {
                if model.session.isBusy { ProgressView() } else { Text("Sign In") }
            }
            .disabled(name.isEmpty || model.session.isBusy)
        }
        .onAppear { if name.isEmpty { name = username } }
        // A failed attempt clears the password field.
        .onChange(of: error) { _, newError in if newError != nil { password = "" } }
    }

    private func signIn() {
        let password = self.password
        Task { await model.session.signIn(username: name, password: password) }
    }
}

/// The mark and the app's name.
struct TVBrand: View {
    var body: some View {
        HStack(spacing: 16) {
            Image("Mark").resizable().scaledToFit().frame(width: 48, height: 48).accessibilityHidden(true)
            Text("Tiny Jellyfin").font(.system(size: 40, weight: .bold)).foregroundStyle(BrowserStyle.text)
        }
    }
}
