# Техническая документация ScreenSaver

## 1. Защита от «Зомби-режима» AccessibilityService (Android / Xiaomi HyperOS)

На прошивках Xiaomi HyperOS / MIUI и некоторых других OEM-оболочках система может принудительно выгрузить фоновый процесс `AccessibilityService` спустя несколько дней, оставив переключатель в системных настройках во включенном состоянии.

В проекте реализованы 4 уровня защиты от этой проблемы:
1. **Device Protected Storage (`createDeviceProtectedStorageContext`)**: `SettingsManager` хранит настройки в системном разделе памяти, доступном даже до первой разблокировки экрана после перезагрузки (Direct Boot), исключая падение сервиса при старте ОС.
2. **Удержание через `ForegroundService` (`FOREGROUND_SERVICE_TYPE_SPECIAL_USE`)**: `BlackScreenAccessibilityService` поднимает приоритет процесса до уровня активного Foreground-сервиса с минимальным тихим уведомлением и флагом `START_STICKY`.
3. **Честная проверка работы в ОЗУ**: `MainActivity` проверяет `BlackScreenAccessibilityService.isRunning` и отличает реальную работу в памяти от «Зомби-состояния».
4. **Автоматическая самореанимация (`ServiceReviver`)**: если приложению выдано разрешение `WRITE_SECURE_SETTINGS` по ADB, то при любом сбое приложение или нажатие на плитку в шторке автоматически перезапускает службу за 150 мс без участия пользователя:

       adb shell pm grant com.screensaver.screen_saver android.permission.WRITE_SECURE_SETTINGS