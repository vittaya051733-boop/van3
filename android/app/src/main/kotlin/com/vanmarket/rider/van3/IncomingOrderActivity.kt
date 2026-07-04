package com.vanmarket.rider.van3

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager

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
        hasForwarded = false
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
        if (hasForwarded || orderId.isEmpty()) {
            return
        }
        hasForwarded = true
        Log.i(TAG, "Forwarding to MainActivity orderId=$orderId")
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_SHOW_INCOMING_ORDER
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtras(intent)
        }
        startActivity(launchIntent)
        finish()
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

    companion object {
        private const val TAG = "IncomingOrderActivity"
    }
}