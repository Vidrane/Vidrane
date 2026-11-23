import SwiftUI
import AVFoundation

@main
struct VidraneApp: App {
    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

enum VidraneStyle {
    static let accent = Color(red: 0.76, green: 0.37, blue: 0.93)
}

struct AppRootView: View {
    @StateObject private var library = MediaLibrary()
    @StateObject private var webdavStore = WebDAVStore.shared
    @StateObject private var transfers = TransferCenter.shared

    var body: some View {
        TabView {
            NavigationStack { LocalView() }
                .tabItem { Label("Локально", systemImage: "folder") }
            NavigationStack { NetworkView() }
                .tabItem { Label("Сеть", systemImage: "network") }
            NavigationStack { PlaylistsView() }
                .tabItem { Label("Плейлисты", systemImage: "music.note.list") }
            NavigationStack { BrowserView() }
                .tabItem { Label("Браузер", systemImage: "globe") }
            NavigationStack { DownloadsView() }
                .tabItem { Label("Загрузки", systemImage: "arrow.down.circle") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Настройки", systemImage: "gearshape") }
        }
        .tint(VidraneStyle.accent)
        .preferredColorScheme(.dark)
        .environmentObject(library)
        .environmentObject(webdavStore)
        .environmentObject(transfers)
        .fullScreenCover(item: $library.playback) { request in
            PlaybackHostView(request: request)
        }
        .alert("Vidrane", isPresented: Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "")
        }
    }
}

struct EmptyLibraryState: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(VidraneStyle.accent)
            Text(title).font(.headline)
            Text(detail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding()
    }
}
