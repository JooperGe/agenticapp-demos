package com.example.ultraalarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 监听手机重启事件，重新注册所有闹钟
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Log.d(TAG, "手机重启完成，重新注册闹钟")
            // 完整版中从 Room 读取所有闹钟重新注册
        }
    }
}
