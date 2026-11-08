# Техническая документация ScreenSaver

## 1. Архитектура решения

1. **Flutter UI (`lib/main.dart`)**:
   - Адаптивный мобильный интерфейс (Material 3 Dark), оптимизированный под управление одной рукой и узкие экраны.
   - Пошаговый мастер снятия блокировки `RESTRICTED_SETTINGS` для Android 13+ (`sdkInt >= 33`).
   - Встроенный OTA-клиент обновлений через GitHub Releases API (`Bra1nButter/ScreenSaver`).

2. **Нативное ядро Android (`android/app/src/main/kotlin/com/screensaver/screen_saver/`)**:
   - `MainActivity.kt` — обрабатывает вызовы `MethodChannel('com.screensaver/native')`, включая прямой вызов `Settings.ACTION_APPLICATION_DETAILS_SETTINGS` (`openAppDetailsSettings`) для снятия «Ограниченных настроек» в Android 13+.
   - `BlackScreenAccessibilityService.kt` — полноэкранный слой `TYPE_ACCESSIBILITY_OVERLAY` с удержанием `FLAG_KEEP_SCREEN_ON`, минимальной яркостью подсветки (`0.0f`), обработкой мультитача, свайпов, кнопок громкости и мгновенным пробуждением по кнопке питания через `PowerManager.ACQUIRE_CAUSES_WAKEUP`.
   - `BlackScreenTileService.kt` — системная плитка `TileService` в шторке быстрых настроек.
   - `ApkFileProvider.kt` — собственный `ContentProvider` для передачи скачанных обновлений системному установщику пакетов.

## 2. Выпуск обновлений (CI/CD)

Для публикации новой версии выполните в PowerShell:

    .\release.ps1 1.0.2 "Улучшена мобильная верстка и добавлен мастер настройки для Android 13+"