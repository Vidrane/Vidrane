import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var transfers: TransferCenter

    var body: some View {
        List {
            if transfers.records.isEmpty {
                EmptyLibraryState(
                    symbol: "arrow.down.circle",
                    title: "Загрузок пока нет",
                    detail: "Добавьте прямую HTTPS-ссылку во вкладке «Сеть» либо скачайте файл через WebDAV."
                )
                .listRowBackground(Color.clear)
            }
            ForEach(transfers.records) { item in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: item.status == .finished
                              ? "checkmark.circle.fill" : "arrow.down.circle")
                            .foregroundStyle(VidraneStyle.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).lineLimit(1)
                            Text(item.status.description)
                                .font(.caption)
                                .foregroundStyle(item.status == .failed ? .red : .secondary)
                        }
                        Spacer()
                        if item.status == .running {
                            Button {
                                transfers.cancel(item.id)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .accessibilityLabel("Отменить загрузку")
                        } else if item.status == .failed || item.status == .cancelled {
                            Button {
                                transfers.retry(item.id)
                            } label: {
                                Image(systemName: "arrow.clockwise.circle")
                            }
                            .accessibilityLabel("Повторить загрузку")
                        }
                    }

                    if item.status == .running {
                        if let progress = item.fraction {
                            ProgressView(value: progress)
                                .tint(VidraneStyle.accent)
                            Text("\(Int(progress * 100))% · \(ByteCountFormatter.string(fromByteCount: item.receivedBytes, countStyle: .file))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                            Text(ByteCountFormatter.string(fromByteCount: item.receivedBytes, countStyle: .file))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let error = item.error {
                        Text(error).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .contextMenu {
                    if item.status == .failed || item.status == .cancelled {
                        Button("Повторить", systemImage: "arrow.clockwise") {
                            transfers.retry(item.id)
                        }
                    }
                    Button(role: .destructive) {
                        transfers.remove(item.id)
                    } label: {
                        Label("Удалить из списка", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Загрузки")
    }
}
