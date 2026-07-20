package com.example.jizhang

import android.app.Activity
import android.os.Bundle
import android.widget.Toast
import org.json.JSONObject
import java.io.File

/**
 * 接收自动记账(AutoAccounting)通过 yimu://api/addbill 协议推送的账单。
 * 解析后追加到应用私有目录的 inbox.jsonl,由 Flutter 侧在启动/回前台时合并入账。
 */
class AddBillActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uri = intent?.data
        if (uri != null && uri.path?.contains("addbill") == true) {
            val money = uri.getQueryParameter("money")?.toDoubleOrNull()
            if (money != null && money > 0) {
                val json = JSONObject().apply {
                    put("money", money)
                    put("parentCategory", uri.getQueryParameter("parentCategory") ?: "")
                    put("childCategory", uri.getQueryParameter("childCategory") ?: "")
                    put("time", uri.getQueryParameter("time") ?: "")
                    put("remark", uri.getQueryParameter("remark") ?: "")
                    put("asset", uri.getQueryParameter("asset") ?: "")
                    put("tags", uri.getQueryParameter("tags") ?: "")
                    put("receivedAt", System.currentTimeMillis())
                }
                File(filesDir, "inbox.jsonl").appendText(json.toString() + "\n")
                Toast.makeText(this, "已自动记账 ¥$money", Toast.LENGTH_SHORT).show()
            }
        }
        finish()
    }
}
