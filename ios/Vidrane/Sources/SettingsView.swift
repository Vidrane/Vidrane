import SwiftUI

struct SettingsView: View {
    @AppStorage("showExtensions") private var showExtensions = true
    @AppStorage("keepScreenOn") private var keepScreenOn = true
    @AppStorage("playbackRate") private var playbackRate = 1.0

    private var signingProfile: String {
        (Bundle.main.object(forInfoDictionaryKey: "VidraneSigningProfile") as? String) ?? "Unknown"
    }

    var body: some View {
        Form {
            Section("Файлы") {
                Toggle("Показывать расширения", isOn: $showExtensions)
            }
            Section("Воспроизведение") {
                Toggle("Не выключать экран во время просмотра", isOn: $keepScreenOn)
                Picker("Начальная скорость", selection: $playbackRate) {
                    Text("0,5×").tag(0.5)
                    Text("1×").tag(1.0)
                    Text("1,25×").tag(1.25)
                    Text("1,5×").tag(1.5)
                    Text("2×").tag(2.0)
                }
            }
            Section {
                LabeledContent("Профиль сборки", value: signingProfile.capitalized)
                LabeledContent("Rust ABI", value: String(vidrane_api_version()))
                LabeledContent("Медиадвижок", value: "AVFoundation")
                LabeledContent("PiP", value: "При поддержке iOS")
            } header: {
                Text("Системные возможности")
            } footer: {
                Text("Personal и Developer — способы подписи IPA, а не уровни доступа. iCloud, APNs и App Groups потребуют отдельных entitlement'ов и настройки профиля. Все реализованные функции Vidrane бесплатны.")
            }
            Section("О проекте") {
                Link("Исходный код GitHub", destination: URL(string: "https://github.com/Vidrane/Vidrane")!)
                LabeledContent("Версия", value: "0.1.0-dev")
                Text("Независимый открытый мультимедийный плеер. Новые протоколы и кодеки будут добавляться поэтапно.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .navigationTitle("Настройки")
    }
}
