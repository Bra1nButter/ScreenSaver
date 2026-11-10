package com.screensaver.screen_saver

import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.screensaver/native"
    private lateinit var settingsManager: SettingsManager
    private var pendingInstallApkPath: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        settingsManager = SettingsManager(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getState" -> {
                        val isRunningInRam = BlackScreenAccessibilityService.isRunning
                        val isListedInSettings = ServiceReviver.isListedInSecureSettings(this)
                        val isZombie = isListedInSettings && !isRunningInRam
                        val canSelfHeal = ServiceReviver.canSelfHeal(this)

                        // Если обнаружен Зомби-режим и есть право самореанимации — лечим сразу при входе!
                        if (isZombie && canSelfHeal) {
                            ServiceReviver.reviveAccessibilityService(this)
                        }

                        val pkgInfo = getPackageInfoCompat()
                        val versionName = pkgInfo.versionName ?: "1.0.0"
                        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            pkgInfo.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            pkgInfo.versionCode.toLong()
                        }
                        val updatesDir = File(cacheDir, "updates").apply { mkdirs() }

                        val map = HashMap<String, Any>()
                        // Теперь true возвращается ТОЛЬКО когда сервис реально жив в ОЗУ!
                        map["isAccessibilityEnabled"] = isRunningInRam
                        map["isZombieState"] = isZombie
                        map["canSelfHeal"] = canSelfHeal
                        map["isBatteryIgnored"] = isBatteryOptimizationIgnored()
                        map["canInstallPackages"] = packageManager.canRequestPackageInstalls()
                        map["sdkInt"] = Build.VERSION.SDK_INT
                        map["versionName"] = versionName
                        map["versionCode"] = versionCode
                        map["updatesDir"] = updatesDir.absolutePath
                        map["settings"] = settingsManager.toMap()
                        result.success(map)
                    }

                    "saveSettings" -> {
                        val args = call.arguments as? Map<*, *>
                        if (args != null) {
                            settingsManager.updateFromMap(args)
                            BlackScreenAccessibilityService.instance?.updateForegroundKeepAlive()
                        }
                        result.success(true)
                    }

                    "reviveService" -> {
                        val ok = ServiceReviver.reviveAccessibilityService(this)
                        result.success(ok)
                    }

                    "openAutostartSettings" -> {
                        ServiceReviver.openOemAutostartSettings(this)
                        result.success(true)
                    }

                    "openAppDetailsSettings" -> {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName")
                        ).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
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
                        } else if (ServiceReviver.reviveAccessibilityService(this) {
                                BlackScreenAccessibilityService.instance?.showOverlay(isTest = false)
                            }
                        ) {
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
                        } else if (ServiceReviver.reviveAccessibilityService(this) {
                                BlackScreenAccessibilityService.instance?.showOverlay(isTest = true, durationSec = 10)
                            }
                        ) {
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

                    "installApk" -> {
                        val apkPath = call.argument<String>("apkPath")
                        if (apkPath.isNullOrEmpty()) {
                            result.error("INVALID_PATH", "APK path is empty", null)
                            return@setMethodCallHandler
                        }
                        val apkFile = File(apkPath)
                        if (!apkFile.exists()) {
                            result.error("NOT_FOUND", "APK file not found", null)
                            return@setMethodCallHandler
                        }

                        if (!packageManager.canRequestPackageInstalls()) {
                            pendingInstallApkPath = apkPath
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                            result.success("permission_requested")
                        } else {
                            pendingInstallApkPath = null
                            launchApkInstaller(apkFile)
                            result.success("installer_launched")
                        }
                    }

                    "cleanupOldApks" -> {
                        val keepFileName = call.argument<String>("keepFileName")
                        val updatesDir = File(cacheDir, "updates")
                        if (updatesDir.exists()) {
                            updatesDir.listFiles()?.forEach { f ->
                                if (keepFileName == null || f.name != keepFileName) {
                                    try {
                                        f.delete()
                                    } catch (_: Exception) {}
                                }
                            }
                        }
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onResume() {
        super.onResume()
        val pendingPath = pendingInstallApkPath
        if (pendingPath != null && packageManager.canRequestPackageInstalls()) {
            pendingInstallApkPath = null
            val file = File(pendingPath)
            if (file.exists()) {
                launchApkInstaller(file)
            }
        }
    }

    private fun launchApkInstaller(apkFile: File) {
        val contentUri = ApkFileProvider.getUriForFile(packageName, apkFile)
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(contentUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(installIntent)
    }

    private fun getPackageInfoCompat() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
        }

    private fun isBatteryOptimizationIgnored(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }
}