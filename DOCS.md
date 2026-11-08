# Техническая документация ScreenSaver

## 1. Архитектура решения

Проект разделен на два слоя, взаимодействующих через `MethodChannel('com.screensaver/native')`:

1. **Flutter UI (`lib/main.dart`)**:
   - Отвечает за проверку разрешений (`AccessibilityService`, `IgnoreBatteryOptimizations`).
   - Автоматически обновляет статусы разрешений при возврате пользователя из системных настроек (`WidgetsBindingObserver`).
   - Управляет сохранением настроек и запуском 10-секундного тестового режима.

2. **Нативное ядро Android (`android/app/src/main/kotlin/...`)**:
   - `SettingsManager.kt` — потокобезопасное хранилище пользовательских настроек в `SharedPreferences`.
   - `BlackScreenAccessibilityService.kt` — системный сервис специальных возможностей.
   - `BlackScreenTileService.kt` — сервис плитки быстрых настроек в шторке Android (`TileService`).
   - `MainActivity.kt` — мост `MethodChannel` между Flutter и Android API.

## 2. Почему активное приложение не останавливается?

Когда создается окно через `WindowManager` с типом `TYPE_ACCESSIBILITY_OVERLAY`, используются следующие флаги:
- `FLAG_NOT_FOCUSABLE` — гарантирует, что нижележащее `Activity` (например, игра или плеер) **не теряет оконный фокус** (`onWindowFocusChanged` остается `true`), но при этом все касания экрана перехватываются нашим полноэкранным слоем.
- `FLAG_KEEP_SCREEN_ON` — запрещает Android уводить процессор и экран в физический сон по системному тайм-ауту.
- `screenBrightness = 0.0f` — временно переводит контроллер подсветки дисплея на минимальный уровень только на время отображения черного окна.

## 3. Защита от сброса AccessibilityService

В `AndroidManifest.xml` для сервиса заданы параметры:
- `android:stopWithTask="false"` — смахивание приложения из списка недавних (Recents) не останавливает сервис.
- `android:directBootAware="true"` — сервис готов к работе сразу после перезагрузки устройства.
- Дополнительно в UI выведена кнопка запроса `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, добавляющая приложение в белый список системного контроллера питания.