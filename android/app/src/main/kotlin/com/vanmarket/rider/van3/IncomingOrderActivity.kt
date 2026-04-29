package com.vanmarket.rider.van3

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

class IncomingOrderActivity : Activity() {
    private var orderId: String = ""
    private var hasForwarded = false

    override fun onCreate(savedInstanceState: Bundle?) {
        applyWakeWindowFlags()
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        Log.i(TAG, "onCreate orderId=$orderId action=${intent?.action}")
        if (orderId.isEmpty()) {
            finish()
            return
        }
        setContentView(buildContentView())
        openFlutterOrderScreen()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
        Log.i(TAG, "onNewIntent orderId=$orderId action=${intent.action}")
        if (orderId.isEmpty()) {
            finish()
            return
        }
        openFlutterOrderScreen()
    }

    override fun onResume() {
        super.onResume()
        Log.i(TAG, "onResume orderId=$orderId hasForwarded=$hasForwarded")
        if (!hasForwarded && orderId.isNotEmpty()) {
            openFlutterOrderScreen()
        }
    }

    private fun handleIntent(intent: Intent?) {
        orderId = intent?.getStringExtra(MainActivity.EXTRA_ORDER_ID).orEmpty()
    }

    private fun openFlutterOrderScreen() {
        if (hasForwarded) {
            return
        }
        hasForwarded = true
        Log.i(TAG, "Forwarding to MainActivity orderId=$orderId")
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_SHOW_INCOMING_ORDER
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtras(intent)
        }
        startActivity(launchIntent)
        finish()
    }

    private fun buildContentView(): LinearLayout {
        val title = intent.getStringExtra(MainActivity.EXTRA_ORDER_TITLE).orEmpty().ifBlank { "มีออเดอร์ใหม่" }
        val body = intent.getStringExtra(MainActivity.EXTRA_ORDER_BODY).orEmpty().ifBlank { "กำลังเปิดหน้ารับงาน" }

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(0xFFF5F7FF.toInt())
            setPadding(dp(24), dp(32), dp(24), dp(32))

            addView(ProgressBar(context).apply {
                isIndeterminate = true
            })

            addView(TextView(context).apply {
                text = title
                setTextColor(0xFF111827.toInt())
                textSize = 28f
                gravity = Gravity.CENTER
                setPadding(0, dp(24), 0, dp(12))
            })

            addView(TextView(context).apply {
                text = body
                setTextColor(0xFF4B5563.toInt())
                textSize = 18f
                gravity = Gravity.CENTER
            })
        }
    }

    private fun applyWakeWindowFlags() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            )
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    companion object {
        private const val TAG = "IncomingOrderActivity"
    }
}