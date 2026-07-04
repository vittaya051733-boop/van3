package com.vanmarket.rider.van3

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.RingtoneManager
import android.os.Build

object RiderNotificationChannels {
    const val CALL_CHANNEL_ID = "call_channel"
    const val ORDER_WAKE_CHANNEL_ID = "incoming_order_wakeup_v2"
    const val URGENT_JOBS_CHANNEL_ID = "rider_jobs_urgent_sound"
    const val CHAT_CHANNEL_ID = "chat_wakeup_channel_v1"
    const val ANNOUNCEMENT_CHANNEL_ID = "rider_announcements"

    fun ensureAll(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        notificationManager.createNotificationChannel(
            NotificationChannel(
                CALL_CHANNEL_ID,
                "Incoming Calls",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Full-screen notifications for incoming calls"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setBypassDnd(true)
                enableVibration(true)
            },
        )

        notificationManager.createNotificationChannel(
            NotificationChannel(
                ORDER_WAKE_CHANNEL_ID,
                "Order Alerts",
                NotificationManager.IMPORTANCE_MAX,
            ).apply {
                description = "Urgent incoming order notifications that can wake the screen"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setBypassDnd(true)
                enableVibration(true)
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                    Notification.AUDIO_ATTRIBUTES_DEFAULT,
                )
            },
        )

        notificationManager.createNotificationChannel(
            NotificationChannel(
                URGENT_JOBS_CHANNEL_ID,
                "Rider Jobs Urgent",
                NotificationManager.IMPORTANCE_MAX,
            ).apply {
                description = "Urgent rider job alerts with sound"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setBypassDnd(true)
                enableVibration(true)
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                    Notification.AUDIO_ATTRIBUTES_DEFAULT,
                )
            },
        )

        notificationManager.createNotificationChannel(
            NotificationChannel(
                CHAT_CHANNEL_ID,
                "Chat Messages",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Lock-screen notifications for new chat messages"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                enableVibration(true)
            },
        )

        notificationManager.createNotificationChannel(
            NotificationChannel(
                ANNOUNCEMENT_CHANNEL_ID,
                "Admin Announcements",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Platform announcements for riders"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                enableVibration(true)
            },
        )
    }
}
