import SwiftUI

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

    let server: SFTPServer
    let directory: String

    @State private var files: [SFTPEntry] = []
    @State private var loading = false
    @State private var downloading: Set<String> = []
    @State private var errorText: String?

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
                } else {
                    Menu {
                        Button {
                            Task { await download(entry, play: false) }
                        } label: {
                            Label("Скачать в медиатеку", systemImage: "arrow.down.circle")
                        }
                        if VidraneMediaKind(filename: entry.name).playable {
                            Button {
                                Task { await download(entry, play: true) }
                            } label: {
                                Label("Скачать и воспроизвести", systemImage: "play.circle")
                            }
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
                            if downloading.contains(entry.id) {
                                ProgressView()
                            } else {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(downloading.contains(entry.id))
                }
            }
        }
        .navigationTitle(directory == server.rootPath ? server.title : (directory as NSString).lastPathComponent)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(loading)
                .accessibilityLabel("Обновить папку SFTP")
            }
        }
        .refreshable { await reload() }
        .task { await reload() }
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

    private func download(_ entry: SFTPEntry, play: Bool) async {
        guard !downloading.contains(entry.id) else { return }
        downloading.insert(entry.id)
        defer { downloading.remove(entry.id) }
        var connection: SFTPConnection?
        var temporary: URL?
        do {
            let password = try sftp.password(for: server)
            let active = try await SFTPConnection.connect(
                server: server, password: password
            )
            connection = active
            temporary = try await active.download(entry)
            await active.close()
            connection = nil

            guard let downloaded = temporary else { throw SFTPError.incompleteTransfer }
            let local = try library.importRemoteFile(at: downloaded, filename: entry.name)
            temporary = nil
            if play { library.play(local) }
        } catch {
            if let connection { await connection.close() }
            errorText = error.localizedDescription
        }
        if let temporary { try? FileManager.default.removeItem(at: temporary) }
    }
}
