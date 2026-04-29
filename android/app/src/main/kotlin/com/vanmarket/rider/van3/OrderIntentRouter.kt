package com.vanmarket.rider.van3

import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object OrderIntentRouter {
    private const val CHANNEL_NAME = "van.rider/order_intents"
    private const val METHOD_DRAIN_PENDING = "drain_pending_order_intents"

    private var channel: MethodChannel? = null
    private val pendingPayloads = mutableListOf<Map<String, Any?>>()
    private var flutterReady = false
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(flutterEngine: FlutterEngine) {
        if (channel != null) {
            return
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    METHOD_DRAIN_PENDING -> {
                        flutterReady = true
                        val snapshot = ArrayList(pendingPayloads)
                        pendingPayloads.clear()
                        result.success(snapshot)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun deliverIntent(intent: Intent?) {
        val payload = extractPayload(intent) ?: return
        val methodChannel = channel
        if (methodChannel == null || !flutterReady) {
            pendingPayloads.add(payload)
        } else {
            mainHandler.post {
                methodChannel.invokeMethod("incoming_order_intent", payload)
            }
        }
    }

    private fun extractPayload(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        if (intent.action != MainActivity.ACTION_SHOW_INCOMING_ORDER) {
            return null
        }

        val orderId = intent.getStringExtra(MainActivity.EXTRA_ORDER_ID)?.trim().orEmpty()
        if (orderId.isEmpty()) {
            return null
        }

        return mapOf(
            "orderId" to orderId,
            "title" to intent.getStringExtra(MainActivity.EXTRA_ORDER_TITLE),
            "body" to intent.getStringExtra(MainActivity.EXTRA_ORDER_BODY),
            "appWasForeground" to intent.getBooleanExtra(MainActivity.EXTRA_APP_WAS_FOREGROUND, true),
        )
    }
}