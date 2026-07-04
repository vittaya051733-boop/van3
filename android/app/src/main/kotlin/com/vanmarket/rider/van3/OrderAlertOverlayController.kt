package com.vanmarket.rider.van3

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

data class OrderAlertOverlayData(
    val orderId: String,
    val title: String,
    val body: String,
)

object OrderAlertOverlayController {
    private var overlayView: View? = null
    private var windowManager: WindowManager? = null
    private var currentOrderId: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var autoDismissRunnable: Runnable? = null
    private const val AUTO_DISMISS_MS = 60_000L

    fun show(
        context: Context,
        data: OrderAlertOverlayData,
        onOpenOrders: () -> Unit,
        onDismiss: () -> Unit,
    ) {
        if (!canDrawOverlays(context)) {
            return
        }
        if (currentOrderId == data.orderId && overlayView != null) {
            return
        }
        dismiss()

        val appContext = context.applicationContext
        val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return

        val scrim = FrameLayout(appContext).apply {
            setBackgroundColor(0xA6000000.toInt())
            isClickable = true
            isFocusable = true
        }

        val card = LinearLayout(appContext).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(appContext, 24), dp(appContext, 28), dp(appContext, 24), dp(appContext, 24))
            background = GradientDrawable().apply {
                setColor(Color.WHITE)
                cornerRadius = dp(appContext, 28).toFloat()
            }
        }

        val badge = TextView(appContext).apply {
            text = "ออเดอร์ใหม่ยืนยันแล้ว"
            setTextColor(Color.parseColor("#C2410C"))
            textSize = 15f
            setTypeface(typeface, Typeface.BOLD)
        }

        val titleView = TextView(appContext).apply {
            text = data.title
            setTextColor(Color.parseColor("#111827"))
            textSize = 24f
            gravity = Gravity.CENTER
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, dp(appContext, 18), 0, dp(appContext, 8))
        }

        val bodyView = TextView(appContext).apply {
            text = data.body
            setTextColor(Color.parseColor("#374151"))
            textSize = 16f
            gravity = Gravity.CENTER
        }

        val orderIdView = TextView(appContext).apply {
            text = "Order ID: ${data.orderId}"
            setTextColor(Color.parseColor("#6B7280"))
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(0, dp(appContext, 12), 0, 0)
        }

        val buttonRow = LinearLayout(appContext).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, dp(appContext, 28), 0, 0)
        }

        val dismissButton = buildActionButton(
            context = appContext,
            label = "ปิดก่อน",
            backgroundColor = Color.parseColor("#E5E7EB"),
            textColor = Color.parseColor("#111827"),
        ) {
            dismiss()
            onDismiss()
        }

        val openButton = buildActionButton(
            context = appContext,
            label = "เปิดหน้ารับงาน",
            backgroundColor = Color.parseColor("#EA580C"),
            textColor = Color.WHITE,
        ) {
            dismiss()
            onOpenOrders()
        }

        buttonRow.addView(dismissButton)
        buttonRow.addView(openButton)

        card.addView(badge)
        card.addView(titleView)
        card.addView(bodyView)
        card.addView(orderIdView)
        card.addView(buttonRow)

        val cardParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER,
        ).apply {
            leftMargin = dp(appContext, 24)
            rightMargin = dp(appContext, 24)
        }
        scrim.addView(card, cardParams)

        val windowType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            windowType,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.CENTER
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }

        wm.addView(scrim, layoutParams)
        overlayView = scrim
        windowManager = wm
        currentOrderId = data.orderId
        scheduleAutoDismiss()
    }

    private fun scheduleAutoDismiss() {
        autoDismissRunnable?.let { mainHandler.removeCallbacks(it) }
        autoDismissRunnable = Runnable { dismiss() }
        mainHandler.postDelayed(autoDismissRunnable!!, AUTO_DISMISS_MS)
    }

    private fun cancelAutoDismiss() {
        autoDismissRunnable?.let { mainHandler.removeCallbacks(it) }
        autoDismissRunnable = null
    }

    fun dismiss(orderId: String? = null) {
        if (orderId != null && currentOrderId != null && orderId != currentOrderId) {
            return
        }
        cancelAutoDismiss()
        val view = overlayView ?: return
        val wm = windowManager
        try {
            wm?.removeViewImmediate(view)
        } catch (_: Exception) {
        }
        overlayView = null
        windowManager = null
        currentOrderId = null
    }

    private fun canDrawOverlays(context: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)
    }

    private fun buildActionButton(
        context: Context,
        label: String,
        backgroundColor: Int,
        textColor: Int,
        onClick: () -> Unit,
    ): Button {
        return Button(context).apply {
            text = label
            isAllCaps = false
            setTextColor(textColor)
            textSize = 16f
            minHeight = dp(context, 52)
            minimumHeight = dp(context, 52)
            background = GradientDrawable().apply {
                setColor(backgroundColor)
                cornerRadius = dp(context, 18).toFloat()
            }
            setPadding(dp(context, 18), dp(context, 12), dp(context, 18), dp(context, 12))
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginStart = dp(context, 6)
                marginEnd = dp(context, 6)
            }
        }
    }

    private fun dp(context: Context, value: Int): Int {
        return (value * context.resources.displayMetrics.density).toInt()
    }
}