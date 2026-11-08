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
        scaffoldBackgroundColor: const Color(0xFF0B0E14),
        cardTheme: CardThemeData(
          color: const Color(0xFF151922),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFF222836), width: 1),
          ),
        ),
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
  int _sdkInt = 33;
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
        _sdkInt = ((data['sdkInt'] as num?) ?? 33).toInt();
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

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$kGithubOwner/$kGithubRepo/releases/latest',
      );
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers
          .set(HttpHeaders.userAgentHeader, 'ScreenSaver-Android-Updater');

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
          _showSnack(
            'Релиз $tagName найден, но APK еще собирается в GitHub Actions.',
          );
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
      req.headers
          .set(HttpHeaders.userAgentHeader, 'ScreenSaver-Android-Updater');
      final resp = await req.close();

      if (resp.statusCode != 200) {
        throw HttpException('Сервер вернул код ${resp.statusCode}');
      }

      final contentLen =
          resp.contentLength > 0 ? resp.contentLength : update.fileSize;
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
        throw const FileSystemException(
          'Скачанный файл поврежден или слишком мал',
        );
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
        'Сначала включите доступ в разделе «1. Разрешения»!',
      );
      return;
    }
    await _saveSettings();
    final String method = isTest ? 'startTestMode' : 'startBlackScreen';
    final bool? ok = await _channel.invokeMethod<bool>(method);
    if (ok != true && mounted) {
      _showSnack(
        'Сервис еще не активен. Перезапустите переключатель в настройках.',
      );
    }
  }

  Future<void> _requestAddTile() async {
    final String? res = await _channel.invokeMethod<String>('requestAddTile');
    if (!mounted) return;
    if (res == 'manual') {
      _showSnack(
        'Опустите шторку уведомлений -> Карандаш (Изменить) -> перетащите плитку «Экран ВЫКЛ».',
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
        backgroundColor: const Color(0xFF0B0E14),
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            const Icon(Icons.dark_mode_outlined, color: Colors.tealAccent, size: 22),
            const SizedBox(width: 8),
            const Text(
              'ScreenSaver',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.tealAccent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'v$_appVersion',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.tealAccent,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить статус',
            onPressed: _refreshState,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            if (_availableUpdate != null) ...[
              _buildUpdateBannerCard(),
              const SizedBox(height: 14),
            ],
            _buildActionsCard(),
            const SizedBox(height: 14),
            _buildPermissionsCard(),
            const SizedBox(height: 14),
            _buildWakeMethodsCard(),
            const SizedBox(height: 14),
            _buildExtraOptionsCard(),
            const SizedBox(height: 14),
            _buildVersionAndUpdateCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Colors.tealAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 13, color: Colors.white60),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusBadge({required bool active, required String text}) {
    final color = active ? Colors.greenAccent : Colors.orangeAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateBannerCard() {
    final u = _availableUpdate!;
    return Card(
      color: const Color(0xFF112624),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Colors.tealAccent, width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.system_update_rounded, color: Colors.tealAccent),
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
            const SizedBox(height: 14),
            if (_isDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: _totalBytes > 0 ? _downloadProgress : null,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_formatMb(_downloadedBytes)} / ${_formatMb(_totalBytes)} МБ (${(_downloadProgress * 100).toStringAsFixed(0)}%)',
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
                height: 48,
                child: FilledButton.icon(
                  onPressed: _downloadAndInstallUpdate,
                  icon: Icon(
                    _readyApkPath != null
                        ? Icons.install_mobile_rounded
                        : Icons.download_rounded,
                  ),
                  label: Text(
                    _readyApkPath != null
                        ? 'Установить обновление v${u.version}'
                        : 'Скачать и установить обновление',
                  ),
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
            _buildSectionHeader(
              Icons.bolt_rounded,
              'Быстрый запуск',
              subtitle: _isAccessibilityEnabled
                  ? 'Сервис готов. Можно гасить экран сейчас или через плитку в шторке.'
                  : 'Для запуска сначала включите доступ в блоке «1. Разрешения» ниже.',
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: () => _triggerBlackScreen(isTest: false),
                icon: const Icon(Icons.power_settings_new_rounded),
                label: const Text(
                  'Выключить экран сейчас',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: FilledButton.tonalIcon(
                onPressed: () => _triggerBlackScreen(isTest: true),
                icon: const Icon(Icons.timer_outlined),
                label: const Text(
                  'Безопасный ТЕСТ (автовозврат через 10 сек)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsCard() {
    final bool isAndroid13Plus = _sdkInt >= 33;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(
              Icons.verified_user_outlined,
              '1. Разрешения и быстрая кнопка',
            ),
            const SizedBox(height: 14),

            // Блок 1.1: Специальные возможности (Accessibility)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF10131A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isAccessibilityEnabled
                      ? Colors.greenAccent.withValues(alpha: 0.25)
                      : Colors.orangeAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Специальные возможности',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _buildStatusBadge(
                        active: _isAccessibilityEnabled,
                        text: _isAccessibilityEnabled ? 'Активно' : 'Требуется',
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isAccessibilityEnabled
                        ? 'Служба ScreenSaver активна и может перекрывать системные панели.'
                        : 'Необходимо для наложения черного экрана поверх всех окон и шторки.',
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),

                  // Специальная подсказка для Android 13+ при установке из APK
                  if (!_isAccessibilityEnabled && isAndroid13Plus) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.amberAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.lock_open_rounded,
                                size: 17,
                                color: Colors.amberAccent,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Если Android пишет «Доступ запрещен»:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 6),
                          Text(
                            'На Android 13+ для приложений, установленных из APK, нужно один раз снять защиту:\n'
                            '1. Нажмите кнопку «Шаг 1: О приложении» ниже.\n'
                            '2. Нажмите ⋮ (три точки в углу) или прокрутите в самый низ (на Xiaomi/HyperOS) и выберите «Разрешить ограниченные настройки».\n'
                            '3. Затем нажмите «Шаг 2» и включите службу.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _channel.invokeMethod('openAppDetailsSettings'),
                        icon: const Icon(Icons.settings_applications_outlined, size: 19),
                        label: const Text('Шаг 1: Открыть «О приложении»'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 44,
                      child: FilledButton.icon(
                        onPressed: () =>
                            _channel.invokeMethod('openAccessibilitySettings'),
                        icon: const Icon(Icons.accessibility_new_rounded, size: 19),
                        label: const Text('Шаг 2: Включить в «Спец. возможностях»'),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 42,
                      child: _isAccessibilityEnabled
                          ? OutlinedButton.icon(
                              onPressed: () => _channel
                                  .invokeMethod('openAccessibilitySettings'),
                              icon: const Icon(Icons.tune_rounded, size: 18),
                              label: const Text('Открыть настройки службы'),
                            )
                          : FilledButton.icon(
                              onPressed: () => _channel
                                  .invokeMethod('openAccessibilitySettings'),
                              icon: const Icon(
                                Icons.accessibility_new_rounded,
                                size: 18,
                              ),
                              label: const Text('Включить доступ'),
                            ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Блок 1.2: Защита от закрытия системой (Anti-Kill)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF10131A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF222836)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Защита от выгрузки (Anti-Kill)',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _buildStatusBadge(
                        active: _isBatteryIgnored,
                        text: _isBatteryIgnored ? 'Защищено' : 'Рекомендуется',
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isBatteryIgnored
                        ? 'Ограничения батареи сняты — система не отключит службу в фоне.'
                        : 'Отключите экономию заряда для ScreenSaver, чтобы доступ не слетал.',
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  if (!_isBatteryIgnored) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 42,
                      child: FilledButton.tonalIcon(
                        onPressed: () => _channel
                            .invokeMethod('requestIgnoreBatteryOptimizations'),
                        icon: const Icon(Icons.shield_outlined, size: 18),
                        label: const Text('Отключить оптимизацию батареи'),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Блок 1.3: Плитка в шторке быстрых настроек
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF10131A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF222836)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Плитка «Экран ВЫКЛ» в шторке Android',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Позволяет гасить экран в один тап поверх любой запущенной игры или видео.',
                    style: TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: _requestAddTile,
                      icon: const Icon(Icons.add_to_home_screen_rounded, size: 18),
                      label: const Text('Добавить кнопку в шторку'),
                    ),
                  ),
                ],
              ),
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
            _buildSectionHeader(
              Icons.touch_app_outlined,
              '2. Способы включения экрана',
              subtitle: 'Можно включить сразу несколько удобных вариантов:',
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.power_settings_new_rounded, color: Colors.tealAccent),
              value: _wakeOnPowerInstant,
              onChanged: (v) {
                setState(() => _wakeOnPowerInstant = v);
                _saveSettings();
              },
              title: const Text(
                'Кнопка питания (1 нажатие)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _wakeOnPowerInstant
                    ? 'Экран сразу загорается после 1 нажатия кнопки питания'
                    : 'Стандартно: 1-е нажатие блокирует, 2-е включает экран',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const Divider(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.pan_tool_alt_outlined, color: Colors.tealAccent),
              value: _wakeOnMultiTouch,
              onChanged: (v) {
                setState(() => _wakeOnMultiTouch = v);
                _saveSettings();
              },
              title: Text(
                'Касание несколькими пальцами ($_multiTouchFingers)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Одновременное нажатие на экран заданным числом пальцев',
                style: TextStyle(fontSize: 12),
              ),
            ),
            if (_wakeOnMultiTouch) ...[
              const SizedBox(height: 6),
              Row(
                children: [2, 3, 4, 5].map((count) {
                  final bool selected = _multiTouchFingers == count;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        showCheckmark: false,
                        selected: selected,
                        label: Center(
                          child: Text(
                            '$count пальца',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        onSelected: (_) {
                          setState(() => _multiTouchFingers = count);
                          _saveSettings();
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 4),
            ],
            const Divider(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.ads_click_rounded, color: Colors.tealAccent),
              value: _wakeOnDoubleTap,
              onChanged: (v) {
                setState(() => _wakeOnDoubleTap = v);
                _saveSettings();
              },
              title: const Text(
                'Двойной тап (Double Tap)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Два быстрых касания одним пальцем',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const Divider(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.touch_app_rounded, color: Colors.tealAccent),
              value: _wakeOnTripleTap,
              onChanged: (v) {
                setState(() => _wakeOnTripleTap = v);
                _saveSettings();
              },
              title: const Text(
                'Тройной тап (Triple Tap)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Три быстрых касания (защита от случайных нажатий)',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const Divider(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.swipe_rounded, color: Colors.tealAccent),
              value: _wakeOnSwipe,
              onChanged: (v) {
                setState(() => _wakeOnSwipe = v);
                _saveSettings();
              },
              title: const Text(
                'Длинный свайп по экрану',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Проведите пальцем по экрану в любую сторону',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const Divider(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.volume_up_rounded, color: Colors.tealAccent),
              value: _wakeOnVolume,
              onChanged: (v) {
                setState(() => _wakeOnVolume = v);
                _saveSettings();
              },
              title: const Text(
                'Кнопки громкости (Volume +/-)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Пробуждение нажатием физической качельки громкости',
                style: TextStyle(fontSize: 12),
              ),
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
            _buildSectionHeader(
              Icons.tune_rounded,
              '3. Дополнительные опции',
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.phone_in_talk_rounded, color: Colors.tealAccent),
              value: _wakeOnCall,
              onChanged: (v) {
                setState(() => _wakeOnCall = v);
                _saveSettings();
              },
              title: const Text(
                'Пробуждать при входящем звонке',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Автоматически снимать черный экран при вызове',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const Divider(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.lens_blur_rounded, color: Colors.tealAccent),
              value: _showIndicator,
              onChanged: (v) {
                setState(() => _showIndicator = v);
                _saveSettings();
              },
              title: const Text(
                'Индикатор программного отключения',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Тусклая плашка, меняющая позицию раз в 20 сек (защита OLED)',
                style: TextStyle(fontSize: 12),
              ),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(
              Icons.cloud_sync_outlined,
              '4. О программе и обновления (OTA)',
            ),
            const SizedBox(height: 10),
            Text(
              'Установлена версия: v$_appVersion (сборка $_appBuildNumber)\n'
              'Источник обновлений: github.com/$kGithubOwner/$kGithubRepo',
              style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
            ),
            if (_updateError != null) ...[
              const SizedBox(height: 8),
              Text(
                _updateError!,
                style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _isCheckingUpdate
                    ? null
                    : () => _checkForUpdates(silent: false),
                icon: _isCheckingUpdate
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt_rounded, size: 18),
                label: Text(
                  _isCheckingUpdate
                      ? 'Проверка обновлений...'
                      : 'Проверить наличие обновлений',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}