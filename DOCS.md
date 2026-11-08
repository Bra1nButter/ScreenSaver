# Техническая документация ScreenSaver

## 1. Механизм внутриприложенческого обновления (OTA)

1. При запуске приложение запрашивает `https://api.github.com/repos/Bra1nButter/ScreenSaver/releases/latest`.
2. Если версия `tag_name` на GitHub выше текущей (`PackageManager.getPackageInfo`), отображается карточка обновления.
3. Скачивание идет во временный файл `.part` внутри `cacheDir/updates` с проверкой целостности.
4. Нативный `ApkFileProvider` формирует `content://` URI и запускает системный установщик `application/vnd.android.package-archive`.
5. Если разрешение `REQUEST_INSTALL_PACKAGES` еще не выдано, открывается системное окно разрешения, а после возврата пользователя в приложение установка запускается автоматически в `MainActivity.onResume()`.

## 2. Настройка GitHub Secrets для единой подписи APK

Чтобы сборки из GitHub Actions устанавливались поверх локальных сборок без конфликта подписей, добавьте в настройки репозитория (`Settings -> Secrets and variables -> Actions -> New repository secret`) 4 секрета:

- `KEYSTORE_BASE64` — содержимое файла `keystore_base64.txt` (сгенерирован в корне проекта).
- `STORE_PASSWORD` — `ScreenSaverStore2026`
- `KEY_PASSWORD` — `ScreenSaverKey2026`
- `KEY_ALIAS` — `screensaver`