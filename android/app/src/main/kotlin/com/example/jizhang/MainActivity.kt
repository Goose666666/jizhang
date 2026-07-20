package com.example.jizhang

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 通过系统文件选择器(Storage Access Framework)选一个账单文件,
 * 读出字节返回给 Flutter。避免第三方 file_picker 插件的兼容问题。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "jizhang/filepick"
    private var pendingResult: MethodChannel.Result? = null
    private val reqCode = 4321

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "pick") {
                    pendingResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }
                    startActivityForResult(intent, reqCode)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != reqCode) return
        val result = pendingResult ?: return
        pendingResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null) // 用户取消
            return
        }
        try {
            val uri = data.data!!
            // 取文件名
            var name = "bill"
            contentResolver.query(uri, null, null, null, null)?.use { c ->
                val idx = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && c.moveToFirst()) name = c.getString(idx)
            }
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
            if (bytes == null) {
                result.error("READ_FAIL", "无法读取文件", null)
                return
            }
            result.success(mapOf("name" to name, "bytes" to bytes))
        } catch (e: Exception) {
            result.error("READ_FAIL", e.message, null)
        }
    }
}
