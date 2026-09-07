package com.example.ultraalarm

import android.app.KeyguardManager
import android.os.Bundle
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

class AlarmFullScreenActivity : ComponentActivity() {

    companion object {
        private const val TAG = "AlarmFullScreenActivity"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val alarmId = intent?.getIntExtra("alarm_id", -1) ?: -1
        Log.d(TAG, "onCreate alarmId=$alarmId isTaskRoot=$isTaskRoot")

        // ★ 现代 API（推荐，替代已废弃的 window flag）：屏幕点亮 + 锁屏上方显示
        setShowWhenLocked(true)
        setTurnScreenOn(true)

        // 兼容旧版 flag：保持屏幕常亮 + 全屏
        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                    or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                    or WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                    or WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
                    or WindowManager.LayoutParams.FLAG_FULLSCREEN
        )

        // 尝试自动解除非安全锁（安全锁需用户输入 PIN/密码，无法绕过）
        try {
            val km = getSystemService(KeyguardManager::class.java)
            if (km.isKeyguardLocked) {
                km.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                    override fun onDismissError() { Log.w(TAG, "keyguard dismiss: error") }
                    override fun onDismissCancelled() { Log.w(TAG, "keyguard dismiss: cancelled") }
                    override fun onDismissSucceeded() { Log.d(TAG, "keyguard dismiss: succeeded") }
                })
            }
        } catch (e: Exception) {
            Log.w(TAG, "keyguard dismiss failed: ${e.message}")
        }

        // 沉浸模式
        @Suppress("DEPRECATION")
        window.decorView.apply {
            systemUiVisibility = (
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            )
        }

        setContent {
            AlarmContent(onDismiss = { finishAndRemoveTask() })
        }
        Log.d(TAG, "setContent done")
    }

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "onResume")
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy")
        super.onDestroy()
    }

    // 拦截电源键——不让按电源键回桌面
    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_POWER) {
            return true
        }
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    // 拦截返回键
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // 不让返回
    }

    @Composable
    fun AlarmContent(onDismiss: () -> Unit) {
        var showDismiss by remember { mutableStateOf(false) }

        // 3秒延迟后显示关闭按钮
        LaunchedEffect(Unit) {
            delay(3000L)
            showDismiss = true
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black)
                .clickable(enabled = showDismiss) { onDismiss() },
            contentAlignment = Alignment.Center
        ) {
            // 全屏显示图片
            Image(
                painter = painterResource(id = R.drawable.alarm),
                contentDescription = "闹钟背景",
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.FillBounds
            )

            // 兜底可见文字：即便图片加载失败，也能确认 Activity 已渲染
            Text(
                text = "闹钟响啦！",
                color = Color.White,
                fontSize = 40.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.Center)
            )

            // 底部关闭提示（延迟显示）
            AnimatedVisibility(
                visible = showDismiss,
                enter = fadeIn() + slideInVertically { it },
                modifier = Modifier.align(Alignment.BottomCenter)
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(bottom = 60.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Bottom
                ) {
                    Text(
                        text = "点击屏幕关闭",
                        color = Color.White.copy(alpha = 0.6f),
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Medium
                    )
                }
            }
        }
    }
}
