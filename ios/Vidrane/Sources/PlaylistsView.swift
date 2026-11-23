import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject private var library: MediaLibrary
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        List {
            if library.playlists.isEmpty {
                EmptyLibraryState(symbol: "music.note.list", title: "Плейлистов пока нет",
                                  detail: "Создайте плейлист и добавьте в него импортированные аудио- или видеофайлы.")
                    .listRowBackground(Color.clear)
            }
            ForEach(library.playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlistID: playlist.id)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playlist.name)
                            Text("\(playlist.files.count) элементов")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "music.note.list")
                            .foregroundStyle(VidraneStyle.accent)
                    }
                }
            }
            .onDelete { offsets in
                let ids = offsets.map { library.playlists[$0].id }
                ids.forEach { library.deletePlaylist(id: $0) }
            }
        }
        .navigationTitle("Плейлисты")
        .toolbar {
            Button {
                newName = ""
                creating = true
            } label: { Image(systemName: "plus") }
                .accessibilityLabel("Создать плейлист")
        }
        .alert("Новый плейлист", isPresented: $creating) {
            TextField("Название", text: $newName)
            Button("Создать") { library.createPlaylist(name: newName) }
            Button("Отмена", role: .cancel) {}
        }
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject private var library: MediaLibrary
    let playlistID: UUID
    @State private var addingFiles = false

    private var playlist: StoredPlaylist? {
        library.playlists.first { $0.id == playlistID }
    }

    var body: some View {
        List {
            if let playlist {
                ForEach(library.files(in: playlist)) { file in
                    Button {
                        library.play(file)
                    } label: {
                        Label(file.relativePath, systemImage: file.symbol)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            library.remove(file, from: playlistID)
                        } label: {
                            Label("Убрать из плейлиста", systemImage: "minus.circle")
                        }
                    }
                }
                .onDelete { offsets in
                    let current = library.files(in: playlist)
                    offsets.map { current[$0] }.forEach { library.remove($0, from: playlistID) }
                }
            }
        }
        .navigationTitle(playlist?.name ?? "Плейлист")
        .toolbar {
            Button {
                addingFiles = true
            } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $addingFiles) {
            NavigationStack {
                List {
                    ForEach(library.files.filter { !$0.isDirectory && $0.kind.playable }) { file in
                        Button {
                            library.add(file, to: playlistID)
                        } label: {
                            HStack {
                                Text(file.relativePath).lineLimit(2)
                                Spacer()
                                if playlist?.files.contains(file.id) == true {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(VidraneStyle.accent)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Добавить файлы")
                .toolbar {
                    Button("Готово") { addingFiles = false }
                }
            }
        }
    }
}
