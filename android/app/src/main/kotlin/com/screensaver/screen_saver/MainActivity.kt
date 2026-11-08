package com.screensaver.screen_saver

import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.screensaver/native"
    private lateinit var settingsManager: SettingsManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        settingsManager = SettingsManager(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getState" -> {
                        val map = HashMap<String, Any>()
                        map["isAccessibilityEnabled"] = isAccessibilityServiceEnabled()
                        map["isBatteryIgnored"] = isBatteryOptimizationIgnored()
                        map["settings"] = settingsManager.toMap()
                        result.success(map)
                    }

                    "saveSettings" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args != null) {
                            settingsManager.updateFromMap(args)
                        }
                        result.success(true)
                    }

                    "openAccessibilitySettings" -> {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    }

                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                        } catch (_: Exception) {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        }
                        result.success(true)
                    }

                    "startBlackScreen" -> {
                        val service = BlackScreenAccessibilityService.instance
                        if (service != null) {
                            service.showOverlay(isTest = false)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }

                    "startTestMode" -> {
                        val service = BlackScreenAccessibilityService.instance
                        if (service != null) {
                            service.showOverlay(isTest = true, durationSec = 10)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }

                    "requestAddTile" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val statusBarManager =
                                getSystemService(StatusBarManager::class.java)
                            val componentName = ComponentName(
                                this,
                                BlackScreenTileService::class.java
                            )
                            statusBarManager.requestAddTileService(
                                componentName,
                                getString(R.string.tile_label),
                                Icon.createWithResource(
                                    this,
                                    android.R.drawable.ic_lock_power_off
                                ),
                                mainExecutor
                            ) { }
                            result.success("prompted")
                        } else {
                            result.success("manual")
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        if (BlackScreenAccessibilityService.isRunning) return true
        val expected = "$packageName/${BlackScreenAccessibilityService::class.java.canonicalName}"
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabledServices.contains(expected) || enabledServices.contains(packageName)
    }

    private fun isBatteryOptimizationIgnored(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }
}