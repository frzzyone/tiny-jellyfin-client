import SwiftUI

/// The licences the app ships under: our notices, how FFmpeg was built, and the LGPL text.
/// FFmpeg's LGPL asks for the notice and the licence to travel with the app.
struct AcknowledgementsView: View {
    private static let files = ["THIRD_PARTY_NOTICES.md", "BUILD-INFO", "COPYING.LGPLv2.1"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(Self.files, id: \.self) { name in
                    if let url = Bundle.main.url(forResource: name, withExtension: nil),
                       let text = try? String(contentsOf: url, encoding: .utf8) {
                        #if os(tvOS)
                        // The remote scrolls by moving focus, so each paragraph takes it in turn.
                        ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                            Text(verbatim: paragraph)
                                .font(.system(size: 22, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .focusable()
                        }
                        #else
                        Text(verbatim: text)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        #endif
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Acknowledgements")
    }
}
