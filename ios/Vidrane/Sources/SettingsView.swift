import SwiftUI

struct SettingsView: View {
    @AppStorage("showExtensions") private var showExtensions = true
    @AppStorage("keepScreenOn") private var keepScreenOn = true
    @AppStorage("playbackRate") private var playbackRate = 1.0
    @AppStorage("playerPresentation") private var playerPresentation = PlayerPresentation.apple.rawValue

    private var signingProfile: String {
        (Bundle.main.object(forInfoDictionaryKey: "VidraneSigningProfile") as? String) ?? "Unknown"
    }

    private var selection: PlayerPresentation {
        PlayerPresentation(rawValue: playerPresentation) ?? .apple
    }

    var body: some View {
        Form {
            Section("Файлы") {
                Toggle("Показывать расширения", isOn: $showExtensions)
            }

            Section {
                Picker("Плеер по умолчанию", selection: $playerPresentation) {
                    ForEach(PlayerPresentation.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.navigationLink)
                LabeledContent("Текущий режим", value: selection.title)
                Text(selection.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("Не выключать экран во время просмотра", isOn: $keepScreenOn)
                Picker("Начальная скорость", selection: $playbackRate) {
                    Text("0,5×").tag(0.5)
                    Text("1×").tag(1.0)
                    Text("1,25×").tag(1.25)
                    Text("1,5×").tag(1.5)
                    Text("2×").tag(2.0)
                }
            } header: {
                Text("Воспроизведение")
            } footer: {
                Text("Apple Player включён по умолчанию. Режим можно сменить во время просмотра через меню «Плеер». Оба интерфейса используют AVFoundation: переключение не меняет набор поддерживаемых кодеков. Системный PiP доступен в режиме Apple, если его поддерживает устройство.")
            }

            Section {
                LabeledContent("Профиль сборки", value: signingProfile.capitalized)
                LabeledContent("Rust ABI", value: String(vidrane_api_version()))
                LabeledContent("Медиадвижок", value: "AVFoundation")
                LabeledContent("PiP", value: "Apple Player / при поддержке iOS")
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
