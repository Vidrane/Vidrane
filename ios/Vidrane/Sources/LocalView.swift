import SwiftUI
import UniformTypeIdentifiers

enum MediaSort: String, CaseIterable, Identifiable {
    case name, modified, size, type
    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Имя"
        case .modified: return "Дата изменения"
        case .size: return "Размер"
        case .type: return "Тип файла"
        }
    }
}

enum MediaFilter: String, CaseIterable, Identifiable {
    case all, videos, audio, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Все"
        case .videos: return "Видео"
        case .audio: return "Аудио"
        case .other: return "Другое"
        }
    }

    func includes(_ file: LocalMedia) -> Bool {
        switch self {
        case .all: return true
        case .videos: return file.kind == .video
        case .audio: return file.kind == .audio
        case .other: return !file.kind.playable
        }
    }
}

struct LocalView: View {
    @EnvironmentObject private var library: MediaLibrary
    @AppStorage("showExtensions") private var showExtensions = true
    @AppStorage("localSort") private var sortPreference = MediaSort.name.rawValue
    @AppStorage("localSortDescending") private var descending = false

    @State private var importing = false
    @State private var playlistTarget: LocalMedia?
    @State private var infoTarget: LocalMedia?
    @State private var renameTarget: LocalMedia?
    @State private var replacementName = ""
    @State private var filter: MediaFilter = .all
    @State private var search = ""

    private var sortedFiles: [LocalMedia] {
        let base = library.files.filter {
            filter.includes($0) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }
        let mode = MediaSort(rawValue: sortPreference) ?? .name
        return base.sorted { lhs, rhs in
            let result: ComparisonResult
            switch mode {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name)
            case .modified:
                let a = lhs.modified ?? .distantPast
                let b = rhs.modified ?? .distantPast
                result = a == b ? lhs.name.localizedStandardCompare(rhs.name)
                    : (a < b ? .orderedAscending : .orderedDescending)
            case .size:
                result = lhs.bytes == rhs.bytes ? lhs.name.localizedStandardCompare(rhs.name)
                    : (lhs.bytes < rhs.bytes ? .orderedAscending : .orderedDescending)
            case .type:
                result = lhs.kind == rhs.kind ? lhs.name.localizedStandardCompare(rhs.name)
                    : (lhs.kind.rawValue < rhs.kind.rawValue ? .orderedAscending : .orderedDescending)
            }
            return descending ? result == .orderedDescending : result == .orderedAscending
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Фильтр", selection: $filter) {
                    ForEach(MediaFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            Section {
                if sortedFiles.isEmpty {
                    EmptyLibraryState(
                        symbol: library.files.isEmpty ? "folder.badge.plus" : "magnifyingglass",
                        title: library.files.isEmpty ? "Медиатека пуста" : "Ничего не найдено",
                        detail: library.files.isEmpty
                            ? "Импортируйте видео или аудио из приложения «Файлы»."
                            : "Измените фильтр или поисковый запрос."
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(sortedFiles) { file in
                        Button {
                            if file.kind.playable {
                                library.play(file)
                            } else {
                                infoTarget = file
                            }
                        } label: {
                            fileRow(file)
                        }
                        .contextMenu { fileMenu(file) }
                    }
                }
            } header: {
                HStack {
                    Text("Файлы")
                    Spacer()
                    Text("\(sortedFiles.count) из \(library.files.count)")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("Локально")
        .searchable(text: $search, prompt: "Поиск файлов")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Сортировать по", selection: $sortPreference) {
                        ForEach(MediaSort.allCases) { kind in
                            Text(kind.title).tag(kind.rawValue)
                        }
                    }
                    Toggle("По убыванию", isOn: $descending)
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Сортировка")

                Button {
                    importing = true
                } label: {
                    Image(systemName: "plus")
                }
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
        .sheet(item: $infoTarget) { file in
            MediaInfoView(file: file)
        }
        .alert("Переименовать файл", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Имя файла", text: $replacementName)
            Button("Сохранить") {
                if let file = renameTarget {
                    library.rename(file, to: replacementName)
                }
                renameTarget = nil
            }
            Button("Отмена", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Изменение расширения может повлиять на определение формата.")
        }
    }

    private func fileRow(_ file: LocalMedia) -> some View {
        HStack(spacing: 14) {
            Image(systemName: file.kind.symbol)
                .frame(width: 28)
                .foregroundStyle(VidraneStyle.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(showExtensions ? file.name : (file.name as NSString).deletingPathExtension)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text(ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file))
                    if let date = file.modified {
                        Text(date, style: .date)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            Image(systemName: file.kind.playable ? "play.circle" : "info.circle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func fileMenu(_ file: LocalMedia) -> some View {
        if file.kind.playable {
            Button {
                library.play(file)
            } label: {
                Label("Воспроизвести", systemImage: "play.fill")
            }
            Button {
                playlistTarget = file
            } label: {
                Label("Добавить в плейлист", systemImage: "text.badge.plus")
            }
        }
        Button {
            infoTarget = file
        } label: {
            Label("Сведения", systemImage: "info.circle")
        }
        Button {
            replacementName = file.name
            renameTarget = file
        } label: {
            Label("Переименовать", systemImage: "pencil")
        }
        ShareLink(item: file.url) {
            Label("Поделиться", systemImage: "square.and.arrow.up")
        }
        Button(role: .destructive) {
            library.delete(file)
        } label: {
            Label("Удалить", systemImage: "trash")
        }
    }
}

struct MediaInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let file: LocalMedia

    var body: some View {
        NavigationStack {
            Form {
                Section("Файл") {
                    LabeledContent("Название", value: file.name)
                    LabeledContent("Размер", value:
                        ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file))
                    LabeledContent("Формат", value: file.url.pathExtension.uppercased())
                    if let modified = file.modified {
                        LabeledContent("Изменён", value: modified.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Section {
                    ShareLink(item: file.url) {
                        Label("Поделиться файлом", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("Сведения")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
