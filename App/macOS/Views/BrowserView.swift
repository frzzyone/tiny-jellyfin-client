import JellyfinKit
import PlayerCore
import SwiftUI

/// The main window: a top bar with Home and one tab per library, the page for the selected tab
/// (or search results while there is a search term), the quick look over it, and the keyboard.
struct BrowserView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let session: SignedInSession
    @State private var browser = BrowserModel()
    @State private var home: HomeModel?
    @State private var libraries: Loader<[BaseItem]>?
    @State private var path: [BaseItem] = []
    @State private var surpriseError: String?
    @State private var lastPlayedID: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                BrowserStyle.ground.ignoresSafeArea()
                VStack(spacing: 0) {
                    topBar
                    content
                }
                if let item = browser.quickLook {
                    Color.black.opacity(0.45).ignoresSafeArea()
                        .onTapGesture { browser.closeQuickLook() }
                    QuickLookView(item: item, onPlay: play, onOpenSeries: open, onUpdate: update,
                                  onClose: { browser.closeQuickLook() })
                        .transition(.opacity)
                }
            }
            .navigationDestination(for: BaseItem.self) { item in
                destination(for: item)
                    .background(BrowserStyle.ground)
            }
        }
        .environment(browser)
        .preferredColorScheme(.dark)
        .background(KeyMonitor(handler: handle))
        .onChange(of: browser.tab) { _, _ in
            path = []
            if browser.selection?.row != BrowserModel.tabsRow { browser.selection = nil }
            browser.closeQuickLook()
        }
        .onChange(of: model.player.status) { was, now in
            // The player stopped: positions on the server changed, so the hero and the rows follow.
            guard now == .idle || now == .ended, was != .idle, let playedID = lastPlayedID else { return }
            Task {
                await home?.refreshProgress()
                if let client = model.client, let fresh = try? await client.item(id: playedID) { update(fresh) }
            }
        }
        .onChange(of: libraries?.state.value?.map(\.id)) { _, ids in
            browser.tabs = [.home] + (ids ?? []).map { BrowserTab.library($0) }
        }
        .task {
            guard let client = model.client else { return }
            let loader = Loader { try await client.libraries() }
            libraries = loader
            let home = HomeModel(service: client)
            self.home = home
            async let libs: Void = loader.load()
            async let rows: Void = home.load()
            _ = await (libs, rows)
            #if DEBUG
            // Screenshot hooks: TJ_BROWSER_TAB=<library name> opens that tab, TJ_BROWSER_QUICKLOOK=hero|<item id>
            // opens the quick look, TJ_BROWSER_SELECT=<row>,<index> outlines a title.
            let env = ProcessInfo.processInfo.environment
            if let name = env["TJ_BROWSER_TAB"], let library = loader.state.value?.first(where: { $0.displayName == name }) {
                browser.tab = .library(library.id)
            }
            if let select = env["TJ_BROWSER_SELECT"]?.split(separator: ","), select.count == 2, let index = Int(select[1]) {
                browser.selection = BrowserSelection(row: String(select[0]), index: index)
            }
            if let text = env["TJ_BROWSER_SEARCH"] { browser.searchText = text }
            if let target = env["TJ_BROWSER_QUICKLOOK"] {
                if target == "hero", let hero = home.hero { browser.openQuickLook(hero, in: [hero]) }
                else if let item = try? await client.item(id: target) { browser.openQuickLook(item, in: [item]) }
            }
            #endif
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 32) {
            HStack(spacing: 10) {
                Image("Mark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                Text("Kinema")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BrowserStyle.text)
            }
            .padding(.leading, 70) // room for the traffic lights
            HStack(spacing: 26) {
                tab("Home", .home, index: 0)
                ForEach(Array((libraries?.state.value ?? []).enumerated()), id: \.element.id) { index, library in
                    tab(library.displayName, .library(library.id), index: index + 1)
                }
                if case .failed(let message)? = libraries?.state {
                    Button("Libraries didn't load · Retry") { Task { await libraries?.load() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(BrowserStyle.muted)
                        .help(message)
                }
            }
            Spacer()
            searchField
            Menu {
                Text(session.userName)
                Text(session.server.name)
                Divider()
                Button("Sign Out") { Task { await model.session.signOut() } }
            } label: {
                Text(String(session.userName.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BrowserStyle.text)
                    .frame(width: 32, height: 32)
                    .background(BrowserStyle.raised, in: Circle())
                    .overlay(Circle().stroke(BrowserStyle.line))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Account")
        }
        .padding(.horizontal, BrowserStyle.sidePadding)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func tab(_ title: String, _ tab: BrowserTab, index: Int) -> some View {
        let on = browser.tab == tab && browser.searchText.isEmpty
        let keyed = browser.selection == BrowserSelection(row: BrowserModel.tabsRow, index: index)
        return Button {
            browser.searchText = ""
            browser.tab = tab
            browser.selection = nil
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(on ? BrowserStyle.text : BrowserStyle.muted)
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(on ? BrowserStyle.accent : .clear).frame(height: 2) }
                .padding(.horizontal, 8)
                .overlay {
                    if keyed { RoundedRectangle(cornerRadius: 6).stroke(BrowserStyle.text, lineWidth: 2) }
                }
                .padding(.horizontal, -8)
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold))
            TextField("Just start typing", text: Bindable(browser).searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
                .onExitCommand { clearSearch() }
                .frame(width: 150)
            if !browser.searchText.isEmpty {
                Button(action: clearSearch) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .foregroundStyle(searchFocused || !browser.searchText.isEmpty ? BrowserStyle.text : BrowserStyle.muted)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(searchFocused ? BrowserStyle.raised : .clear, in: Capsule())
        .overlay(Capsule().stroke(BrowserStyle.line))
    }

    // MARK: Pages

    @ViewBuilder
    private var content: some View {
        if !browser.searchText.isEmpty {
            LibraryTabView(parentId: nil, title: "Search", searchTerm: browser.searchText)
                .id("search")
        } else {
            switch browser.tab {
            case .home:
                if let home {
                    HomeView(home: home, surpriseError: surpriseError, onPlay: play, onOpenSeries: open, onSurprise: surprise)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .library(let id):
                let library = libraries?.state.value?.first { $0.id == id }
                LibraryTabView(parentId: id, title: library?.displayName ?? "Library", searchTerm: "", library: library)
                    .id(id)
            }
        }
    }

    @ViewBuilder
    private func destination(for item: BaseItem) -> some View {
        switch item.type {
        case .series?: SeriesView(series: item)
        case .season?: SeasonView(season: item)
        default: SeriesView(series: item)
        }
    }

    // MARK: Actions

    private func play(_ item: BaseItem, resume: Bool) {
        browser.closeQuickLook()
        lastPlayedID = item.id
        model.play(item, resume: resume)
        openWindow(id: AppModel.playerWindowID)
    }

    /// A series or season opens its list; anything playable plays.
    private func open(_ item: BaseItem) {
        browser.closeQuickLook()
        switch item.type {
        case .series?, .season?: path.append(item)
        default: play(item, resume: item.resumePositionSeconds != nil)
        }
    }

    private func update(_ item: BaseItem) {
        home?.update(item)
        browser.update(item)
    }

    private func surprise() {
        guard let home else { return }
        Task {
            do {
                if let pick = try await home.surprise() {
                    browser.openQuickLook(pick, in: [pick])
                    surpriseError = nil
                } else {
                    surpriseError = "Nothing unwatched left to pick from."
                }
            } catch {
                surpriseError = describe(error)
            }
        }
    }

    private func clearSearch() {
        browser.searchText = ""
        searchFocused = false
    }

    // MARK: Keyboard

    /// Every key in the window. True swallows it. While the search field holds text, it keeps its
    /// keys (bar Escape); with the field empty, navigation keys are the page's even if the field
    /// has focus, and typed characters fall through to the field.
    private func handle(_ event: NSEvent, editing: Bool) -> Bool {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "f" { searchFocused = true; return true }
            if let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(digit) {
                clearSearch()
                browser.selectTab(number: digit)
                return true
            }
            return false
        }
        if editing {
            if event.isEscape { clearSearch(); return true }
            if event.typedText != nil { return false }
            // ↑ ↓ leave the field for the results (or the page); the rest stays with the field.
            if event.isUpArrow || event.isDownArrow {
                searchFocused = false
                browser.move(event.isDownArrow ? .down : .up)
                return true
            }
            if !browser.searchText.isEmpty { return false }
        }
        if browser.quickLook != nil {
            if event.isEscape { browser.closeQuickLook(); return true }
            if event.isLeftArrow { browser.stepQuickLook(forward: false); return true }
            if event.isRightArrow { browser.stepQuickLook(forward: true); return true }
            if event.isReturn { if let item = browser.quickLook { open(item) }; return true }
            if event.isSpace { browser.closeQuickLook(); return true }
            return false
        }
        if event.isUpArrow { browser.move(.up); return true }
        if event.isDownArrow { browser.move(.down); return true }
        if event.isLeftArrow { browser.move(.left); return true }
        if event.isRightArrow { browser.move(.right); return true }
        if event.isEscape {
            if !browser.searchText.isEmpty { clearSearch() } else { browser.selection = nil }
            return true
        }
        if event.isReturn {
            if browser.selection?.row == BrowserModel.tabsRow { browser.move(.down); return true }
            if let selected = browser.selectedItem { open(selected.item) }
            else if browser.tab == .home, browser.searchText.isEmpty, let hero = home?.hero { play(hero, resume: hero.resumePositionSeconds != nil) }
            return true
        }
        if event.isSpace {
            if let selected = browser.selectedItem { browser.openQuickLook(selected.item, in: selected.row) }
            return true
        }
        // Printable characters start a search; S on Home is Surprise me.
        guard let text = event.typedText else { return false }
        if text == "s", browser.searchText.isEmpty, browser.tab == .home { surprise(); return true }
        typeIntoSearch(text)
        return true
    }

    /// Puts the field in focus, then types the character into it once it really is the first
    /// responder. Taking focus selects the field's whole text, so appending the character to the
    /// binding and focusing would let the next key replace it; inserting at the end does not.
    private func typeIntoSearch(_ text: String, attempt: Int = 0) {
        searchFocused = true
        let editor = NSApp.windows.lazy.compactMap { $0.firstResponder as? NSTextView }.first
        if let editor {
            let end = (editor.string as NSString).length
            editor.setSelectedRange(NSRange(location: end, length: 0))
            editor.insertText(text, replacementRange: NSRange(location: end, length: 0))
        } else if attempt < 25 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { typeIntoSearch(text, attempt: attempt + 1) }
        } else {
            browser.searchText += text
        }
    }
}
