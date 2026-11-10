package com.screensaver.screen_saver

import android.accessibilityservice.AccessibilityService
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.FrameLayout
import android.widget.TextView
import kotlin.math.hypot
import kotlin.random.Random

class BlackScreenAccessibilityService : AccessibilityService() {

    companion object {
        private const val CHANNEL_ID = "screensaver_keepalive_channel"
        private const val NOTIFICATION_ID = 1001

        @Volatile
        var instance: BlackScreenAccessibilityService? = null
            private set

        val isRunning: Boolean
            get() = instance != null
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var settings: SettingsManager
    private var windowManager: WindowManager? = null
    private var overlayView: FrameLayout? = null
    private var indicatorView: TextView? = null
    private var overlayParams: WindowManager.LayoutParams? = null

    var isOverlayShowing: Boolean = false
        private set

    private var isTestMode: Boolean = false
    private var testRemainingSec: Int = 0

    private var lastTapTime: Long = 0L
    private var tapCount: Int = 0
    private var downX: Float = 0f
    private var downY: Float = 0f
    private var maxPointersInGesture: Int = 0

    private val screenOffReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF && isOverlayShowing) {
                val instantWake = settings.wakeOnPowerInstant
                hideOverlay()
                if (instantWake) {
                    wakeUpScreenImmediately()
                }
            }
        }
    }

    private var tickCounter = 0
    private val periodicTask = object : Runnable {
        override fun run() {
            if (!isOverlayShowing) return

            if (settings.wakeOnCall && isIncomingCallActive()) {
                hideOverlay()
                return
            }

            if (isTestMode) {
                testRemainingSec--
                if (testRemainingSec <= 0) {
                    hideOverlay()
                    return
                }
                updateIndicatorText()
            }

            tickCounter++
            if (tickCounter % 20 == 0) {
                moveIndicatorRandomly()
            }

            mainHandler.postDelayed(this, 1000L)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        updateForegroundKeepAlive()
        return START_STICKY
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        settings = SettingsManager(this)
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        updateForegroundKeepAlive()

        try {
            val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(screenOffReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(screenOffReceiver, filter)
            }
        } catch (_: Exception) {}
    }

    fun updateForegroundKeepAlive() {
        if (!::settings.isInitialized) {
            settings = SettingsManager(this)
        }
        if (settings.keepAliveForeground) {
            startKeepAliveForeground()
        } else {
            stopKeepAliveForeground()
        }
    }

    private fun startKeepAliveForeground() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Удержание службы в памяти",
                    NotificationManager.IMPORTANCE_MIN
                ).apply {
                    description = "Защищает службу ScreenSaver от фонового закрытия системой"
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_SECRET
                }
                nm.createNotificationChannel(channel)
            }

            val openIntent = Intent(this, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

            val notification = builder
                .setContentTitle("ScreenSaver активен")
                .setContentText("Готов к отключению экрана из шторки")
                .setSmallIcon(android.R.drawable.ic_lock_power_off)
                .setContentIntent(pendingIntent)
                .setOngoing(true)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: Exception) {}
    }

    private fun stopKeepAliveForeground() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {}
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // При смахивании приложения из списка недавних удерживаем сервис активным
        updateForegroundKeepAlive()
        super.onTaskRemoved(rootIntent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {
        hideOverlay()
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (isOverlayShowing && settings.wakeOnVolume) {
            if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
            ) {
                if (event.action == KeyEvent.ACTION_DOWN) {
                    hideOverlay()
                }
                return true
            }
        }
        return super.onKeyEvent(event)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (isOverlayShowing && overlayView != null && overlayParams != null) {
            mainHandler.post {
                try {
                    applyImmersiveFlags(overlayView!!)
                    windowManager?.updateViewLayout(overlayView, overlayParams)
                    moveIndicatorRandomly()
                } catch (_: Exception) {}
            }
        }
    }

    fun collapseShadeAndShowOverlay() {
        mainHandler.post {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                performGlobalAction(GLOBAL_ACTION_DISMISS_NOTIFICATION_SHADE)
            } else {
                @Suppress("DEPRECATION")
                sendBroadcast(Intent(Intent.ACTION_CLOSE_SYSTEM_DIALOGS))
            }
            mainHandler.postDelayed({
                showOverlay(isTest = false)
            }, 250L)
        }
    }

    fun showOverlay(isTest: Boolean = false, durationSec: Int = 10) {
        mainHandler.post {
            if (isOverlayShowing) {
                hideOverlay()
            }

            isTestMode = isTest
            testRemainingSec = durationSec
            tickCounter = 0

            val container = FrameLayout(this).apply {
                setBackgroundColor(Color.BLACK)
                isClickable = true
                isFocusable = false
                setOnTouchListener { _, event -> handleTouchEvent(event) }
            }

            if (settings.showIndicator || isTestMode) {
                val badge = createIndicatorTextView()
                indicatorView = badge
                val badgeParams = FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    gravity = Gravity.CENTER
                }
                container.addView(badge, badgeParams)
                updateIndicatorText()
            }

            val params = createOverlayLayoutParams()
            overlayParams = params
            overlayView = container

            try {
                windowManager?.addView(container, params)
                applyImmersiveFlags(container)
                isOverlayShowing = true
                mainHandler.postDelayed(periodicTask, 1000L)
            } catch (e: Exception) {
                e.printStackTrace()
                overlayView = null
                indicatorView = null
                isOverlayShowing = false
            }
        }
    }

    fun hideOverlay() {
        mainHandler.post {
            mainHandler.removeCallbacks(periodicTask)
            val view = overlayView
            if (view != null) {
                try {
                    windowManager?.removeViewImmediate(view)
                } catch (_: Exception) {}
            }
            overlayView = null
            indicatorView = null
            overlayParams = null
            isOverlayShowing = false
            isTestMode = false
        }
    }

    private fun wakeUpScreenImmediately() {
        mainHandler.postDelayed({
            try {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                @Suppress("DEPRECATION")
                val wakeLock = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                            PowerManager.ACQUIRE_CAUSES_WAKEUP or
                            PowerManager.ON_AFTER_RELEASE,
                    "screensaver:instant_wake"
                )
                wakeLock.acquire(1500L)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }, 120L)
    }

    private fun createOverlayLayoutParams(): WindowManager.LayoutParams {
        @Suppress("DEPRECATION")
        val flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_FULLSCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR

        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            flags,
            PixelFormat.OPAQUE
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            screenBrightness = 0.0f

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }

    private fun applyImmersiveFlags(view: View) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            view.windowInsetsController?.let { controller ->
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            view.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                )
        }
    }

    private fun createIndicatorTextView(): TextView {
        val bg = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dpToPx(20f)
            setColor(Color.parseColor("#14FFFFFF"))
            setStroke(1, Color.parseColor("#28FFFFFF"))
        }
        return TextView(this).apply {
            background = bg
            setTextColor(Color.parseColor("#55FFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            gravity = Gravity.CENTER
            val padH = dpToPx(14f).toInt()
            val padV = dpToPx(8f).toInt()
            setPadding(padH, padV, padH, padV)
        }
    }

    private fun updateIndicatorText() {
        val badge = indicatorView ?: return
        if (isTestMode) {
            badge.text = "● ТЕСТ: возврат через $testRemainingSec сек"
        } else {
            badge.text = "● Экран программно отключен"
        }
    }

    private fun moveIndicatorRandomly() {
        val badge = indicatorView ?: return
        val parent = overlayView ?: return
        if (parent.width <= 0 || parent.height <= 0) return

        val maxOffsetX = (parent.width / 3).coerceAtLeast(20)
        val maxOffsetY = (parent.height / 3).coerceAtLeast(20)

        badge.translationX = Random.nextInt(-maxOffsetX, maxOffsetX).toFloat()
        badge.translationY = Random.nextInt(-maxOffsetY, maxOffsetY).toFloat()
    }

    private fun handleTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.rawX
                downY = event.rawY
                maxPointersInGesture = 1
            }

            MotionEvent.ACTION_POINTER_DOWN -> {
                val count = event.pointerCount
                if (count > maxPointersInGesture) {
                    maxPointersInGesture = count
                }
                if (settings.wakeOnMultiTouch && count >= settings.multiTouchFingers) {
                    hideOverlay()
                    return true
                }
            }

            MotionEvent.ACTION_MOVE -> {
                val count = event.pointerCount
                if (count > maxPointersInGesture) {
                    maxPointersInGesture = count
                }
                if (settings.wakeOnMultiTouch && count >= settings.multiTouchFingers) {
                    hideOverlay()
                    return true
                }
            }

            MotionEvent.ACTION_UP -> {
                if (maxPointersInGesture == 1) {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    val distance = hypot(dx, dy)

                    if (settings.wakeOnSwipe && distance >= dpToPx(110f)) {
                        hideOverlay()
                        return true
                    }

                    if (distance < dpToPx(24f)) {
                        val now = SystemClock.uptimeMillis()
                        if (now - lastTapTime <= 380L) {
                            tapCount++
                        } else {
                            tapCount = 1
                        }
                        lastTapTime = now

                        if (settings.wakeOnDoubleTap && tapCount >= 2) {
                            tapCount = 0
                            hideOverlay()
                            return true
                        }
                        if (settings.wakeOnTripleTap && tapCount >= 3) {
                            tapCount = 0
                            hideOverlay()
                            return true
                        }
                    }
                }
            }
        }
        return true
    }

    private fun isIncomingCallActive(): Boolean {
        return try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioManager.mode == AudioManager.MODE_RINGTONE
        } catch (_: Exception) {
            false
        }
    }

    private fun dpToPx(dp: Float): Float {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            resources.displayMetrics
        )
    }

    override fun onUnbind(intent: Intent?): Boolean {
        hideOverlay()
        stopKeepAliveForeground()
        instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        hideOverlay()
        stopKeepAliveForeground()
        try {
            unregisterReceiver(screenOffReceiver)
        } catch (_: Exception) {}
        instance = null
        super.onDestroy()
    }
}