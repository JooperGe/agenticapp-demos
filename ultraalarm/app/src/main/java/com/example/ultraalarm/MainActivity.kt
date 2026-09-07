package com.example.ultraalarm

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.Manifest
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import java.util.Calendar

class MainActivity : ComponentActivity() {

    private val alarmId = 1001

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    AlarmSetupScreen()
                }
            }
        }
    }

    @Composable
    fun AlarmSetupScreen() {
        val context = LocalContext.current

        // Android 13+ 需要运行时申请通知权限，否则闹钟触发时无法弹出全屏通知
        val notificationPermissionLauncher = rememberLauncherForActivityResult(
            ActivityResultContracts.RequestPermission()
        ) { granted ->
            if (!granted) {
                Toast.makeText(
                    context,
                    "未授予通知权限，闹钟触发时可能无法弹出全屏页面",
                    Toast.LENGTH_LONG
                ).show()
            }
        }

        LaunchedEffect(Unit) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val granted = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.POST_NOTIFICATIONS
                ) == PackageManager.PERMISSION_GRANTED
                if (!granted) {
                    notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                }
            }
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = "UltraAlarm",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "极简全屏图片闹钟验证",
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
            )

            Spacer(modifier = Modifier.height(48.dp))

            Button(
                onClick = {
                    val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    when {
                        // 1) 通知权限（Android 13+）：未授予时通知会被静默丢弃
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            ContextCompat.checkSelfPermission(
                                context,
                                Manifest.permission.POST_NOTIFICATIONS
                            ) != PackageManager.PERMISSION_GRANTED -> {
                            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                        }

                        // 2) 全屏显示权限（Android 14+ 特殊访问）：未授予时无法拉起全屏闹钟页
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
                            !nm.canUseFullScreenIntent() -> {
                            Toast.makeText(
                                context,
                                "请授予「显示在其他应用上层/全屏显示」权限后再点击",
                                Toast.LENGTH_LONG
                            ).show()
                            startActivity(
                                Intent(android.provider.Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                    data = Uri.parse("package:${context.packageName}")
                                }
                            )
                        }

                        // 3) 精确闹钟权限（Android 12+）
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                            !(context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
                                .canScheduleExactAlarms() -> {
                            startActivity(
                                Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                    data = Uri.parse("package:${context.packageName}")
                                }
                            )
                        }

                        else -> {
                            scheduleAlarm(context)
                            startAlarmService(context)
                        }
                    }
                },
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary
                ),
                modifier = Modifier
                    .padding(horizontal = 40.dp)
                    .height(56.dp)
            ) {
                Text(
                    text = "设置 1 分钟后闹钟",
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Medium
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            Button(
                onClick = {
                    // 前台直接启动，绕过闹钟/通知/全屏 Intent 链路，用于隔离测试
                    startActivity(Intent(context, AlarmFullScreenActivity::class.java))
                },
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.tertiary
                ),
                modifier = Modifier
                    .padding(horizontal = 40.dp)
                    .height(48.dp)
            ) {
                Text(
                    text = "立即测试全屏页",
                    fontSize = 16.sp
                )
            }
        }
    }

    private fun scheduleAlarm(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("alarm_id", alarmId)
            action = "ACTION_ALARM_TRIGGER_$alarmId"
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            alarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val triggerTime = System.currentTimeMillis() + 60_000L // 1分钟后

        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            triggerTime,
            pendingIntent
        )

        // 显示触发时间
        val cal = Calendar.getInstance()
        cal.timeInMillis = triggerTime
        val timeStr = String.format(
            "%02d:%02d:%02d",
            cal.get(Calendar.HOUR_OF_DAY),
            cal.get(Calendar.MINUTE),
            cal.get(Calendar.SECOND)
        )

        Toast.makeText(
            context,
            "闹钟已设置于 $timeStr（1分钟后）",
            Toast.LENGTH_LONG
        ).show()
    }

    private fun startAlarmService(context: Context) {
        val serviceIntent = Intent(context, AlarmForegroundService::class.java)
        ContextCompat.startForegroundService(context, serviceIntent)
    }
}
