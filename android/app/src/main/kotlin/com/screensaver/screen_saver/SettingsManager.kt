package com.screensaver.screen_saver

import android.content.Context
import android.content.SharedPreferences
import android.os.Build

class SettingsManager(context: Context) {
    private val prefs: SharedPreferences = createSafePreferences(context)

    private fun createSafePreferences(context: Context): SharedPreferences {
        val appCtx = context.applicationContext ?: context
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val deviceCtx = appCtx.createDeviceProtectedStorageContext()
            // Переносим старые настройки при первом обновлении, если телефон разблокирован
            try {
                deviceCtx.moveSharedPreferencesFrom(appCtx, "screen_saver_prefs")
            } catch (_: Exception) {}
            deviceCtx.getSharedPreferences("screen_saver_prefs", Context.MODE_PRIVATE)
        } else {
            appCtx.getSharedPreferences("screen_saver_prefs", Context.MODE_PRIVATE)
        }
    }

    var keepAliveForeground: Boolean
        get() = prefs.getBoolean("keepAliveForeground", true)
        set(value) = prefs.edit().putBoolean("keepAliveForeground", value).apply()

    var wakeOnPowerInstant: Boolean
        get() = prefs.getBoolean("wakeOnPowerInstant", true)
        set(value) = prefs.edit().putBoolean("wakeOnPowerInstant", value).apply()

    var wakeOnDoubleTap: Boolean
        get() = prefs.getBoolean("wakeOnDoubleTap", true)
        set(value) = prefs.edit().putBoolean("wakeOnDoubleTap", value).apply()

    var wakeOnTripleTap: Boolean
        get() = prefs.getBoolean("wakeOnTripleTap", false)
        set(value) = prefs.edit().putBoolean("wakeOnTripleTap", value).apply()

    var wakeOnMultiTouch: Boolean
        get() = prefs.getBoolean("wakeOnMultiTouch", true)
        set(value) = prefs.edit().putBoolean("wakeOnMultiTouch", value).apply()

    var multiTouchFingers: Int
        get() = prefs.getInt("multiTouchFingers", 3)
        set(value) = prefs.edit().putInt("multiTouchFingers", value.coerceIn(2, 5)).apply()

    var wakeOnSwipe: Boolean
        get() = prefs.getBoolean("wakeOnSwipe", false)
        set(value) = prefs.edit().putBoolean("wakeOnSwipe", value).apply()

    var wakeOnVolume: Boolean
        get() = prefs.getBoolean("wakeOnVolume", false)
        set(value) = prefs.edit().putBoolean("wakeOnVolume", value).apply()

    var wakeOnCall: Boolean
        get() = prefs.getBoolean("wakeOnCall", true)
        set(value) = prefs.edit().putBoolean("wakeOnCall", value).apply()

    var showIndicator: Boolean
        get() = prefs.getBoolean("showIndicator", true)
        set(value) = prefs.edit().putBoolean("showIndicator", value).apply()

    fun toMap(): Map<String, Any> {
        return mapOf(
            "keepAliveForeground" to keepAliveForeground,
            "wakeOnPowerInstant" to wakeOnPowerInstant,
            "wakeOnDoubleTap" to wakeOnDoubleTap,
            "wakeOnTripleTap" to wakeOnTripleTap,
            "wakeOnMultiTouch" to wakeOnMultiTouch,
            "multiTouchFingers" to multiTouchFingers,
            "wakeOnSwipe" to wakeOnSwipe,
            "wakeOnVolume" to wakeOnVolume,
            "wakeOnCall" to wakeOnCall,
            "showIndicator" to showIndicator
        )
    }

    fun updateFromMap(map: Map<*, *>) {
        (map["keepAliveForeground"] as? Boolean)?.let { keepAliveForeground = it }
        (map["wakeOnPowerInstant"] as? Boolean)?.let { wakeOnPowerInstant = it }
        (map["wakeOnDoubleTap"] as? Boolean)?.let { wakeOnDoubleTap = it }
        (map["wakeOnTripleTap"] as? Boolean)?.let { wakeOnTripleTap = it }
        (map["wakeOnMultiTouch"] as? Boolean)?.let { wakeOnMultiTouch = it }
        (map["multiTouchFingers"] as? Number)?.let { multiTouchFingers = it.toInt() }
        (map["wakeOnSwipe"] as? Boolean)?.let { wakeOnSwipe = it }
        (map["wakeOnVolume"] as? Boolean)?.let { wakeOnVolume = it }
        (map["wakeOnCall"] as? Boolean)?.let { wakeOnCall = it }
        (map["showIndicator"] as? Boolean)?.let { showIndicator = it }
    }
}