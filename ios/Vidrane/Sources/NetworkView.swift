import SwiftUI

struct NetworkView: View {
    @EnvironmentObject private var library: MediaLibrary
    @EnvironmentObject private var webdav: WebDAVStore
    @EnvironmentObject private var sftpStore: SFTPStore
    @EnvironmentObject private var smbStore: SMBStore
    @EnvironmentObject private var transfers: TransferCenter
    @State private var directURL = ""
    @State private var addingWebDAV = false
    @State private var addingSFTP = false
    @State private var addingSMB = false

    private let planned: [(String, String)] = [
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
                Text("WebDAV поддерживает защищённые HTTPS-подключения, загрузку и просмотр MP4/MOV/M4V и совместимого аудио по HTTP Range без сохранения файла. Для серверов без Range остаётся скачивание.")
            }

            Section {
                ForEach(sftpStore.servers) { server in
                    NavigationLink {
                        SFTPBrowserView(server: server, directory: server.rootPath)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.title)
                                Text("\(server.username)@\(server.host):\(server.port)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(VidraneStyle.accent)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { sftpStore.remove(server) } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
                Button {
                    addingSFTP = true
                } label: {
                    Label("Добавить SFTP", systemImage: "plus")
                }
            } header: {
                Text("SFTP / SSH")
            } footer: {
                Text("SSH-ключ сервера должен быть проверен и указан заранее. Пароль хранится в Keychain.")
            }

            Section {
                ForEach(smbStore.servers) { server in
                    NavigationLink {
                        SMBBrowserView(server: server, directory: server.root)
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(server.title)
                                Text("\(server.host)/\(server.share)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "externaldrive")
                                .foregroundStyle(VidraneStyle.accent)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { smbStore.remove(server) } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
                Button {
                    addingSMB = true
                } label: {
                    Label("Добавить SMB", systemImage: "plus")
                }
            } header: {
                Text("SMB2/3")
            } footer: {
                Text("Для подключения необходимо SMB3-шифрование. Учётные данные хранятся в Keychain.")
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
        .sheet(isPresented: $addingSFTP) {
            NavigationStack {
                SFTPAddView()
            }
        }
        .sheet(isPresented: $addingSMB) {
            NavigationStack {
                SMBAddView()
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
    @EnvironmentObject private var transfers: TransferCenter

    let server: WebDAVServer
    let directory: URL

    @State private var entries: [WebDAVEntry] = []
    @State private var loading = false
    @State private var mutating = false
    @State private var errorText: String?
    @State private var addingFolder = false
    @State private var folderName = ""
    @State private var uploading = false
    @State private var openingStream: Set<URL> = []
    @State private var renameTarget: WebDAVEntry?
    @State private var renameText = ""
    @State private var deleteTarget: WebDAVEntry?

    private enum Change {
        case createFolder(String)
        case rename(WebDAVEntry, String)
        case duplicate(WebDAVEntry)
        case delete(WebDAVEntry)
    }

    var body: some View {
        List {
            if (loading || mutating) && entries.isEmpty {
                HStack {
                    Spacer()
                    ProgressView(mutating ? "Выполнение операции" : "Получение каталога")
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
                    .contextMenu { changeMenu(for: entry) }
                } else {
                    Menu {
                        Button {
                            transfer(entry, play: false)
                        } label: {
                            Label("Скачать в медиатеку", systemImage: "arrow.down.circle")
                        }
                        if VidraneMediaKind(filename: entry.name).playable {
                            if WebDAVRangeStream.allowedExtensions.contains(
                                entry.url.pathExtension.lowercased()
                            ) {
                                Button {
                                    Task { await playStream(entry) }
                                } label: {
                                    Label("Воспроизвести без скачивания", systemImage: "play.rectangle")
                                }
                            }
                            Button {
                                transfer(entry, play: true)
                            } label: {
                                Label("Скачать и воспроизвести", systemImage: "play.circle")
                            }
                        }
                        changeMenu(for: entry)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: VidraneMediaKind(filename: entry.name).symbol)
                                .foregroundStyle(VidraneStyle.accent)
                                .frame(width: 25)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name)
                                    .lineLimit(1)
                                    .foregroundStyle(.primary)
                                if let size = entry.size {
                                    Text(
                                        ByteCountFormatter.string(
                                            fromByteCount: size,
                                            countStyle: .file
                                        )
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if transfers.isDownloading(entry.url) ||
                                openingStream.contains(entry.url) {
                                ProgressView()
                            } else {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(
                        transfers.isDownloading(entry.url) ||
                        openingStream.contains(entry.url) || mutating
                    )
                }
            }
        }
        .navigationTitle(directory == server.root ? server.title : directory.lastPathComponent)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if mutating { ProgressView() }
                Menu {
                    Button {
                        folderName = ""
                        addingFolder = true
                    } label: {
                        Label("Новая папка", systemImage: "folder.badge.plus")
                    }
                    Button {
                        uploading = true
                    } label: {
                        Label("Загрузить файлы на сервер", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(mutating)
                .accessibilityLabel("Добавить на WebDAV")

                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(loading || mutating)
                .accessibilityLabel("Обновить каталог")
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
            case .success(let urls):
                Task { await uploadFiles(urls) }
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
        .alert("Новая папка WebDAV", isPresented: $addingFolder) {
            TextField("Название папки", text: $folderName)
            Button("Создать") {
                Task { await perform(.createFolder(folderName)) }
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Переименовать на сервере", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Новое название", text: $renameText)
            Button("Сохранить") {
                if let entry = renameTarget {
                    Task { await perform(.rename(entry, renameText)) }
                }
                renameTarget = nil
            }
            Button("Отмена", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog(
            "Удалить \(deleteTarget?.name ?? "элемент") с WebDAV?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить с сервера", role: .destructive) {
                if let entry = deleteTarget {
                    Task { await perform(.delete(entry)) }
                }
                deleteTarget = nil
            }
        } message: {
            Text("Если это папка, сервер может удалить всё её содержимое. Отменить операцию невозможно.")
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

    @ViewBuilder
    private func changeMenu(for entry: WebDAVEntry) -> some View {
        Button {
            renameTarget = entry
            renameText = entry.name
        } label: {
            Label("Переименовать", systemImage: "pencil")
        }
        Button {
            Task { await perform(.duplicate(entry)) }
        } label: {
            Label("Создать копию", systemImage: "doc.on.doc")
        }
        Button(role: .destructive) {
            deleteTarget = entry
        } label: {
            Label("Удалить с сервера", systemImage: "trash")
        }
    }

    private func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let access = try webdav.access(server)
            entries = try await WebDAVClient.shared.list(
                directory: directory, access: access
            )
            errorText = nil
        } catch {
            entries = []
            errorText = error.localizedDescription
        }
    }

    private func perform(_ change: Change) async {
        guard !mutating else { return }
        mutating = true
        defer { mutating = false }
        do {
            let access = try webdav.access(server)
            switch change {
            case .createFolder(let name):
                try await WebDAVClient.shared.createDirectory(
                    named: name, in: directory, access: access
                )
            case .rename(let entry, let name):
                try await WebDAVClient.shared.transfer(
                    entry, into: directory, named: name,
                    copy: false, access: access
                )
            case .duplicate(let entry):
                let ext = entry.isDirectory ? "" : (entry.name as NSString).pathExtension
                let stem = ext.isEmpty ? entry.name : (entry.name as NSString).deletingPathExtension
                let duplicate = "\(stem) (копия)" + (ext.isEmpty ? "" : ".\(ext)")
                try await WebDAVClient.shared.transfer(
                    entry, into: directory, named: duplicate,
                    copy: true, access: access
                )
            case .delete(let entry):
                try await WebDAVClient.shared.delete(entry, access: access)
            }
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func uploadFiles(_ urls: [URL]) async {
        guard !mutating else { return }
        mutating = true
        defer { mutating = false }
        do {
            let access = try webdav.access(server)
            for url in urls {
                try await WebDAVClient.shared.upload(url, in: directory, access: access)
            }
            await reload()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func playStream(_ entry: WebDAVEntry) async {
        guard !openingStream.contains(entry.url) else { return }
        openingStream.insert(entry.url)
        defer { openingStream.remove(entry.url) }
        do {
            let access = try webdav.access(server)
            let source = try await WebDAVRangeStream.open(file: entry, access: access)
            library.playWebDAV(source, title: entry.name)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func transfer(_ entry: WebDAVEntry, play: Bool) {
        do {
            let access = try webdav.access(server)
            try transfers.enqueue(
                url: entry.url,
                filename: entry.name,
                source: "WebDAV",
                authorization: access.authorizationHeader,
                playWhenFinished: play,
                library: library
            )
        } catch {
            errorText = error.localizedDescription
        }
    }
}
