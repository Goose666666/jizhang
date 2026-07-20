package com.example.jizhang

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * 常驻前台服务:
 *  - 常驻通知,把进程钉在前台优先级(防止 MIUI 冻结后台传感器)
 *  - 通知可点击 → 触发截屏识别(支付页下拉通知即可,不受 FLAG_SECURE 限制)
 *  触发方式:翻转手机(传感器) 或 点击本通知。
 */
class ScanForegroundService : Service() {

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIF_ID, buildNotification())
        return START_STICKY
    }

    // 兼容 ScanService 里的调用:悬浮球已移除,这两个方法留空。
    fun hideBubble() {}
    fun showBubble() {}

    private fun buildNotification(): Notification {
        val channelId = "jizhang_scan"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(channelId) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        channelId, "自动记账扫描",
                        NotificationManager.IMPORTANCE_LOW
                    )
                )
            }
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        // 点击通知 → 触发截屏识别(通知栏在支付页也能用)
        val triggerIntent = Intent(this, ScanTriggerReceiver::class.java).apply {
            action = ScanTriggerReceiver.ACTION_TRIGGER
            setPackage(packageName)
        }
        val pi = android.app.PendingIntent.getBroadcast(
            this, 0, triggerIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                android.app.PendingIntent.FLAG_IMMUTABLE
        )
        return builder
            .setContentTitle("记账 · 点这里记一笔")
            .setContentText("支付后停在成功页,翻转手机或下拉点此通知即可记账")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .setContentIntent(pi)
            .build()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val NOTIF_ID = 1001
        @Volatile var instance: ScanForegroundService? = null
    }
}
