package com.example.ultraalarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.util.Log

class AlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AlarmReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "闹钟触发！")

        val alarmId = intent.getIntExtra("alarm_id", -1)
        Log.d(TAG, "Alarm ID: $alarmId")

        // 获取 WakeLock，确保 CPU 保持唤醒
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.FULL_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
            "UltraAlarm:AlarmWakeLock"
        )
        wakeLock.acquire(30_000L)

        // 启动全屏 Activity
        val fullScreenIntent = Intent(context, AlarmFullScreenActivity::class.java).apply {
            putExtra("alarm_id", alarmId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ 通过全屏通知方式启动
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager

            val channelId = "alarm_trigger"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = android.app.NotificationChannel(
                    channelId,
                    "闹钟触发",
                    android.app.NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "闹钟响起时的通知"
                    setShowBadge(false)
                    enableVibration(true)
                }
                notificationManager.createNotificationChannel(channel)
            }

            val pendingIntent = PendingIntent.getActivity(
                context,
                alarmId,
                fullScreenIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = android.app.Notification.Builder(context, channelId)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle("闹钟响了")
                .setContentText("点击查看")
                .setPriority(android.app.Notification.PRIORITY_MAX)
                .setFullScreenIntent(pendingIntent, true)
                .setAutoCancel(true)
                .build()

            notificationManager.notify(alarmId, notification)
        } else {
            context.startActivity(fullScreenIntent)
        }
    }
}
