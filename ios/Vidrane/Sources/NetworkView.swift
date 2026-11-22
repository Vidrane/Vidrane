import SwiftUI

struct NetworkView: View {
    @EnvironmentObject private var library: MediaLibrary
    @State private var url = ""

    private let futureProtocols: [(String, String)] = [
        ("SMB / CIFS", "Общий доступ к папкам"),
        ("SFTP / FTP", "Удалённые файловые серверы"),
        ("WebDAV", "Удалённые каталоги"),
        ("NFS", "Сетевые файловые системы"),
        ("DLNA / UPnP", "Устройства в локальной сети")
    ]

    var body: some View {
        Form {
            Section {
                TextField("https://server.example/video.mp4", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    library.playRemote(url)
                } label: {
                    Label("Открыть поток", systemImage: "play.fill")
                }
                Button {
                    library.download(url)
                } label: {
                    Label("Скачать файл", systemImage: "arrow.down.circle")
                }
            } header: {
                Text("Прямая HTTPS-ссылка")
            } footer: {
                Text("На первом этапе доступны прямые HTTPS-потоки и загрузки. Произвольные серверы и учётные данные пока не подключены.")
            }

            Section("Сетевые подключения — в разработке") {
                ForEach(futureProtocols, id: \.0) { title, detail in
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundStyle(.secondary)
                            .frame(width: 26)
                        VStack(alignment: .leading) {
                            Text(title)
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Позже").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle("Сеть")
    }
}
