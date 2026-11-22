import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var library: MediaLibrary

    var body: some View {
        List {
            if library.downloads.isEmpty {
                EmptyLibraryState(symbol: "arrow.down.circle", title: "Загрузок пока нет",
                                  detail: "Вставьте прямую HTTPS-ссылку на файл во вкладке «Сеть».")
                    .listRowBackground(Color.clear)
            }
            ForEach(library.downloads) { item in
                HStack(spacing: 14) {
                    Image(systemName: item.status == "Готово" ? "checkmark.circle" : "arrow.down.circle")
                        .foregroundStyle(VidraneStyle.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).lineLimit(1)
                        Text(item.status).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Загрузки")
    }
}
