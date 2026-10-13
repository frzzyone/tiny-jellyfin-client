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
                        Text(verbatim: text)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Acknowledgements")
    }
}
