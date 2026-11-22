import SwiftUI
import UniformTypeIdentifiers

struct LocalView: View {
    @EnvironmentObject private var library: MediaLibrary
    @AppStorage("showExtensions") private var showExtensions = true
    @State private var importing = false
    @State private var playlistTarget: LocalMedia?

    var body: some View {
        List {
            if library.files.isEmpty {
                EmptyLibraryState(
                    symbol: "folder.badge.plus",
                    title: "Медиатека пуста",
                    detail: "Импортируйте видео или аудио из приложения «Файлы»."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(library.files) { file in
                    Button {
                        library.play(file)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: file.kind.symbol)
                                .frame(width: 28)
                                .foregroundStyle(VidraneStyle.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(showExtensions ? file.name : (file.name as NSString).deletingPathExtension)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                Text(file.kind.playable ? "Готово к воспроизведению" : "Файл")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if file.kind.playable {
                                Image(systemName: "play.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contextMenu {
                        if file.kind.playable {
                            Button("Добавить в плейлист", systemImage: "text.badge.plus") {
                                playlistTarget = file
                            }
                        }
                        Button("Удалить", systemImage: "trash", role: .destructive) {
                            library.delete(file)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("Локально")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    importing = true
                } label: { Image(systemName: "plus") }
                .accessibilityLabel("Импортировать файлы")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) {
            result in
            switch result {
            case .success(let urls): library.importFiles(urls)
            case .failure(let error): library.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $playlistTarget) { file in
            NavigationStack {
                List {
                    if library.playlists.isEmpty {
                        Text("Создайте плейлист во вкладке «Плейлисты».")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(library.playlists) { playlist in
                        Button(playlist.name) {
                            library.add(file, to: playlist.id)
                            playlistTarget = nil
                        }
                    }
                }
                .navigationTitle("В плейлист")
                .toolbar {
                    Button("Закрыть") { playlistTarget = nil }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
