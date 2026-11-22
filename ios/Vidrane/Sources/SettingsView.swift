import SwiftUI

struct SettingsView: View {
    @AppStorage("showExtensions") private var showExtensions = true
    @AppStorage("keepScreenOn") private var keepScreenOn = true
    @AppStorage("playbackRate") private var playbackRate = 1.0
    @AppStorage("playerPresentation") private var playerPresentation = PlayerPresentation.vidrane.rawValue

    private var signingProfile: String {
        (Bundle.main.object(forInfoDictionaryKey: "VidraneSigningProfile") as? String) ?? "Unknown"
    }

    private var selection: PlayerPresentation {
        PlayerPresentation(rawValue: playerPresentation) ?? .vidrane
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
                Text("По умолчанию используется Vidrane Player. Здесь можно выбрать Apple Player для следующих воспроизведений. Переключение через меню «Плеер» во время просмотра действует только для текущего сеанса. Оба интерфейса используют AVFoundation, а системный PiP доступен в режиме Apple на совместимых устройствах.")
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
