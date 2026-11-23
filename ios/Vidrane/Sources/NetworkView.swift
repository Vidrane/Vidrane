import SwiftUI

struct NetworkView: View {
    @EnvironmentObject private var library: MediaLibrary
    @EnvironmentObject private var webdav: WebDAVStore
    @State private var directURL = ""
    @State private var addingWebDAV = false

    private let planned: [(String, String)] = [
        ("SMB / CIFS", "Подключение к сетевым папкам"),
        ("SFTP / FTP", "Серверы и защищённый файловый доступ"),
        ("NFS", "Сетевые файловые системы"),
        ("DLNA / UPnP", "Обнаружение медиасерверов")
    ]

    var body: some View {
        Form {
            Section {
                TextField("https://server.example/video.mp4", text: $directURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    library.playRemote(directURL)
                } label: {
                    Label("Открыть поток", systemImage: "play.fill")
                }
                Button {
                    library.download(directURL)
                } label: {
                    Label("Скачать файл", systemImage: "arrow.down.circle")
                }
            } header: {
                Text("Прямая HTTPS-ссылка")
            } footer: {
                Text("Прямое воспроизведение требует формат, поддерживаемый AVFoundation. Адреса с паролем в URL не используются.")
            }

            Section {
                ForEach(webdav.servers) { server in
                    NavigationLink {
                        WebDAVFolderView(
                            server: server,
                            directory: server.root ?? URL(fileURLWithPath: "/")
                        )
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.title)
                                Text(server.baseURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: "externaldrive.connected.to.line.below")
                                .foregroundStyle(VidraneStyle.accent)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            webdav.remove(server)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }

                Button {
                    addingWebDAV = true
                } label: {
                    Label("Добавить WebDAV", systemImage: "plus")
                }
            } header: {
                Text("WebDAV")
            } footer: {
                Text("Поддерживаются HTTPS WebDAV, просмотр папок, Basic-авторизация и скачивание в локальную медиатеку. Пароли хранятся в Keychain. Прямое воспроизведение защищённых файлов пока не реализовано.")
            }

            Section("Другие протоколы — в разработке") {
                ForEach(planned.indices, id: \.self) { index in
                    let (title, description) = planned[index]
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundStyle(.secondary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Позже")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle("Сеть")
        .sheet(isPresented: $addingWebDAV) {
            NavigationStack {
                WebDAVAddView()
            }
        }
    }
}

struct WebDAVAddView: View {
    @EnvironmentObject private var webdav: WebDAVStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("Подключение") {
                TextField("Название (необязательно)", text: $title)
                TextField("https://host.example/dav/", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("Авторизация") {
                TextField("Логин (необязательно)", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Пароль", text: $password)
                Text("Пароль сохраняется в системном Keychain, а не в файле настроек.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Сохранить подключение") {
                    do {
                        try webdav.add(
                            title: title, address: address,
                            username: username, password: password
                        )
                        password = ""
                        dismiss()
                    } catch {
                        errorText = error.localizedDescription
                    }
                }
                .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Новый WebDAV")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Закрыть") { dismiss() }
            }
        }
        .alert("WebDAV", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }
}

struct WebDAVFolderView: View {
    @EnvironmentObject private var library: MediaLibrary
    @EnvironmentObject private var webdav: WebDAVStore

    let server: WebDAVServer
    let directory: URL

    @State private var entries: [WebDAVEntry] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var downloading: Set<String> = []

    var body: some View {
        List {
            if loading && entries.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Получение каталога")
                    Spacer()
                }
            } else if entries.isEmpty {
                EmptyLibraryState(
                    symbol: "externaldrive",
                    title: "Нет файлов",
                    detail: "Каталог пуст или сервер не предоставил список."
                )
                .listRowBackground(Color.clear)
            }

            ForEach(entries) { entry in
                if entry.isDirectory {
                    NavigationLink {
                        WebDAVFolderView(server: server, directory: entry.url)
                    } label: {
                        Label(entry.name, systemImage: "folder")
                            .foregroundStyle(.primary)
                    }
                } else {
                    Menu {
                        Button {
                            Task { await transfer(entry, play: false) }
                        } label: {
                            Label("Скачать в медиатеку", systemImage: "arrow.down.circle")
                        }
                        if VidraneMediaKind(filename: entry.name).playable {
                            Button {
                                Task { await transfer(entry, play: true) }
                            } label: {
                                Label("Скачать и воспроизвести", systemImage: "play.circle")
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: VidraneMediaKind(filename: entry.name).symbol)
                                .foregroundStyle(VidraneStyle.accent)
                                .frame(width: 25)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name).lineLimit(1)
                                    .foregroundStyle(.primary)
                                if let size = entry.size {
                                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
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
        .navigationTitle(directory == server.root ? server.title : directory.lastPathComponent)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(loading)
                .accessibilityLabel("Обновить каталог")
            }
        }
        .refreshable { await reload() }
        .task { await reload() }
        .alert("WebDAV", isPresented: Binding(
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
        do {
            let access = try webdav.access(server)
            entries = try await WebDAVClient.shared.list(directory: directory, access: access)
            errorText = nil
        } catch {
            entries = []
            errorText = error.localizedDescription
        }
    }

    private func transfer(_ entry: WebDAVEntry, play: Bool) async {
        guard !downloading.contains(entry.id) else { return }
        downloading.insert(entry.id)
        defer { downloading.remove(entry.id) }
        var temporary: URL?
        defer {
            if let temporary {
                try? FileManager.default.removeItem(at: temporary)
            }
        }
        do {
            let access = try webdav.access(server)
            temporary = try await WebDAVClient.shared.download(file: entry.url, access: access)
            guard let temp = temporary else { throw WebDAVError.invalidResponse }
            let local = try library.importRemoteFile(at: temp, filename: entry.name)
            temporary = nil
            if play { library.play(local) }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
