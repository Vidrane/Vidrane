import SwiftUI

struct SettingsView: View {
    @AppStorage("showExtensions") private var showExtensions = true
    @AppStorage("keepScreenOn") private var keepScreenOn = true
    @AppStorage("playbackRate") private var playbackRate = 1.0
    @AppStorage("playerPresentation") private var playerPresentation = PlayerPresentation.vidrane.rawValue
    @AppStorage("resumePlayback") private var resumePlayback = true
    @AppStorage("videoScaling") private var videoScaling = VideoScaling.fit.rawValue
    @AppStorage("decoderPreference") private var decoderPreference = DecoderPreference.automatic.rawValue
    @AppStorage("mpvHardwareDecode") private var mpvHardwareDecode = "videotoolbox"
    @AppStorage("subtitleFontSize") private var subtitleFontSize = 24.0
    @AppStorage("subtitleDelay") private var subtitleDelay = 0.0
    @AppStorage("subtitleBackground") private var subtitleBackground = true
    @State private var confirmingClearHistory = false

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
                Toggle("Продолжать просмотр с места остановки", isOn: $resumePlayback)
                Picker("Размер видео в Vidrane", selection: $videoScaling) {
                    ForEach(VideoScaling.allCases) { scaling in
                        Text(scaling.title).tag(scaling.rawValue)
                    }
                }
                Button(role: .destructive) {
                    confirmingClearHistory = true
                } label: {
                    Label("Очистить историю просмотра", systemImage: "trash")
                }
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
                Picker("Медиадвижок", selection: $decoderPreference) {
                    Text(DecoderPreference.automatic.title)
                        .tag(DecoderPreference.automatic.rawValue)
                    Text(DecoderPreference.avFoundation.title)
                        .tag(DecoderPreference.avFoundation.rawValue)
                    if PlaybackDecoderAvailability.hasLibmpv {
                        Text(DecoderPreference.libmpv.title)
                            .tag(DecoderPreference.libmpv.rawValue)
                    }
                }
                LabeledContent(
                    "libmpv установлен",
                    value: PlaybackDecoderAvailability.hasLibmpv ? "Да" : "Нет"
                )
                if PlaybackDecoderAvailability.hasLibmpv {
                    Picker("libmpv: декодирование", selection: $mpvHardwareDecode) {
                        Text("VideoToolbox (аппаратное)").tag("videotoolbox")
                        Text("Программное").tag("software")
                    }
                }
            } header: {
                Text("Декодер видео и аудио")
            } footer: {
                Text("В обеих основных IPA доступен libmpv. Автоматический режим ориентируется на расширение файла, а не гарантирует поддержку кодека. При выборе Apple Player автоматический режим использует AVFoundation. Принудительный libmpv показывает собственные элементы управления Vidrane, поскольку системный Apple Player не работает с libmpv. Изменение аппаратного декодирования применяется к следующему видео.")
            }

            Section("Внешние субтитры") {
                Picker("Размер шрифта", selection: $subtitleFontSize) {
                    Text("18 pt").tag(18.0)
                    Text("22 pt").tag(22.0)
                    Text("24 pt").tag(24.0)
                    Text("28 pt").tag(28.0)
                    Text("32 pt").tag(32.0)
                }
                Toggle("Затемнять фон текста", isOn: $subtitleBackground)
                Stepper(
                    "Задержка: \(String(format: "%+.1f", subtitleDelay)) с",
                    value: $subtitleDelay,
                    in: -10.0...10.0,
                    step: 0.5
                )
                Button("Сбросить задержку") { subtitleDelay = 0 }
                Text("Поддерживаются внешние UTF-8 SRT и WebVTT. Файл рядом с видео подхватывается автоматически, если совпадает основное имя. Внешние субтитры выводятся поверх видео, но не передаются в системный PiP.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Профиль сборки", value: signingProfile.capitalized)
                LabeledContent("Rust ABI", value: String(vidrane_api_version()))
                LabeledContent("AVFoundation", value: "Системный")
                LabeledContent(
                    "libmpv / FFmpeg",
                    value: PlaybackDecoderAvailability.hasLibmpv ? "Включён в сборку" : "Не включён"
                )
                LabeledContent("PiP", value: "Apple и Vidrane / при поддержке iOS")
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
        .confirmationDialog(
            "Удалить все сохранённые позиции воспроизведения?",
            isPresented: $confirmingClearHistory
        ) {
            Button("Удалить историю", role: .destructive) {
                WatchHistory.shared.clearAll()
            }
        }
    }
}
