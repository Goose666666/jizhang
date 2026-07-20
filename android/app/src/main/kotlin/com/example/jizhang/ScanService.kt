package com.example.jizhang

import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * 无障碍服务:提供「截屏当前屏幕 → GLM-4V 识别账单 → 写入 inbox」的能力。
 * 由悬浮按钮(ScanForegroundService)点击时调用 captureAndRecognize()。
 */
class ScanService : AccessibilityService(), SensorEventListener {

    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler by lazy { android.os.Handler(mainLooper) }
    @Volatile private var busy = false

    private var sensorManager: SensorManager? = null
    private var accelerometer: Sensor? = null
    private var wasFaceUp = false
    private var lastFlip = 0L
    private var sensorOn = false

    /** 灭屏时注销传感器、亮屏时注册,省电降温(灭屏无需翻转检测)。 */
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_ON -> registerSensor()
                Intent.ACTION_SCREEN_OFF -> unregisterSensor()
            }
        }
    }

    private fun registerSensor() {
        if (sensorOn) return
        // 用 GAME/NORMAL 之间的 NORMAL 档,足够检测翻转,功耗最低
        sensorManager?.registerListener(
            this, accelerometer, SensorManager.SENSOR_DELAY_NORMAL
        )
        sensorOn = true
    }

    private fun unregisterSensor() {
        if (!sensorOn) return
        sensorManager?.unregisterListener(this)
        sensorOn = false
        wasFaceUp = false
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        // 启动前台服务(常驻通知,保活)
        try {
            val i = Intent(this, ScanForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i)
            else startService(i)
        } catch (e: Exception) {
            Log.e(TAG, "前台服务启动失败: ${e.message}")
        }
        // 翻转手势(需 MIUI 省电策略设为无限制,否则后台传感器会被冻)
        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        registerSensor()
        registerReceiver(
            screenReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
            }
        )
        Log.i(TAG, ">>> 无障碍服务已连接")
    }

    override fun onDestroy() {
        unregisterSensor()
        try {
            unregisterReceiver(screenReceiver)
        } catch (_: Exception) {}
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    // ---- 翻转检测:正面朝上 → 翻到反面朝下,触发识别 ----
    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
        val z = event.values[2]
        if (z > 5f) {
            wasFaceUp = true
        } else if (z < -3.5f && wasFaceUp) {
            wasFaceUp = false
            val now = SystemClock.elapsedRealtime()
            if (now - lastFlip < 3000) return
            lastFlip = now
            Log.i(TAG, "检测到翻转,触发识别")
            captureAndRecognize()
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    /** 供悬浮按钮调用:截当前屏 → 识别 → 记账。 */
    fun captureAndRecognize() {
        if (busy) return
        val apiKey = readApiKey()
        if (apiKey.isBlank()) {
            notify("请先在记账App设置里填写 GLM API Key")
            return
        }
        busy = true
        notify("📸 正在识别账单…")
        // 先隐藏悬浮球,等通知栏收起动画结束再截图
        ScanForegroundService.instance?.hideBubble()
        mainHandler.postDelayed({ captureScreenshot(apiKey) }, 600)
    }

    private fun captureScreenshot(apiKey: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            finishBusy("系统版本过低,不支持自动截屏")
            return
        }
        takeScreenshot(Display.DEFAULT_DISPLAY, worker, object : TakeScreenshotCallback {
            override fun onSuccess(screenshot: ScreenshotResult) {
                try {
                    val hw = Bitmap.wrapHardwareBuffer(
                        screenshot.hardwareBuffer, screenshot.colorSpace
                    )
                    val bmp = hw?.copy(Bitmap.Config.ARGB_8888, false)
                    hw?.recycle()
                    screenshot.hardwareBuffer.close()
                    if (bmp == null) {
                        finishBusy("截屏失败")
                        return
                    }
                    recognizeAndSave(bmp, apiKey)
                } catch (e: Exception) {
                    Log.e(TAG, "截屏处理失败: ${e.message}", e)
                    finishBusy("截屏失败")
                }
            }

            override fun onFailure(errorCode: Int) {
                Log.e(TAG, "截屏失败 code=$errorCode")
                finishBusy("截屏失败,请重试")
            }
        })
    }

    private fun recognizeAndSave(bmp: Bitmap, apiKey: String) {
        worker.execute {
            try {
                val bill = GlmClient.recognize(bmp, apiKey)
                if (bill == null) {
                    notify("未识别到账单,请对准支付成功页")
                    return@execute
                }
                writeInbox(bill)
                notify("已记账 ${if (bill.isExpense) "-" else "+"}¥${bill.money} · ${bill.category}")
            } finally {
                bmp.recycle()
                busy = false
                ScanForegroundService.instance?.showBubble()
            }
        }
    }

    private fun finishBusy(msg: String) {
        notify(msg)
        busy = false
        ScanForegroundService.instance?.showBubble()
    }

    private fun writeInbox(bill: GlmClient.Bill) {
        val (parent, child) = if (bill.isExpense) {
            bill.category to bill.merchant
        } else {
            "收入" to bill.category
        }
        val json = JSONObject().apply {
            put("money", bill.money)
            put("parentCategory", parent)
            put("childCategory", child)
            put("time", SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date()))
            put("remark", bill.merchant)
            put("asset", bill.account)
            put("tags", "")
            put("receivedAt", System.currentTimeMillis())
        }
        File(filesDir, "inbox.jsonl").appendText(json.toString() + "\n")
        Log.i(TAG, "已写入账单: $json")
    }

    private fun readApiKey(): String = try {
        val f = File(filesDir, "config.json")
        if (!f.exists()) "" else JSONObject(f.readText()).optString("glmKey", "")
    } catch (e: Exception) {
        ""
    }

    private fun notify(msg: String) {
        mainHandler.post { Toast.makeText(this, msg, Toast.LENGTH_SHORT).show() }
        try {
            val channelId = "jizhang_scan"
            val nm = getSystemService(android.app.NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                nm.getNotificationChannel(channelId) == null) {
                nm.createNotificationChannel(
                    android.app.NotificationChannel(
                        channelId, "自动记账扫描",
                        android.app.NotificationManager.IMPORTANCE_HIGH
                    )
                )
            }
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                android.app.Notification.Builder(this, channelId)
            } else {
                @Suppress("DEPRECATION") android.app.Notification.Builder(this)
            }
            nm.notify(2002, builder
                .setContentTitle("自动记账")
                .setContentText(msg)
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setAutoCancel(true)
                .build())
        } catch (_: Exception) {}
    }

    companion object {
        private const val TAG = "JZSCAN"
        @Volatile var instance: ScanService? = null
    }
}
