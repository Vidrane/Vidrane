import SwiftUI
import UniformTypeIdentifiers

struct SFTPAddView: View {
    @EnvironmentObject private var sftp: SFTPStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var password = ""
    @State private var path = "/"
    @State private var trustedKey = ""
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("SSH-сервер") {
                TextField("Название (необязательно)", text: $title)
                TextField("sftp.example.com", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Порт (по умолчанию 22)", text: $port)
                    .keyboardType(.numberPad)
                TextField("Папка, например /home/user/videos", text: $path)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("Пользователь") {
                TextField("Логин", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Пароль", text: $password)
            }
            Section {
                TextEditor(text: $trustedKey)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 95)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Доверенный ключ SSH-хоста")
            } footer: {
                Text("Вставьте полный публичный ключ сервера в формате ssh-ed25519 AAAA… или ecdsa-sha2-… AAAA… . Получите ключ у администратора и проверьте его по независимому каналу. Не используйте ключ, полученный от неизвестного сервера, без проверки.")
            }
            Section {
                Button("Сохранить SFTP") {
                    do {
                        try sftp.add(
                            title: title, host: host,
                            port: Int(port) ?? 0,
                            username: username, password: password,
                            rootPath: path, trustedHostKey: trustedKey
                        )
                        password = ""
                        dismiss()
                    } catch {
                        errorText = error.localizedDescription
                    }
                }
                .disabled(host.isEmpty || username.isEmpty || trustedKey.isEmpty)
            }
        }
        .navigationTitle("Новый SFTP")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Закрыть") { dismiss() }
            }
        }
        .alert("SFTP", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }
}

struct SFTPBrowserView: View {
    @EnvironmentObject private var sftp: SFTPStore
    @EnvironmentObject private var library: MediaLibrary
    @EnvironmentObject private var transfers: TransferCenter

    let server: SFTPServer
    let directory: String

    @State private var files: [SFTPEntry] = []
    @State private var loading = false
    @State private var streaming: Set<String> = []
    @State private var errorText: String?
    @State private var mutating = false
    @State private var uploading = false
    @State private var creatingFolder = false
    @State private var folderName = ""
    @State private var deleteTarget: SFTPEntry?

    var body: some View {
        List {
            if loading && files.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Получение каталога")
                    Spacer()
                }
            } else if files.isEmpty {
                EmptyLibraryState(
                    symbol: "server.rack",
                    title: "Нет файлов",
                    detail: "Папка пуста или сервер не возвращает список."
                )
                .listRowBackground(Color.clear)
            }
            ForEach(files) { entry in
                if entry.isDirectory {
                    NavigationLink {
                        SFTPBrowserView(server: server, directory: entry.path)
                    } label: {
                        Label(entry.name, systemImage: "folder")
                    }
                    .contextMenu {
                        Button(role: .destructive) { deleteTarget = entry } label: {
                            Label("Удалить пустую папку", systemImage: "trash")
                        }
                    }
                } else {
                    Menu {
                        Button {
                            transfer(entry, play: false)
                        } label: {
                            Label("Скачать в медиатеку", systemImage: "arrow.down.circle")
                        }
                        if VidraneMediaKind(filename: entry.name).playable {
                            if SFTPRangeStream.allowedExtensions.contains(
                                (entry.name as NSString).pathExtension.lowercased()
                            ) {
                                Button {
                                    Task { await playStream(entry) }
                                } label: {
                                    Label(
                                        "Воспроизвести без скачивания",
                                        systemImage: "play.rectangle"
                                    )
                                }
                            }
                            Button {
                                transfer(entry, play: true)
                            } label: {
                                Label("Скачать и воспроизвести", systemImage: "play.circle")
                            }
                        }
                        Button(role: .destructive) {
                            deleteTarget = entry
                        } label: {
                            Label("Удалить с сервера", systemImage: "trash")
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: VidraneMediaKind(filename: entry.name).symbol)
                                .frame(width: 24)
                                .foregroundStyle(VidraneStyle.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.name).foregroundStyle(.primary)
                                if let size = entry.size {
                                    Text(ByteCountFormatter.string(
                                        fromByteCount: size, countStyle: .file
                                    ))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if transfers.isDownloadingSFTP(server: server, entry: entry) ||
                                streaming.contains(entry.id) {
                                ProgressView()
                            } else {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(
                        transfers.isDownloadingSFTP(server: server, entry: entry) ||
                        streaming.contains(entry.id) || mutating
                    )
                }
            }
        }
        .navigationTitle(directory == server.rootPath ? server.title : (directory as NSString).lastPathComponent)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if mutating { ProgressView() }
                Menu {
                    Button {
                        folderName = ""
                        creatingFolder = true
                    } label: {
                        Label("Новая папка", systemImage: "folder.badge.plus")
                    }
                    Button {
                        uploading = true
                    } label: {
                        Label("Загрузить файлы на SFTP", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(mutating)
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(loading || mutating)
                .accessibilityLabel("Обновить папку SFTP")
            }
        }
        .refreshable { await reload() }
        .task { await reload() }
        .fileImporter(
            isPresented: $uploading,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): Task { await uploadFiles(urls) }
            case .failure(let error): errorText = error.localizedDescription
            }
        }
        .alert("Новая папка SFTP", isPresented: $creatingFolder) {
            TextField("Название папки", text: $folderName)
            Button("Создать") { Task { await createDirectory() } }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog(
            "Удалить \(deleteTarget?.name ?? "элемент") с SFTP?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ), titleVisibility: .visible
        ) {
            Button("Удалить с сервера", role: .destructive) {
                if let entry = deleteTarget { Task { await remove(entry) } }
                deleteTarget = nil
            }
        } message: {
            Text("Папку можно удалить только если она пуста. Операция необратима.")
        }
        .alert("SFTP", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    private func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        var connection: SFTPConnection?
        do {
            let password = try sftp.password(for: server)
            let active = try await SFTPConnection.connect(
                server: server, password: password
            )
            connection = active
            let entries = try await active.list(directory: directory)
            await active.close()
            connection = nil
            files = entries
            errorText = nil
        } catch {
            if let connection { await connection.close() }
            files = []
            errorText = error.localizedDescription
        }
    }

    private func createDirectory() async {
        guard !mutating else { return }
        mutating = true
        var connection: SFTPConnection?
        do {
            let password = try sftp.password(for: server)
            let active = try await SFTPConnection.connect(server: server, password: password)
            connection = active
            try await active.createDirectory(named: folderName, in: directory)
            await active.close()
            connection = nil
            await reload()
        } catch {
            if let connection { await connection.close() }
            errorText = error.localizedDescription
        }
        mutating = false
    }

    private func remove(_ entry: SFTPEntry) async {
        guard !mutating else { return }
        mutating = true
        var connection: SFTPConnection?
        do {
            let password = try sftp.password(for: server)
            let active = try await SFTPConnection.connect(server: server, password: password)
            connection = active
            try await active.remove(entry)
            await active.close()
            connection = nil
            await reload()
        } catch {
            if let connection { await connection.close() }
            errorText = error.localizedDescription
        }
        mutating = false
    }

    private func uploadFiles(_ urls: [URL]) async {
        guard !mutating else { return }
        mutating = true
        var connection: SFTPConnection?
        do {
            let password = try sftp.password(for: server)
            let active = try await SFTPConnection.connect(server: server, password: password)
            connection = active
            for url in urls {
                try await active.upload(localURL: url, in: directory)
            }
            await active.close()
            connection = nil
            await reload()
        } catch {
            if let connection { await connection.close() }
            errorText = error.localizedDescription
        }
        mutating = false
    }

    private func playStream(_ entry: SFTPEntry) async {
        guard !streaming.contains(entry.id) else { return }
        streaming.insert(entry.id)
        defer { streaming.remove(entry.id) }
        do {
            let password = try sftp.password(for: server)
            let source = try await SFTPRangeStream.open(
                server: server, password: password, entry: entry
            )
            library.playSFTP(source, title: entry.name)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func transfer(_ entry: SFTPEntry, play: Bool) {
        transfers.enqueueSFTP(
            server: server, entry: entry,
            playWhenFinished: play, library: library
        )
    }
}
