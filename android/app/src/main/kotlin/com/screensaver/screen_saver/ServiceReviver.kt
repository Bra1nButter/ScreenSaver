package com.screensaver.screen_saver

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings

object ServiceReviver {

    fun isListedInSecureSettings(context: Context): Boolean {
        return try {
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            val expected = "${context.packageName}/${BlackScreenAccessibilityService::class.java.canonicalName}"
            enabledServices.contains(expected) || enabledServices.contains(context.packageName)
        } catch (_: Exception) {
            false
        }
    }

    fun canSelfHeal(context: Context): Boolean {
        return context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) ==
                PackageManager.PERMISSION_GRANTED
    }

    /**
     * Автоматически перезапускает («перещелкивает») AccessibilityService в системных настройках,
     * если Android / HyperOS выгрузил сервис из памяти, оставив тумблер включенным.
     */
    fun reviveAccessibilityService(context: Context, onRevived: (() -> Unit)? = null): Boolean {
        if (!canSelfHeal(context)) return false
        return try {
            val cr = context.contentResolver
            val component = "${context.packageName}/${BlackScreenAccessibilityService::class.java.canonicalName}"
            val current = Settings.Secure.getString(
                cr,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: ""

            val withoutUs = current.split(":")
                .filter { it.isNotBlank() && !it.contains(context.packageName) }
                .joinToString(":")

            // 1. Выключаем запись нашего сервиса
            Settings.Secure.putString(cr, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, withoutUs)

            // 2. Через 150 мс включаем обратно — Android мгновенно заново вызывает onServiceConnected()
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    val updated = if (withoutUs.isEmpty()) component else "$withoutUs:$component"
                    Settings.Secure.putString(cr, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, updated)
                    Settings.Secure.putInt(cr, Settings.Secure.ACCESSIBILITY_ENABLED, 1)

                    if (onRevived != null) {
                        Handler(Looper.getMainLooper()).postDelayed({
                            onRevived.invoke()
                        }, 300L)
                    }
                } catch (_: Exception) {}
            }, 150L)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    /**
     * Открывает фирменные настройки Автозапуска / Фонового контроля для Xiaomi (HyperOS/MIUI),
     * Samsung, Honor/Huawei, Oppo/Realme, либо стандартное окно «О приложении».
     */
    fun openOemAutostartSettings(context: Context) {
        val intents = listOf(
            Intent().setComponent(
                ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
                )
            ),
            Intent("miui.intent.action.OP_AUTO_START").addCategory(Intent.CATEGORY_DEFAULT),
            Intent().setComponent(
                ComponentName(
                    "com.miui.powerkeeper",
                    "com.miui.powerkeeper.ui.HiddenAppsConfigActivity"
                )
            ).putExtra("package_name", context.packageName)
                .putExtra("package_label", "ScreenSaver"),
            Intent().setComponent(
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                )
            ),
            Intent().setComponent(
                ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                )
            ),
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${context.packageName}")
            )
        )

        for (intent in intents) {
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (intent.resolveActivity(context.packageManager) != null) {
                    context.startActivity(intent)
                    return
                }
            } catch (_: Exception) {}
        }
    }
}