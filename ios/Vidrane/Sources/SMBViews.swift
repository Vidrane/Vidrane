import SwiftUI

struct SMBAddView: View {
    @EnvironmentObject private var store: SMBStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var host = ""
    @State private var port = "445"
    @State private var share = ""
    @State private var domain = ""
    @State private var user = ""
    @State private var password = ""
    @State private var root = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section("Общая папка SMB2/3") {
                TextField("Название", text: $name)
                TextField("Сервер, IP или hostname", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Порт (445)", text: $port).keyboardType(.numberPad)
                TextField("Имя SMB-ресурса (share)", text: $share)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Каталог внутри ресурса (необязательно)", text: $root)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("Авторизация") {
                TextField("Домен (необязательно)", text: $domain)
                TextField("Имя пользователя", text: $user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Пароль", text: $password)
            }
            Section {
                Label("Требуется SMB3 с шифрованием. SMB1 и незашифрованные подключения не используются.", systemImage: "lock.shield")
                    .font(.footnote)
            } header: {
                Text("Безопасность")
            } footer: {
                Text("Пароль сохраняется в Keychain. Для локальных сетевых ресурсов iOS может запросить доступ к локальной сети.")
            }
            Button("Сохранить SMB") {
                do {
                    try store.add(
                        title: name, host: host, port: Int(port) ?? 0,
                        share: share, domain: domain, username: user,
                        password: password, root: root
                    )
                    password = ""
                    dismiss()
                } catch {
                    self.error = error.localizedDescription
                }
            }
            .disabled(host.isEmpty || share.isEmpty || user.isEmpty)
        }
        .navigationTitle("Новый SMB")
        .toolbar {
            Button("Закрыть") { dismiss() }
        }
        .alert("SMB", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }
}

struct SMBBrowserView: View {
    @EnvironmentObject private var store: SMBStore
    @EnvironmentObject private var library: MediaLibrary
    let server: SMBServer
    let directory: String

    @State private var files: [SMBEntry] = []
    @State private var loading = false
    @State private var transferring: Set<String> = []
    @State private var message: String?
    @State private var newFolder = false
    @State private var folderName = ""
    @State private var removing: SMBEntry?
    @State private var busy = false

    var body: some View {
        List {
            if loading && files.isEmpty {
                ProgressView("Подключение к SMB")
            } else if files.isEmpty {
                EmptyLibraryState(
                    symbol: "externaldrive",
                    title: "Нет файлов",
                    detail: "Папка пуста или сервер вернул ошибку."
                )
            }
            ForEach(files) { entry in
                if entry.isDirectory {
                    NavigationLink {
                        SMBBrowserView(server: server, directory: entry.path)
                    } label: {
                        Label(entry.name, systemImage: "folder")
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            removing = entry
                        } label: {
                            Label("Удалить пустую папку", systemImage: "trash")
                        }
                    }
                } else {
                    Menu {
                        Button {
                            Task { await download(entry, play: false) }
                        } label: {
                            Label("Скачать в медиатеку", systemImage: "arrow.down.circle")
                        }
                        if VidraneMediaKind(filename: entry.name).playable {
                            Button {
                                Task { await playWithMPV(entry) }
                            } label: {
                                Label("Воспроизвести через libmpv", systemImage: "film")
                            }
                            Button {
                                Task { await download(entry, play: true) }
                            } label: {
                                Label("Скачать и воспроизвести", systemImage: "play.circle")
                            }
                        }
                        Button(role: .destructive) { removing = entry } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: VidraneMediaKind(filename: entry.name).symbol)
                                .foregroundStyle(VidraneStyle.accent)
                                .frame(width: 25)
                            VStack(alignment: .leading) {
                                Text(entry.name).foregroundStyle(.primary)
                                if let size = entry.size {
                                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if transferring.contains(entry.id) { ProgressView() }
                            else { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                        }
                    }
                    .disabled(transferring.contains(entry.id) || busy)
                }
            }
        }
        .navigationTitle(directory == server.root ? server.title : (directory as NSString).lastPathComponent)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if busy { ProgressView() }
                Menu {
                    Button {
                        folderName = ""
                        newFolder = true
                    } label: {
                        Label("Создать папку", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(busy)
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(loading || busy)
            }
        }
        .refreshable { await reload() }
        .task { await reload() }
        .alert("Новая папка SMB", isPresented: $newFolder) {
            TextField("Название папки", text: $folderName)
            Button("Создать") { Task { await makeDirectory() } }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog(
            "Удалить \(removing?.name ?? "элемент")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Удалить с сервера", role: .destructive) {
                if let entry = removing { Task { await delete(entry) } }
                removing = nil
            }
        } message: {
            Text("Удаление файлов безвозвратно. Папка удаляется только пустой.")
        }
        .alert("SMB", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func withConnection<T>(_ perform: (SMBConnection) async throws -> T) async throws -> T {
        let secret = try store.password(for: server)
        let client = try await SMBConnection.connect(server: server, password: secret)
        do {
            let value = try await perform(client)
            await client.close()
            return value
        } catch {
            await client.close()
            throw error
        }
    }

    private func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            files = try await withConnection { try await $0.list(directory) }
            message = nil
        } catch {
            files = []
            message = error.localizedDescription
        }
    }

    private func playWithMPV(_ entry: SMBEntry) async {
        guard !transferring.contains(entry.id) else { return }
        transferring.insert(entry.id)
        defer { transferring.remove(entry.id) }
        do {
            let password = try store.password(for: server)
            let client = try await SMBConnection.connect(
                server: server, password: password
            )
            let size: Int64
            do {
                size = try await client.fileSize(entry)
            } catch {
                await client.close()
                throw error
            }
            let relay = try await MediaLoopbackRelay.start(
                source: SMBRemoteBytes(client: client, entry: entry, length: size),
                filename: entry.name
            )
            library.playRemoteMPV(relay, title: entry.name)
        } catch {
            message = error.localizedDescription
        }
    }

    private func download(_ entry: SMBEntry, play: Bool) async {
        guard !transferring.contains(entry.id) else { return }
        transferring.insert(entry.id)
        defer { transferring.remove(entry.id) }
        var tmp: URL?
        do {
            tmp = try await withConnection {
                try await $0.download(entry, progress: { _, _ in true })
            }
            guard let tmp else { throw SMBError.truncated }
            let file = try library.importRemoteFile(at: tmp, filename: entry.name)
            self.tmpCleanup(tmp)
            if play { library.play(file) }
        } catch {
            if let tmp { tmpCleanup(tmp) }
            message = error.localizedDescription
        }
    }

    private func tmpCleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func makeDirectory() async {
        guard !busy else { return }
        busy = true
        do {
            try await withConnection {
                try await $0.createDirectory(named: folderName, in: directory)
            }
            await reload()
        } catch { message = error.localizedDescription }
        busy = false
    }

    private func delete(_ entry: SMBEntry) async {
        guard !busy else { return }
        busy = true
        do {
            try await withConnection { try await $0.remove(entry) }
            await reload()
        } catch { message = error.localizedDescription }
        busy = false
    }
}
