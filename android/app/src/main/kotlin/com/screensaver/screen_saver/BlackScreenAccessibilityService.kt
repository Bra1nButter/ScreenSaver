package com.screensaver.screen_saver

import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
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

    // Переменные для распознавания жестов
    private var lastTapTime: Long = 0L
    private var tapCount: Int = 0
    private var downX: Float = 0f
    private var downY: Float = 0f
    private var maxPointersInGesture: Int = 0

    // Ресивер физического отключения экрана (кнопка питания)
    private val screenOffReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF && isOverlayShowing) {
                hideOverlay()
            }
        }
    }

    // Периодическая задача: таймер теста, проверка входящего звонка и защита OLED от выгорания
    private var tickCounter = 0
    private val periodicTask = object : Runnable {
        override fun run() {
            if (!isOverlayShowing) return

            // 1. Проверка входящего звонка (если включено в настройках)
            if (settings.wakeOnCall && isIncomingCallActive()) {
                hideOverlay()
                return
            }

            // 2. Логика тестового режима (обратный отсчет 10 секунд)
            if (isTestMode) {
                testRemainingSec--
                if (testRemainingSec <= 0) {
                    hideOverlay()
                    return
                }
                updateIndicatorText()
            }

            // 3. Сдвиг индикатора каждые 20 секунд (защита OLED от выгорания)
            tickCounter++
            if (tickCounter % 20 == 0) {
                moveIndicatorRandomly()
            }

            mainHandler.postDelayed(this, 1000L)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        settings = SettingsManager(this)
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenOffReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(screenOffReceiver, filter)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Дополнительных действий на события UI не требуется
    }

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
                } catch (_: Exception) {
                }
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
                } catch (_: Exception) {
                }
            }
            overlayView = null
            indicatorView = null
            overlayParams = null
            isOverlayShowing = false
            isTestMode = false
        }
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
            // Программное снижение подсветки экрана до минимума для этого окна
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

                    // Проверка свайпа
                    if (settings.wakeOnSwipe && distance >= dpToPx(110f)) {
                        hideOverlay()
                        return true
                    }

                    // Проверка двойного / тройного тапа
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

    override fun onDestroy() {
        hideOverlay()
        try {
            unregisterReceiver(screenOffReceiver)
        } catch (_: Exception) {
        }
        instance = null
        super.onDestroy()
    }
}