import SwiftUI
import WebKit

struct BrowserView: View {
    @State private var address = "https://example.org"
    @State private var requestedAddress = "https://example.org"
    @State private var navigationRevision = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                TextField("Адрес сайта", text: $address)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .onSubmit(navigate)
                Button {
                    navigate()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Перейти")
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.vertical, 8)

            WebPage(address: requestedAddress, revision: navigationRevision)
        }
        .navigationTitle("Браузер")
    }

    private func navigate() {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        requestedAddress = trimmed.contains("://") ? trimmed : "https://" + trimmed
        navigationRevision += 1
    }
}

struct WebPage: UIViewRepresentable {
    let address: String
    let revision: Int

    final class Coordinator {
        var appliedRevision = -1
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.appliedRevision != revision else { return }
        context.coordinator.appliedRevision = revision
        guard let url = URL(string: address), url.scheme?.lowercased() == "https" else { return }
        webView.load(URLRequest(url: url))
    }
}
