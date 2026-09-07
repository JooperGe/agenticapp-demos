package com.example.ultraalarm

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat

class AlarmReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AlarmReceiver"
        private const val CHANNEL_ID = "alarm_trigger"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val alarmId = intent.getIntExtra("alarm_id", -1)
        Log.d(TAG, "闹钟触发！ alarmId=$alarmId SDK=${Build.VERSION.SDK_INT}")

        // 1) WakeLock：唤醒 CPU / 屏幕
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
            "UltraAlarm:AlarmWakeLock"
        )
        wakeLock.acquire(30_000L)
        Log.d(TAG, "WakeLock acquired")

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // 诊断：通知权限与全屏 Intent 能力
        val notifGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else true
        val canFull = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            nm.canUseFullScreenIntent()
        } else true
        Log.d(TAG, "POST_NOTIFICATIONS granted=$notifGranted, canUseFullScreenIntent=$canFull")

        // 启动全屏 Activity
        val fullScreenIntent = Intent(context, AlarmFullScreenActivity::class.java).apply {
            putExtra("alarm_id", alarmId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        // 2) 创建高重要性、带闹钟铃声、可绕过勿扰的渠道
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "闹钟触发",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "闹钟响起时的通知"
                setShowBadge(true)
                enableVibration(true)
                setBypassDnd(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
                val audioAttributes = AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .build()
                setSound(Settings.System.DEFAULT_ALARM_ALERT_URI, audioAttributes)
            }
            nm.createNotificationChannel(channel)
        }

        // 3) 全屏通知：屏幕锁屏/熄灭时直接拉起 Activity；亮屏时显示为横幅通知
        val pendingIntent = PendingIntent.getActivity(
            context,
            alarmId,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = android.app.Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("闹钟响了")
            .setContentText("点击查看")
            .setCategory(android.app.Notification.CATEGORY_ALARM)
            .setPriority(android.app.Notification.PRIORITY_MAX)
            .setFullScreenIntent(pendingIntent, true)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()

        nm.notify(alarmId, notification)
        Log.d(TAG, "Notification posted, id=$alarmId")

        // 兜底：直接发送启动全屏 Activity 的 PendingIntent。
        // 部分机型在亮屏/特定锁屏状态下会把全屏 Intent 降级为普通横幅，这里强制再触发一次。
        try {
            pendingIntent.send()
            Log.d(TAG, "Directly sent fullScreen PendingIntent")
        } catch (e: Exception) {
            Log.w(TAG, "Direct PendingIntent.send failed: ${e.message}")
        }
    }
}
