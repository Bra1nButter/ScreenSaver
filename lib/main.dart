import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const String kGithubOwner = 'Bra1nButter';
const String kGithubRepo = 'ScreenSaver';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ScreenSaverApp());
}

class ReleaseInfo {
  final String version;
  final String tagName;
  final String releaseNotes;
  final String downloadUrl;
  final String fileName;
  final int fileSize;

  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.fileName,
    required this.fileSize,
  });
}

class ScreenSaverApp extends StatelessWidget {
  const ScreenSaverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScreenSaver',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.tealAccent,
        scaffoldBackgroundColor: const Color(0xFF0E1116),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel('com.screensaver/native');

  bool _isAccessibilityEnabled = false;
  bool _isBatteryIgnored = false;
  String _appVersion = '1.0.0';
  int _appBuildNumber = 1;
  String _updatesDir = '';

  bool _wakeOnPowerInstant = true;
  bool _wakeOnDoubleTap = true;
  bool _wakeOnTripleTap = false;
  bool _wakeOnMultiTouch = true;
  int _multiTouchFingers = 3;
  bool _wakeOnSwipe = false;
  bool _wakeOnVolume = false;
  bool _wakeOnCall = true;
  bool _showIndicator = true;

  // Состояние системы автообновления
  bool _isCheckingUpdate = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _readyApkPath;
  String? _updateError;
  ReleaseInfo? _availableUpdate;
  HttpClient? _activeHttpClient;
  bool _initialCheckDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    await _refreshState();
    if (!_initialCheckDone) {
      _initialCheckDone = true;
      await _checkForUpdates(silent: true);
    }
  }

  @override
  void dispose() {
    _activeHttpClient?.close(force: true);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshState();
    }
  }

  Future<void> _refreshState() async {
    try {
      final Map<dynamic, dynamic>? data =
          await _channel.invokeMethod('getState');
      if (data == null || !mounted) return;

      final Map<dynamic, dynamic> s =
          (data['settings'] as Map<dynamic, dynamic>?) ?? {};

      setState(() {
        _isAccessibilityEnabled =
            (data['isAccessibilityEnabled'] as bool?) ?? false;
        _isBatteryIgnored = (data['isBatteryIgnored'] as bool?) ?? false;
        _appVersion = (data['versionName'] as String?) ?? '1.0.0';
        _appBuildNumber = ((data['versionCode'] as num?) ?? 1).toInt();
        _updatesDir = (data['updatesDir'] as String?) ?? '';

        _wakeOnPowerInstant = (s['wakeOnPowerInstant'] as bool?) ?? true;
        _wakeOnDoubleTap = (s['wakeOnDoubleTap'] as bool?) ?? true;
        _wakeOnTripleTap = (s['wakeOnTripleTap'] as bool?) ?? false;
        _wakeOnMultiTouch = (s['wakeOnMultiTouch'] as bool?) ?? true;
        _multiTouchFingers = (s['multiTouchFingers'] as int?) ?? 3;
        _wakeOnSwipe = (s['wakeOnSwipe'] as bool?) ?? false;
        _wakeOnVolume = (s['wakeOnVolume'] as bool?) ?? false;
        _wakeOnCall = (s['wakeOnCall'] as bool?) ?? true;
        _showIndicator = (s['showIndicator'] as bool?) ?? true;
      });
    } catch (e) {
      debugPrint('Error loading state: $e');
    }
  }

  Future<void> _saveSettings() async {
    await _channel.invokeMethod('saveSettings', {
      'wakeOnPowerInstant': _wakeOnPowerInstant,
      'wakeOnDoubleTap': _wakeOnDoubleTap,
      'wakeOnTripleTap': _wakeOnTripleTap,
      'wakeOnMultiTouch': _wakeOnMultiTouch,
      'multiTouchFingers': _multiTouchFingers,
      'wakeOnSwipe': _wakeOnSwipe,
      'wakeOnVolume': _wakeOnVolume,
      'wakeOnCall': _wakeOnCall,
      'showIndicator': _showIndicator,
    });
  }

  Future<void> _checkForUpdates({required bool silent}) async {
    if (_isCheckingUpdate || _isDownloading) return;

    setState(() {
      _isCheckingUpdate = true;
      _updateError = null;
    });

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$kGithubOwner/$kGithubRepo/releases/latest',
      );
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'ScreenSaver-Android-Updater');

      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();

      if (!mounted) return;

      if (resp.statusCode == 404) {
        setState(() => _isCheckingUpdate = false);
        if (!silent) {
          _showSnack('Релизов в репозитории пока нет (текущая v$_appVersion).');
        }
        return;
      }

      if (resp.statusCode == 403) {
        setState(() {
          _isCheckingUpdate = false;
          _updateError = 'Превышен лимит запросов GitHub API. Попробуйте позже.';
        });
        if (!silent) _showSnack(_updateError!);
        return;
      }

      if (resp.statusCode != 200) {
        throw HttpException('HTTP ${resp.statusCode}');
      }

      final Map<String, dynamic> json =
          jsonDecode(body) as Map<String, dynamic>;
      final String tagName = (json['tag_name'] as String?) ?? '';
      final String cleanVer = tagName.replaceFirst(RegExp(r'^[vV]'), '').trim();
      final String notes = (json['body'] as String?)?.trim() ?? '';
      final List<dynamic> assets = (json['assets'] as List<dynamic>?) ?? [];

      Map<String, dynamic>? selectedAsset;
      for (final item in assets) {
        if (item is Map<String, dynamic>) {
          final name = (item['name'] as String?)?.toLowerCase() ?? '';
          if (name.endsWith('.apk')) {
            selectedAsset = item;
            if (name.contains('arm64')) break;
          }
        }
      }

      if (selectedAsset == null) {
        setState(() => _isCheckingUpdate = false);
        if (!silent) {
          _showSnack('Релиз $tagName найден, но APK еще собирается в GitHub Actions.');
        }
        return;
      }

      if (_isNewerVersion(cleanVer, _appVersion)) {
        final fileName = (selectedAsset['name'] as String?) ?? 'update.apk';
        final fileSize = ((selectedAsset['size'] as num?) ?? 0).toInt();
        final downloadUrl =
            (selectedAsset['browser_download_url'] as String?) ?? '';

        String? existingPath;
        if (_updatesDir.isNotEmpty) {
          final cachedFile = File('$_updatesDir/$fileName');
          if (cachedFile.existsSync() &&
              (fileSize == 0 || cachedFile.lengthSync() == fileSize)) {
            existingPath = cachedFile.path;
          }
        }

        setState(() {
          _availableUpdate = ReleaseInfo(
            version: cleanVer,
            tagName: tagName,
            releaseNotes: notes,
            downloadUrl: downloadUrl,
            fileName: fileName,
            fileSize: fileSize,
          );
          _readyApkPath = existingPath;
          _isCheckingUpdate = false;
        });

        if (!silent) {
          _showSnack('Найдена новая версия: v$cleanVer!');
        }
      } else {
        await _channel.invokeMethod('cleanupOldApks', {'keepFileName': null});
        setState(() {
          _availableUpdate = null;
          _readyApkPath = null;
          _isCheckingUpdate = false;
        });
        if (!silent) {
          _showSnack('У вас установлена последняя версия (v$_appVersion).');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingUpdate = false;
        _updateError = 'Не удалось проверить обновления: $e';
      });
      if (!silent) {
        _showSnack('Ошибка сети при проверке обновлений.');
      }
    } finally {
      client.close();
    }
  }

  bool _isNewerVersion(String remote, String local) {
    List<int> parseParts(String v) {
      final clean = v.split('+').first.split('-').first;
      return clean
          .split('.')
          .map((e) => int.tryParse(e.trim()) ?? 0)
          .toList();
    }

    final r = parseParts(remote);
    final l = parseParts(local);
    final maxLen = r.length > l.length ? r.length : l.length;

    for (int i = 0; i < maxLen; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv > lv) return true;
      if (rv < lv) return false;
    }
    return false;
  }

  Future<void> _downloadAndInstallUpdate() async {
    final update = _availableUpdate;
    if (update == null || _isDownloading) return;

    if (_readyApkPath != null && File(_readyApkPath!).existsSync()) {
      await _triggerInstallApk(_readyApkPath!);
      return;
    }

    if (_updatesDir.isEmpty) {
      await _refreshState();
    }

    final targetFile = File('$_updatesDir/${update.fileName}');
    final partFile = File('$_updatesDir/${update.fileName}.part');

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadedBytes = 0;
      _totalBytes = update.fileSize;
      _updateError = null;
    });

    final client = HttpClient();
    _activeHttpClient = client;

    try {
      if (partFile.existsSync()) {
        partFile.deleteSync();
      }

      final req = await client.getUrl(Uri.parse(update.downloadUrl));
      req.headers.set(HttpHeaders.userAgentHeader, 'ScreenSaver-Android-Updater');
      final resp = await req.close();

      if (resp.statusCode != 200) {
        throw HttpException('Сервер вернул код ${resp.statusCode}');
      }

      final contentLen = resp.contentLength > 0 ? resp.contentLength : update.fileSize;
      final sink = partFile.openWrite();
      int received = 0;

      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        if (mounted) {
          setState(() {
            _downloadedBytes = received;
            _totalBytes = contentLen;
            if (contentLen > 0) {
              _downloadProgress = (received / contentLen).clamp(0.0, 1.0);
            }
          });
        }
      }

      await sink.flush();
      await sink.close();

      if (received < 100 * 1024) {
        throw const FileSystemException('Скачанный файл поврежден или слишком мал');
      }

      if (targetFile.existsSync()) {
        targetFile.deleteSync();
      }
      partFile.renameSync(targetFile.path);

      await _channel.invokeMethod('cleanupOldApks', {
        'keepFileName': update.fileName,
      });

      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _readyApkPath = targetFile.path;
      });

      await _triggerInstallApk(targetFile.path);
    } catch (e) {
      try {
        if (partFile.existsSync()) partFile.deleteSync();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _updateError = 'Сбой загрузки: $e';
      });
      _showSnack('Не удалось скачать обновление. Попробуйте еще раз.');
    } finally {
      _activeHttpClient = null;
      client.close();
    }
  }

  void _cancelDownload() {
    _activeHttpClient?.close(force: true);
    _activeHttpClient = null;
    setState(() {
      _isDownloading = false;
      _downloadProgress = 0.0;
    });
    _showSnack('Загрузка отменена');
  }

  Future<void> _triggerInstallApk(String path) async {
    try {
      final String? status = await _channel.invokeMethod<String>('installApk', {
        'apkPath': path,
      });
      if (!mounted) return;
      if (status == 'permission_requested') {
        _showSnack(
          'Разрешите установку для ScreenSaver — окно обновления откроется автоматически!',
        );
      }
    } catch (e) {
      _showSnack('Ошибка запуска установщика: $e');
    }
  }

  Future<void> _triggerBlackScreen({required bool isTest}) async {
    if (!_isAccessibilityEnabled) {
      _showSnack(
        'Сначала включите доступ в разделе «Специальные возможности»!',
      );
      return;
    }
    await _saveSettings();
    final String method = isTest ? 'startTestMode' : 'startBlackScreen';
    final bool? ok = await _channel.invokeMethod<bool>(method);
    if (ok != true && mounted) {
      _showSnack('Сервис еще не активен. Перезапустите переключатель в настройках.');
    }
  }

  Future<void> _requestAddTile() async {
    final String? res = await _channel.invokeMethod<String>('requestAddTile');
    if (!mounted) return;
    if (res == 'manual') {
      _showSnack(
        'Откройте шторку уведомлений -> Карандаш (Изменить) -> перетащите плитку «Экран ВЫКЛ».',
      );
    }
  }

  String _formatMb(int bytes) {
    return (bytes / (1024 * 1024)).toStringAsFixed(1);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('ScreenSaver'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.tealAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'v$_appVersion',
                style: const TextStyle(fontSize: 12, color: Colors.tealAccent),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить статус',
            onPressed: _refreshState,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_availableUpdate != null) ...[
            _buildUpdateBannerCard(),
            const SizedBox(height: 16),
          ],
          _buildPermissionsCard(),
          const SizedBox(height: 16),
          _buildActionsCard(),
          const SizedBox(height: 16),
          _buildWakeMethodsCard(),
          const SizedBox(height: 16),
          _buildExtraOptionsCard(),
          const SizedBox(height: 16),
          _buildVersionAndUpdateCard(),
        ],
      ),
    );
  }

  Widget _buildUpdateBannerCard() {
    final u = _availableUpdate!;
    return Card(
      color: const Color(0xFF142926),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.tealAccent, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.system_update, color: Colors.tealAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Доступно обновление v${u.version}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.tealAccent,
                    ),
                  ),
                ),
                if (u.fileSize > 0)
                  Text(
                    '${_formatMb(u.fileSize)} МБ',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
              ],
            ),
            if (u.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                u.releaseNotes,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
            const SizedBox(height: 12),
            if (_isDownloading) ...[
              LinearProgressIndicator(
                value: _totalBytes > 0 ? _downloadProgress : null,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Скачано: ${_formatMb(_downloadedBytes)} / ${_formatMb(_totalBytes)} МБ (${(_downloadProgress * 100).toStringAsFixed(0)}%)',
                    style: const TextStyle(fontSize: 12),
                  ),
                  TextButton(
                    onPressed: _cancelDownload,
                    child: const Text('Отмена'),
                  ),
                ],
              ),
            ] else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _downloadAndInstallUpdate,
                  icon: Icon(
                    _readyApkPath != null ? Icons.install_mobile : Icons.download,
                  ),
                  label: Text(
                    _readyApkPath != null
                        ? 'Установить обновление v${u.version}'
                        : 'Скачать и установить (без браузера)',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. Разрешения и защита от выгрузки',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _isAccessibilityEnabled ? Icons.check_circle : Icons.error,
                color: _isAccessibilityEnabled ? Colors.greenAccent : Colors.orangeAccent,
              ),
              title: const Text('Специальные возможности (Accessibility)'),
              subtitle: Text(
                _isAccessibilityEnabled
                    ? 'Активно — сервис готов к работе'
                    : 'Требуется для наложения черного экрана поверх системных панелей',
              ),
              trailing: FilledButton.tonal(
                onPressed: () =>
                    _channel.invokeMethod('openAccessibilitySettings'),
                child: Text(_isAccessibilityEnabled ? 'Настройки' : 'Включить'),
              ),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _isBatteryIgnored ? Icons.shield : Icons.battery_alert,
                color: _isBatteryIgnored ? Colors.greenAccent : Colors.amberAccent,
              ),
              title: const Text('Защита от закрытия системой (Anti-Kill)'),
              subtitle: Text(
                _isBatteryIgnored
                    ? 'Ограничения батареи сняты (Accessibility не слетит)'
                    : 'Рекомендуется отключить экономию энергии для стабильной работы',
              ),
              trailing: _isBatteryIgnored
                  ? const Text('ОК', style: TextStyle(color: Colors.greenAccent))
                  : FilledButton.tonal(
                      onPressed: () => _channel
                          .invokeMethod('requestIgnoreBatteryOptimizations'),
                      child: const Text('Разрешить'),
                    ),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.dashboard_customize, color: Colors.tealAccent),
              title: const Text('Быстрая кнопка в шторке Android'),
              subtitle: const Text('Позволяет гасить экран поверх любого приложения'),
              trailing: OutlinedButton(
                onPressed: _requestAddTile,
                child: const Text('Добавить'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '2. Управление и проверка',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _triggerBlackScreen(isTest: true),
                    icon: const Icon(Icons.timer_outlined),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('ТЕСТ (10 сек)'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _triggerBlackScreen(isTest: false),
                    icon: const Icon(Icons.power_settings_new),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Выключить сейчас'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWakeMethodsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '3. Способы включения экрана',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Можно выбрать сразу несколько способов одновременно:',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _wakeOnPowerInstant,
              onChanged: (v) {
                setState(() => _wakeOnPowerInstant = v);
                _saveSettings();
              },
              title: const Text('Кнопка питания: 1 нажатие (Мгновенное пробуждение)'),
              subtitle: Text(
                _wakeOnPowerInstant
                    ? '1 нажатие: экран моргает и сразу загорается уже без шторки'
                    : 'Стандартно: 1 нажатие гасит экран, 2-е нажатие включает экран',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _wakeOnMultiTouch,
              onChanged: (v) {
                setState(() => _wakeOnMultiTouch = v);
                _saveSettings();
              },
              title: Text('Одновременное касание ($_multiTouchFingers пальца/ев)'),
              subtitle: const Text('Быстрое пробуждение мультитачем'),
            ),
            if (_wakeOnMultiTouch)
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: Row(
                  children: [
                    const Text('Пальцев: 2'),
                    Expanded(
                      child: Slider(
                        value: _multiTouchFingers.toDouble(),
                        min: 2,
                        max: 5,
                        divisions: 3,
                        label: '$_multiTouchFingers',
                        onChanged: (v) {
                          setState(() => _multiTouchFingers = v.round());
                          _saveSettings();
                        },
                      ),
                    ),
                    const Text('5'),
                  ],
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _wakeOnDoubleTap,
              onChanged: (v) {
                setState(() => _wakeOnDoubleTap = v);
                _saveSettings();
              },
              title: const Text('Двойное касание (Double Tap)'),
              subtitle: const Text('Два быстрых нажатия одним пальцем'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _wakeOnTripleTap,
              onChanged: (v) {
                setState(() => _wakeOnTripleTap = v);
                _saveSettings();
              },
              title: const Text('Тройное касание (Triple Tap)'),
              subtitle: const Text('Три быстрых нажатия (меньше ложных срабатываний)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _wakeOnSwipe,
              onChanged: (v) {
                setState(() => _wakeOnSwipe = v);
                _saveSettings();
              },
              title: const Text('Длинный свайп по экрану'),
              subtitle: const Text('Проведите пальцем в любом направлении'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _wakeOnVolume,
              onChanged: (v) {
                setState(() => _wakeOnVolume = v);
                _saveSettings();
              },
              title: const Text('Физические кнопки громкости (Volume +/-)'),
              subtitle: const Text('Пробуждение по нажатию качельки громкости'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExtraOptionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '4. Дополнительные опции',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _wakeOnCall,
              onChanged: (v) {
                setState(() => _wakeOnCall = v);
                _saveSettings();
              },
              title: const Text('Пробуждать при входящем звонке'),
              subtitle: const Text('Автоматически снимать черный экран при вызове'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _showIndicator,
              onChanged: (v) {
                setState(() => _showIndicator = v);
                _saveSettings();
              },
              title: const Text('Индикатор программного отключения'),
              subtitle: const Text('Тусклая плашка, меняющая позицию раз в 20 сек (защита OLED)'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionAndUpdateCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '5. Версия и обновления (GitHub OTA)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline, color: Colors.tealAccent),
              title: Text('Текущая версия: v$_appVersion (сборка $_appBuildNumber)'),
              subtitle: const Text('Репозиторий: $kGithubOwner/$kGithubRepo'),
              trailing: _isCheckingUpdate
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => _checkForUpdates(silent: false),
                      icon: const Icon(Icons.cloud_sync_outlined, size: 18),
                      label: const Text('Проверить'),
                    ),
            ),
            if (_updateError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _updateError!,
                  style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}