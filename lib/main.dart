import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ScreenSaverApp());
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

  bool _wakeOnDoubleTap = true;
  bool _wakeOnTripleTap = false;
  bool _wakeOnMultiTouch = true;
  int _multiTouchFingers = 3;
  bool _wakeOnSwipe = false;
  bool _wakeOnVolume = false;
  bool _wakeOnCall = true;
  bool _showIndicator = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshState();
  }

  @override
  void dispose() {
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

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ScreenSaver'),
        centerTitle: false,
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
          _buildPermissionsCard(),
          const SizedBox(height: 16),
          _buildActionsCard(),
          const SizedBox(height: 16),
          _buildWakeMethodsCard(),
          const SizedBox(height: 16),
          _buildExtraOptionsCard(),
        ],
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
            const SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: true,
              onChanged: null,
              title: Text('Кнопка питания (Power)'),
              subtitle: Text('Всегда активна для гарантированного возврата'),
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
              subtitle: const Text(
                'Автоматически снимать черный экран при вызове',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _showIndicator,
              onChanged: (v) {
                setState(() => _showIndicator = v);
                _saveSettings();
              },
              title: const Text('Индикатор программного отключения'),
              subtitle: const Text(
                'Тусклая плашка, меняющая позицию раз в 20 сек (защита OLED)',
              ),
            ),
          ],
        ),
      ),
    );
  }
}