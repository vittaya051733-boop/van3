package com.vanmarket.rider.van3

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

class VanFirebaseMessagingService : FlutterFirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        Log.i(TAG, "onMessageReceived type=${data["type"]} orderId=${data["orderId"]} foreground=${VanRiderApp.isAppInForeground()}")
        when (data["type"]) {
            "call" -> {
                showIncomingCallNotification(data)
                super.onMessageReceived(message)
            }
            "call_cancel" -> {
                dismissIncomingCall(data)
                super.onMessageReceived(message)
            }
            "chat" -> {
                showChatNotificationIfNeeded(data)
                super.onMessageReceived(message)
            }
            else -> {
                if (shouldPresentConfirmedOrderAlert(data)) {
                    showOrderNotificationIfNeeded(message)
                    // Native path already posts the urgent full-screen notification.
                    return
                }
                super.onMessageReceived(message)
            }
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
    }

    private fun showIncomingCallNotification(data: Map<String, String>) {
        val channelId = data["channelId"] ?: return
        val appId = data["appId"]
        val token = data["token"] ?: return
        val callerName = data["callerName"] ?: "ผู้โทร"
        val callerId = data["callerId"] ?: data["caller_id"]
        val callerPhoto = data["callerPhotoUrl"]
        val isVideo = data["callType"] == "video" || data["isVideo"].equals("true", true)

        val incomingActivityIntent = IncomingCallActivityIntentBuilder.build(
            context = this,
            channelId = channelId,
            appId = appId,
            token = token,
            callerId = callerId,
            callerName = callerName,
            callerPhoto = callerPhoto,
            isVideo = isVideo,
        )

        val pendingIntent = PendingIntent.getActivity(
            this,
            REQUEST_CODE_INCOMING_CALL,
            incomingActivityIntent,
            pendingIntentFlags(),
        )

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        RiderNotificationChannels.ensureAll(this)
        wakeDeviceForIncomingCall()

        val notification = NotificationCompat.Builder(this, RiderNotificationChannels.CALL_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(if (isVideo) "สายวิดีโอคอลเข้า" else "สายเข้าจาก $callerName")
            .setContentText("แตะเพื่อรับสาย")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setOngoing(true)
            .setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(pendingIntent, true)
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
            .setContentIntent(pendingIntent)
            .setTimeoutAfter(60000)
            .build()

        notificationManager.notify(NOTIFICATION_ID_INCOMING_CALL, notification)
        CallIntentRouter.deliverIntent(incomingActivityIntent)
        try {
            startActivity(incomingActivityIntent)
        } catch (error: Exception) {
            Log.w(TAG, "Unable to start call UI", error)
        }
    }

    private fun dismissIncomingCall(data: Map<String, String>) {
        val channelId = data["channelId"] ?: return
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID_INCOMING_CALL)
        IncomingCallOverlayController.dismiss(channelId)
        IncomingCallActivity.dismissIfShowing(channelId)
        sendCancelIntent(channelId)
    }

    private fun showChatNotificationIfNeeded(data: Map<String, String>) {
        if (VanRiderApp.isAppInForeground()) {
            return
        }

        val chatId = data["chatId"] ?: data["chat_id"] ?: "chat"
        val senderName = data["senderName"] ?: data["title"] ?: "ข้อความใหม่"
        val body = data["message"] ?: data["body"] ?: "แตะเพื่ออ่านข้อความ"
        val openIntent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_SHOW_CHAT_NOTIFICATION
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("type", "chat")
            putExtra("chatId", chatId)
            putExtra("senderId", data["senderId"] ?: data["sender_id"].orEmpty())
            putExtra("senderName", senderName)
            putExtra("message", body)
            putExtra("orderId", data["orderId"].orEmpty())
            putExtra(MainActivity.EXTRA_CHAT_ID, chatId)
            putExtra(MainActivity.EXTRA_SENDER_ID, data["senderId"] ?: data["sender_id"].orEmpty())
            putExtra(MainActivity.EXTRA_SENDER_NAME, senderName)
            putExtra(MainActivity.EXTRA_MESSAGE, body)
            putExtra(MainActivity.EXTRA_ORDER_ID, data["orderId"].orEmpty())
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            chatId.hashCode(),
            openIntent,
            pendingIntentFlags(),
        )

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        RiderNotificationChannels.ensureAll(this)
        wakeDevice("incoming_chat", 2000)

        val notification = NotificationCompat.Builder(this, RiderNotificationChannels.CHAT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_action_chat)
            .setContentTitle(senderName)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(pendingIntent)
            .build()

        notificationManager.notify((data["notificationId"] ?: chatId).hashCode(), notification)
    }

    private fun showOrderNotificationIfNeeded(message: RemoteMessage) {
        val data = message.data
        if (!shouldPresentConfirmedOrderAlert(data)) {
            Log.d(TAG, "Skipping order alert for payloadKeys=${data.keys}")
            return
        }

        val title = data["title"]
            ?: message.notification?.title
            ?: "มีออเดอร์ใหม่"
        val body = data["body"]
            ?: message.notification?.body
            ?: "แตะเพื่อดูรายละเอียดออเดอร์"
        val orderId = data["orderId"] ?: data["jobId"] ?: return

        val openIntent = MainActivityOrderIntentBuilder.build(
            context = this,
            orderId = orderId,
            title = title,
            body = body,
        )

        val wakeIntent = IncomingOrderActivityIntentBuilder.build(
            context = this,
            orderId = orderId,
            title = title,
            body = body,
        )

        val pendingIntent = PendingIntent.getActivity(
            this,
            REQUEST_CODE_ORDER,
            wakeIntent,
            pendingIntentFlags(),
        )

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        RiderNotificationChannels.ensureAll(this)
        wakeDeviceForIncomingOrder()

        val notificationId = orderId.hashCode()
        Log.i(
            TAG,
            "Presenting incoming order alert orderId=$orderId foreground=${VanRiderApp.isAppInForeground()} title=$title",
        )

        val notification = NotificationCompat.Builder(this, RiderNotificationChannels.ORDER_WAKE_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setAutoCancel(true)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setOngoing(true)
            .setTimeoutAfter(60000)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(pendingIntent, true)
            .setContentIntent(pendingIntent)
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
            .build()

        notificationManager.notify(notificationId, notification)
        Log.i(TAG, "Posted wake notification id=$notificationId orderId=$orderId")

        OrderIntentRouter.deliverFromFcm(
            orderId = orderId,
            title = title,
            body = body,
            appWasForeground = VanRiderApp.isAppInForeground(),
        )
        try {
            startActivity(wakeIntent)
        } catch (error: Exception) {
            Log.w(TAG, "Unable to start order UI", error)
            showOrderAlertOverlay(
                orderId = orderId,
                title = title,
                body = body,
                openIntent = openIntent,
            )
        }

        if (!canUseFullScreenIntent()) {
            Log.i(TAG, "Full-screen intent unavailable; showing native order overlay orderId=$orderId")
            showOrderAlertOverlay(
                orderId = orderId,
                title = title,
                body = body,
                openIntent = openIntent,
            )
        }
    }

    private fun shouldPresentConfirmedOrderAlert(data: Map<String, String>): Boolean {
        val type = data["type"]?.trim()
        val orderId = data["orderId"]?.trim().orEmpty().ifEmpty { data["jobId"]?.trim().orEmpty() }
        if (type != "app_notification" || orderId.isEmpty()) {
            return false
        }

        val sourceApp = data["sourceApp"]?.trim()
        if (sourceApp != "van2_customer") {
            return false
        }

        val customerConfirmed = data["customerConfirmed"].equals("true", true) || data["customerConfirmed"] == "1"
        val riderNotifyReady = data["riderNotifyReady"].equals("true", true) || data["riderNotifyReady"] == "1"
        return customerConfirmed && riderNotifyReady
    }

    private fun showOrderAlertOverlay(
        orderId: String,
        title: String,
        body: String,
        openIntent: Intent,
    ) {
        OrderAlertOverlayController.show(
            context = this,
            data = OrderAlertOverlayData(
                orderId = orderId,
                title = title,
                body = body,
            ),
            onOpenOrders = {
                try {
                    startActivity(openIntent)
                } catch (error: Exception) {
                    Log.w(TAG, "Unable to open order screen from overlay", error)
                }
            },
            onDismiss = {},
        )
    }

    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return true
        }
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
        return notificationManager?.canUseFullScreenIntent() ?: true
    }

    private fun wakeDeviceForIncomingCall() {
        wakeDevice("incoming_call", 3000)
    }

    private fun wakeDevice(reason: String, timeoutMillis: Long) {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
            @Suppress("DEPRECATION")
            val wakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                "$packageName:$reason",
            )
            wakeLock.acquire(timeoutMillis)
        } catch (error: Exception) {
            Log.w(TAG, "Unable to acquire wake lock for $reason", error)
        }
    }

    private fun wakeDeviceForIncomingOrder() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
            @Suppress("DEPRECATION")
            val wakeLock = powerManager.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                "$packageName:incoming_order",
            )
            wakeLock.acquire(3000)
        } catch (error: Exception) {
            Log.w(TAG, "Unable to acquire wake lock for incoming order", error)
        }
    }

    private fun pendingIntentFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            flags = flags or PendingIntent.FLAG_ALLOW_UNSAFE_IMPLICIT_INTENT
        }
        return flags
    }

    companion object {
        private const val REQUEST_CODE_INCOMING_CALL = 3182
        private const val REQUEST_CODE_ORDER = 3183
        const val NOTIFICATION_ID_INCOMING_CALL = 2387
        private const val TAG = "VanRiderFcmService"
    }
}

private object MainActivityOrderIntentBuilder {
    fun build(
        context: Context,
        orderId: String,
        title: String,
        body: String,
    ) = Intent(context, MainActivity::class.java).apply {
        action = MainActivity.ACTION_SHOW_INCOMING_ORDER
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        putExtra(MainActivity.EXTRA_ORDER_ID, orderId)
        putExtra(MainActivity.EXTRA_ORDER_TITLE, title)
        putExtra(MainActivity.EXTRA_ORDER_BODY, body)
        putExtra(MainActivity.EXTRA_APP_WAS_FOREGROUND, VanRiderApp.isAppInForeground())
    }
}

private object IncomingOrderActivityIntentBuilder {
    fun build(
        context: Context,
        orderId: String,
        title: String,
        body: String,
    ) = Intent(context, IncomingOrderActivity::class.java).apply {
        action = MainActivity.ACTION_SHOW_INCOMING_ORDER
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
        putExtra(MainActivity.EXTRA_ORDER_ID, orderId)
        putExtra(MainActivity.EXTRA_ORDER_TITLE, title)
        putExtra(MainActivity.EXTRA_ORDER_BODY, body)
        putExtra(MainActivity.EXTRA_APP_WAS_FOREGROUND, VanRiderApp.isAppInForeground())
    }
}

private object MainActivityIntentBuilder {
    fun build(
        context: Context,
        channelId: String,
        token: String,
        callerId: String?,
        callerName: String,
        callerPhoto: String?,
        isVideo: Boolean,
    ) = Intent(context, MainActivity::class.java).apply {
        action = MainActivity.ACTION_SHOW_INCOMING_CALL
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
        putExtra(MainActivity.EXTRA_CHANNEL_ID, channelId)
        putExtra(MainActivity.EXTRA_CALL_TOKEN, token)
        putExtra(MainActivity.EXTRA_CALLER_ID, callerId.orEmpty())
        putExtra(MainActivity.EXTRA_CALLER_NAME, callerName)
        putExtra(MainActivity.EXTRA_CALLER_PHOTO, callerPhoto)
        putExtra(MainActivity.EXTRA_IS_VIDEO, isVideo)
        putExtra(MainActivity.EXTRA_APP_WAS_FOREGROUND, VanRiderApp.isAppInForeground())
    }

    fun cancelIntent(context: Context, channelId: String) = Intent(context, MainActivity::class.java).apply {
        action = MainActivity.ACTION_CANCEL_INCOMING_CALL
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        putExtra(MainActivity.EXTRA_CHANNEL_ID, channelId)
    }
}

private object IncomingCallActivityIntentBuilder {
    fun build(
        context: Context,
        channelId: String,
        appId: String?,
        token: String,
        callerId: String?,
        callerName: String,
        callerPhoto: String?,
        isVideo: Boolean,
    ) = Intent(context, IncomingCallActivity::class.java).apply {
        action = MainActivity.ACTION_SHOW_INCOMING_CALL
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
        putExtra(MainActivity.EXTRA_CHANNEL_ID, channelId)
        putExtra(MainActivity.EXTRA_APP_ID, appId)
        putExtra(MainActivity.EXTRA_CALL_TOKEN, token)
        putExtra(MainActivity.EXTRA_CALLER_ID, callerId.orEmpty())
        putExtra(MainActivity.EXTRA_CALLER_NAME, callerName)
        putExtra(MainActivity.EXTRA_CALLER_PHOTO, callerPhoto)
        putExtra(MainActivity.EXTRA_IS_VIDEO, isVideo)
        putExtra(MainActivity.EXTRA_APP_WAS_FOREGROUND, VanRiderApp.isAppInForeground())
    }
}

private fun VanFirebaseMessagingService.sendCancelIntent(channelId: String) {
    val intent = MainActivityIntentBuilder.cancelIntent(this, channelId)
    CallIntentRouter.deliverIntent(intent)
}
