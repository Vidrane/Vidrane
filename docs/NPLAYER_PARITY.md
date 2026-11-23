# Vidrane — сверка с nPlayer Plus

Базовая проверка: запись `ScreenRecording_11-23-2026 01-58-03_1.mp4`, 14:47 (23 ноября 2026), файлы `main` в коммите `fe1df8b3` (23 ноября 2026). Это **не** полный официальный список всех выпусков nPlayer: дополнительно проверять заявленные функции в ходе соответствующего этапа.

Статусы: **CODE** = сценарий реализован в исходниках (не означает тест на устройстве); **PARTIAL** = основная функция есть, но менее полная; **TODO** = нет пользовательской реализации; **REVIEW** = требует экспертизы iOS, зависимости или лицензии.

| Категория | Функция | Vidrane | Задача |
|---|---|---|---|
| Общая архитектура | Rust core/FFI | CODE | M00 |
| Сборки | Personal + Developer unsigned IPA с libmpv | CODE | M00/M13 |
| UI | Шесть вкладок | CODE | M11 |
| UI | Выбор тем, меню, цвета, quick actions | TODO | M11 |
| UI | Настройка вида списков, иконок, фильтров, бейджей новых файлов | PARTIAL | M05/M11 |
| UI | Локализация и доступность | PARTIAL | M11 |
| Security | Face ID/пароль и блокировка папок | TODO | M05 |
| Файлы | Вложенные каталоги, импорт, CRUD | CODE | M05 |
| Файлы | Множественный выбор/пакетные операции | TODO | M05 |
| Файлы | Корзина/избранное/скрытые файлы | TODO | M05 |
| Файлы | Фото, обложки, медиа-метаданные | PARTIAL | M05 |
| Файлы | Импорт Photos/iTunes/external folders | PARTIAL | M05 |
| Файлы | Архивы | TODO | M05 |
| Сеть | WebDAV HTTPS | CODE | M07 |
| Сеть | SFTP password+SSH host pinning | CODE | M07 |
| Сеть | SFTP SSH user public key auth | TODO | M07 |
| Сеть | SMB3 encrypted browse/read/mkdir/delete | CODE | M07 |
| Сеть | SMB upload/rename/share discovery/legacy | TODO/REVIEW | M07 |
| Сеть | FTP/FTPS | TODO | M07 |
| Сеть | NFS | TODO/REVIEW | M07 |
| Сеть | DLNA/UPnP/автопоиск LAN | TODO | M07 |
| Сеть | Облака Dropbox, OneDrive, Box, pCloud, Yandex Disk | TODO | M08 |
| Playback | AVFoundation с Vidrane controls | CODE | M01 |
| Playback | libmpv/FFmpeg в обеих IPA | CODE | M01 |
| Playback | MKV удалённо через Range relay | CODE | M01/M07 |
| Playback | Автовыбор по содержимому, fallback | PARTIAL | M01 |
| Playback | Resume/история | CODE | M01/M06 |
| Playback | Resume спрашивать/авто/нет | PARTIAL | M01 |
| Playback | Скорость до 4.0× | PARTIAL | M01 |
| Playback | Следующий/предыдущий, repeat, shuffle | PARTIAL | M01/M06 |
| Playback | PiP Apple | CODE | M01 |
| Playback | PiP libmpv | TODO/REVIEW | M02 |
| Видео | Zoom fit/fill | CODE | M02 |
| Видео | Соотношение сторон 4:3/16:9/1.85 и др. | TODO | M02 |
| Видео | Rotate/mirror, color space, deinterlace, postprocessing | TODO/REVIEW | M02 |
| Видео | Выбор hardware/software per-codec | PARTIAL | M02 |
| Видео | Seek thumbnails, A–B, lock controls, timer | TODO | M02 |
| Жесты | Двойной тап ±10 секунд | CODE | M02 |
| Жесты | Профили настраиваемых действий 1/2 пальца, brightness/volume/seek | TODO | M02 |
| Субтитры | Внешние UTF-8 SRT/VTT, задержка | CODE | M03 |
| Субтитры | Embedded track selection | CODE | M03 |
| Субтитры | ASS/SSA со стилями и bitmap PGS/VobSub | PARTIAL/REVIEW | M03 |
| Субтитры | Кодировки текста, выбор языка | TODO | M03 |
| Субтитры | Шрифты, цвет, тень, контур, положение, высота | PARTIAL | M03 |
| Субтитры | TTS и расширенные жесты | TODO/REVIEW | M03 |
| Аудио | Аудиодорожки | CODE | M04 |
| Аудио | Gain/latency/equalizer/ReplayGain | TODO | M04 |
| Аудио | Предпочтительный язык | TODO | M04 |
| Аудио | Dolby/DTS pass-through, HDMI/AirPlay/Chromecast | TODO/REVIEW | M04/M10 |
| Аудио | Mini-player, lyrics | TODO | M04 |
| Плейлисты | Создание/удаление/добавление файлов | CODE | M06 |
| Плейлисты | M3U/M3U8/PLS/CUE импорт/экспорт | TODO | M06 |
| Плейлисты | Recently played/visited, favorites | PARTIAL | M06 |
| Загрузки | Очередь HTTP/WebDAV/SFTP/SMB на диске | CODE | M09 |
| Загрузки | Resume при повторном открытии | CODE | M09 |
| Загрузки | Передачи при завершённом iOS приложении | PARTIAL/REVIEW | M09 |
| Загрузки | Очередь upload, pause, limits, speed ETA | PARTIAL | M09 |
| Браузер | HTTPS WKWebView | CODE | M10 |
| Браузер | Tabs/bookmarks/download detection/play in player | TODO | M10 |
| Внешние устройства | AirPlay/HDMI/Chromecast | PARTIAL/REVIEW | M10 |
| Платформы | Android/Windows/Linux/macOS | TODO | M14 |

## Проверенная навигация по видео

- 00:00–01:30: локальные файлы, сеть, серверы SFTP, облачные подключения и их настройка.
- 01:30–03:30: SFTP, удалённые файлы, MKV и базовое воспроизведение.
- 03:30–05:45: масштаб/соотношение сторон, дорожки, субтитры, декодер, PiP и карточка медиаданных.
- 06:00–08:45: плейлисты, встроенный браузер, темы, кодировки, параметры отображения списков и файлов.
- 08:45–10:05: ориентация, перемотка, resume, playback next, видеоопции/codec decoder.
- 10:05–11:05: аудиодорожки, усиление/задержка, языки, Dolby/DTS и варианты pass-through.
- 11:05–12:45: настройки языков, шрифтов, размеров, цвета/оформления субтитров, ASS/SSA.
- 12:45–13:45: назначение жестов одним и двумя пальцами, remote control.
- 13:45–14:47: лицензии и правовая информация.

Наличие настройки в nPlayer на видео **не доказывает**, что она технически доступна в любой конфигурации Vidrane/iOS. Статус `TODO` не подменять «готово» только из-за функции внутри FFmpeg/libmpv без пользовательского подключения. Не заявлять превосходство без измерений и реальных тестов.