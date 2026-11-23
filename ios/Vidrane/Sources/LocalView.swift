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
        if file.isDirectory { return true }
        switch self {
        case .all: return true
        case .videos: return file.kind == .video
        case .audio: return file.kind == .audio
        case .other: return !file.kind.playable
        }
    }
}

private struct LocalOperationRequest: Identifiable {
    let id = UUID()
    let file: LocalMedia
    let copy: Bool
}

/// Reused by the root library and every nested folder.
struct LocalView: View {
    @EnvironmentObject private var library: MediaLibrary
    @ObservedObject private var watchHistory = WatchHistory.shared
    @AppStorage("showExtensions") private var showExtensions = true
    @AppStorage("localSort") private var sortPreference = MediaSort.name.rawValue
    @AppStorage("localSortDescending") private var descending = false

    var folder: URL? = nil

    @State private var importing = false
    @State private var newFolderPrompt = false
    @State private var newFolderName = ""
    @State private var playlistTarget: LocalMedia?
    @State private var infoTarget: LocalMedia?
    @State private var renameTarget: LocalMedia?
    @State private var deleteTarget: LocalMedia?
    @State private var operation: LocalOperationRequest?
    @State private var replacementName = ""
    @State private var filter: MediaFilter = .all
    @State private var search = ""

    private var currentFolder: URL { folder ?? library.rootDirectory }
    private var isRoot: Bool { folder == nil }

    private var sortedFiles: [LocalMedia] {
        let base = library.entries(in: currentFolder).filter {
            filter.includes($0) &&
                (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }
        let mode = MediaSort(rawValue: sortPreference) ?? .name
        return base.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            let result: ComparisonResult
            switch mode {
            case .name:
                result = lhs.name.localizedStandardCompare(rhs.name)
            case .modified:
                let a = lhs.modified ?? .distantPast
                let b = rhs.modified ?? .distantPast
                result = a == b ? lhs.name.localizedStandardCompare(rhs.name) :
                    (a < b ? .orderedAscending : .orderedDescending)
            case .size:
                result = lhs.bytes == rhs.bytes ? lhs.name.localizedStandardCompare(rhs.name) :
                    (lhs.bytes < rhs.bytes ? .orderedAscending : .orderedDescending)
            case .type:
                result = lhs.kind == rhs.kind ? lhs.name.localizedStandardCompare(rhs.name) :
                    (lhs.kind.rawValue < rhs.kind.rawValue ? .orderedAscending : .orderedDescending)
            }
            return descending ? result == .orderedDescending : result == .orderedAscending
        }
    }

    private var interruptedFiles: [LocalMedia] {
        library.files
            .filter { !$0.isDirectory && $0.kind.playable &&
                watchHistory.checkpoint(for: $0.url) != nil }
            .sorted {
                (watchHistory.checkpoint(for: $0.url)?.updatedAt ?? .distantPast) >
                    (watchHistory.checkpoint(for: $1.url)?.updatedAt ?? .distantPast)
            }
    }

    var body: some View {
        List {
            if isRoot && !interruptedFiles.isEmpty && search.isEmpty {
                Section("Продолжить просмотр") {
                    ForEach(Array(interruptedFiles.prefix(5))) { file in
                        Button {
                            library.play(file)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Label(file.name, systemImage: "play.circle.fill")
                                    .foregroundStyle(.primary)
                                Text(file.relativePath)
                                    .font(.caption2).foregroundStyle(.secondary)
                                if let checkpoint = watchHistory.checkpoint(for: file.url) {
                                    ProgressView(value: checkpoint.fraction)
                                        .tint(VidraneStyle.accent)
                                    Text("Продолжить с \(Int(checkpoint.seconds / 60)) мин")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

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
                        title: library.files.isEmpty ? "Медиатека пуста" : "Папка пуста",
                        detail: library.files.isEmpty
                            ? "Импортируйте файлы или создайте папку."
                            : "Добавьте файлы или измените поиск."
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(sortedFiles) { file in
                        Group {
                            if file.isDirectory {
                                NavigationLink {
                                    LocalView(folder: file.url)
                                } label: {
                                    fileRow(file)
                                }
                            } else {
                                Button {
                                    if file.kind.playable {
                                        library.play(file)
                                    } else {
                                        infoTarget = file
                                    }
                                } label: {
                                    fileRow(file)
                                }
                            }
                        }
                        .contextMenu { fileMenu(file) }
                    }
                }
            } header: {
                HStack {
                    Text("Файлы и папки")
                    Spacer()
                    Text("\(sortedFiles.count) элементов")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle(isRoot ? "Локально" : currentFolder.lastPathComponent)
        .searchable(text: $search, prompt: "Поиск в этой папке")
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

                Menu {
                    Button {
                        importing = true
                    } label: {
                        Label("Импортировать", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        newFolderName = ""
                        newFolderPrompt = true
                    } label: {
                        Label("Создать папку", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Добавить файл или папку")
            }
        }
        .onAppear { library.refreshFiles() }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.item, .folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): library.importFiles(urls, to: currentFolder)
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
                .navigationTitle("Добавить в плейлист")
                .toolbar {
                    Button("Закрыть") { playlistTarget = nil }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $infoTarget) { file in
            MediaInfoView(file: file)
        }
        .sheet(item: $operation) { request in
            LocalDestinationPicker(request: request)
        }
        .alert("Новая папка", isPresented: $newFolderPrompt) {
            TextField("Название", text: $newFolderName)
            Button("Создать") {
                library.createFolder(named: newFolderName, in: currentFolder)
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Переименовать", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Новое название", text: $replacementName)
            Button("Сохранить") {
                if let file = renameTarget { library.rename(file, to: replacementName) }
                renameTarget = nil
            }
            Button("Отмена", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Изменение расширения файла может влиять на его распознавание.")
        }
        .confirmationDialog(
            "Удалить \(deleteTarget?.name ?? "элемент")?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let file = deleteTarget { library.delete(file) }
                deleteTarget = nil
            }
        } message: {
            Text("Папки удаляются вместе со всем содержимым. Действие необратимо.")
        }
    }

    private func fileRow(_ file: LocalMedia) -> some View {
        HStack(spacing: 14) {
            Image(systemName: file.symbol)
                .frame(width: 28)
                .foregroundStyle(VidraneStyle.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(file.isDirectory || showExtensions
                     ? file.name : (file.name as NSString).deletingPathExtension)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    if file.isDirectory {
                        Text("Папка")
                    } else {
                        Text(ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file))
                    }
                    if let date = file.modified {
                        Text(date, style: .date)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                if !file.isDirectory,
                   let checkpoint = watchHistory.checkpoint(for: file.url) {
                    ProgressView(value: checkpoint.fraction)
                        .tint(VidraneStyle.accent)
                        .accessibilityLabel("Просмотрено \(Int(checkpoint.fraction * 100)) процентов")
                }
            }
            Spacer()
            if !file.isDirectory {
                Image(systemName: file.kind.playable ? "play.circle" : "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func fileMenu(_ file: LocalMedia) -> some View {
        if !file.isDirectory && file.kind.playable {
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
        Button {
            operation = LocalOperationRequest(file: file, copy: false)
        } label: {
            Label("Переместить", systemImage: "folder")
        }
        Button {
            operation = LocalOperationRequest(file: file, copy: true)
        } label: {
            Label("Копировать", systemImage: "doc.on.doc")
        }
        if !file.isDirectory {
            ShareLink(item: file.url) {
                Label("Поделиться", systemImage: "square.and.arrow.up")
            }
        }
        Button(role: .destructive) {
            deleteTarget = file
        } label: {
            Label("Удалить", systemImage: "trash")
        }
    }
}

private struct LocalDestinationPicker: View {
    @EnvironmentObject private var library: MediaLibrary
    @Environment(\.dismiss) private var dismiss

    let request: LocalOperationRequest

    private func validDestination(_ folder: URL) -> Bool {
        guard library.isValidFolder(folder) else { return false }
        guard request.file.isDirectory else { return true }
        let source = request.file.url.standardizedFileURL.path
        let target = folder.standardizedFileURL.path
        return target != source && !target.hasPrefix(source + "/")
    }

    private func select(_ folder: URL) {
        library.relocate(request.file, to: folder, copy: request.copy)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    select(library.rootDirectory)
                } label: {
                    Label("Корень медиатеки", systemImage: "house.fill")
                }
                .disabled(!validDestination(library.rootDirectory))

                ForEach(library.folders) { folder in
                    Button {
                        select(folder.url)
                    } label: {
                        Label(folder.relativePath, systemImage: "folder")
                            .lineLimit(2)
                    }
                    .disabled(!validDestination(folder.url))
                }
            }
            .navigationTitle(request.copy ? "Копировать в…" : "Переместить в…")
            .toolbar {
                Button("Отмена") { dismiss() }
            }
        }
    }
}

struct MediaInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let file: LocalMedia

    var body: some View {
        NavigationStack {
            Form {
                Section(file.isDirectory ? "Папка" : "Файл") {
                    LabeledContent("Название", value: file.name)
                    LabeledContent("Путь", value: file.relativePath)
                    if !file.isDirectory {
                        LabeledContent(
                            "Размер",
                            value: ByteCountFormatter.string(
                                fromByteCount: file.bytes, countStyle: .file
                            )
                        )
                        LabeledContent("Формат", value: file.url.pathExtension.uppercased())
                    }
                    if let modified = file.modified {
                        LabeledContent(
                            "Изменён",
                            value: modified.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }
                if !file.isDirectory {
                    Section {
                        ShareLink(item: file.url) {
                            Label("Поделиться файлом", systemImage: "square.and.arrow.up")
                        }
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
