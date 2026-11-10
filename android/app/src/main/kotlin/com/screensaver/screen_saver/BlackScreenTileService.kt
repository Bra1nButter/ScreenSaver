package com.screensaver.screen_saver

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.Toast

class BlackScreenTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        qsTile?.let { tile ->
            // Плитка всегда активна для нажатия, чтобы при зомби-состоянии она могла реанимировать сервис
            tile.state = Tile.STATE_INACTIVE
            tile.updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val service = BlackScreenAccessibilityService.instance
        if (service != null) {
            service.collapseShadeAndShowOverlay()
            return
        }

        // Если сервис был убит системой (Зомби-режим), пробуем реанимировать его автоматически:
        val revived = ServiceReviver.reviveAccessibilityService(this) {
            BlackScreenAccessibilityService.instance?.collapseShadeAndShowOverlay()
        }
        if (revived) {
            return
        }

        // Если нет права WRITE_SECURE_SETTINGS, открываем приложение с подсказкой
        Toast.makeText(
            this,
            "Служба ScreenSaver была остановлена системой. Перезапустите переключатель.",
            Toast.LENGTH_LONG
        ).show()

        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}