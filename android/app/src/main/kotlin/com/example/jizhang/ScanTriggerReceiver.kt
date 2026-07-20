package com.example.jizhang

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 接收「常驻通知被点击」的广播,触发截屏识别。
 * 通知栏不受支付页 FLAG_SECURE 限制,是支付成功页唯一可靠的触发入口。
 */
class ScanTriggerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TRIGGER) {
            ScanService.instance?.captureAndRecognize()
        }
    }

    companion object {
        const val ACTION_TRIGGER = "com.example.jizhang.SCAN_TRIGGER"
    }
}
