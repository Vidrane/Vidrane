import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var transfers: TransferCenter

    var body: some View {
        List {
            if transfers.records.isEmpty {
                EmptyLibraryState(
                    symbol: "arrow.down.circle",
                    title: "Загрузок пока нет",
                    detail: "Добавьте HTTPS-ссылку или скачайте файл через WebDAV либо SFTP во вкладке «Сеть»."
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
                            Text("\(item.source) · \(item.status.description)")
                                .font(.caption)
                                .foregroundColor(item.status == .failed ? .red : .secondary)
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
                        Button {
                            transfers.retry(item.id)
                        } label: {
                            Label("Повторить", systemImage: "arrow.clockwise")
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
