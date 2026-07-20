package com.example.jizhang

import android.graphics.Bitmap
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * 智谱 GLM-4V-Flash 多模态识别客户端。
 * 输入一张支付截图,返回识别出的账单字段(识别失败返回 null)。
 *
 * 免费模型,国内直连:https://open.bigmodel.cn/api/paas/v4/chat/completions
 * API Key 在 https://bigmodel.cn 注册后创建,填到 app 设置页即可。
 */
object GlmClient {
    private const val TAG = "JZSCAN"
    private const val ENDPOINT = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    private const val MODEL = "glm-4v-flash"

    private const val PROMPT = """你是账单识别助手。请判断这张手机截图是否是一笔"已完成的支付/转账/收款"结果页。
只返回一个 JSON 对象,不要任何解释、不要 markdown 代码块:
{"isBill": true 或 false, "money": 数字, "type": "expense" 或 "income", "category": "分类", "merchant": "商户或对方名称", "account": "微信" 或 "支付宝"}

判定为账单(isBill=true)需同时满足:
1. 页面明确显示"支付成功/已支付/付款成功/转账成功/已到账/收款成功"等交易完成字样;
2. 能看到明确的交易金额(带¥或元的数字)。
如果是聊天页/首页/列表页/网页/余额页/账单列表/搜索页/其他非交易页,则 isBill=false, money=0。

isBill=true 时其余字段:
money 为正数不带负号;type: 付款/支出/转出=expense,收款/到账/收入=income;
category 只能选:餐饮、购物、交通、日用、娱乐、医疗、转账、工资、红包、理财、退款、其他;
account: 看这是哪个App的界面来判断——支付宝(蓝色主题/有"支付宝积分"等字样)填"支付宝",微信(绿色主题)填"微信";
注意 account 是指所在App(微信/支付宝),不是"付款方式"里的银行卡名。判断不出就填"微信"。"""

    data class Bill(
        val money: Double,
        val isExpense: Boolean,
        val category: String,
        val merchant: String,
        val account: String,
    )

    /** 同步调用(需在后台线程执行)。 */
    fun recognize(bitmap: Bitmap, apiKey: String): Bill? {
        return try {
            val base64 = encodeJpeg(bitmap)
            val body = buildRequest(base64)
            val content = post(body, apiKey) ?: return null
            parseBill(content)
        } catch (e: Exception) {
            Log.e(TAG, "GLM 识别失败: ${e.message}", e)
            null
        }
    }

    private fun encodeJpeg(src: Bitmap): String {
        // 缩放到最长边 1080,降低体积与耗时
        val maxSide = 1080
        val scale = minOf(1f, maxSide.toFloat() / maxOf(src.width, src.height))
        val bmp = if (scale < 1f) {
            Bitmap.createScaledBitmap(
                src, (src.width * scale).toInt(), (src.height * scale).toInt(), true
            )
        } else src
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, 85, out)
        return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
    }

    private fun buildRequest(base64Jpeg: String): String {
        val textPart = JSONObject().put("type", "text").put("text", PROMPT)
        val imagePart = JSONObject()
            .put("type", "image_url")
            .put("image_url", JSONObject().put("url", "data:image/jpeg;base64,$base64Jpeg"))
        val message = JSONObject()
            .put("role", "user")
            .put("content", JSONArray().put(textPart).put(imagePart))
        return JSONObject()
            .put("model", MODEL)
            .put("messages", JSONArray().put(message))
            .toString()
    }

    private fun post(body: String, apiKey: String): String? {
        val conn = URL(ENDPOINT).openConnection() as HttpURLConnection
        return try {
            conn.requestMethod = "POST"
            conn.connectTimeout = 15000
            conn.readTimeout = 30000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Authorization", "Bearer $apiKey")
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val resp = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
            Log.i(TAG, "GLM HTTP $code, resp前300字: ${resp.take(300)}")
            if (code !in 200..299) {
                Log.e(TAG, "GLM HTTP $code: $resp")
                return null
            }
            // choices[0].message.content
            JSONObject(resp)
                .getJSONArray("choices")
                .getJSONObject(0)
                .getJSONObject("message")
                .getString("content")
        } finally {
            conn.disconnect()
        }
    }

    private fun parseBill(content: String): Bill? {
        // 模型可能带 ```json 包裹,抠出第一个 { ... }
        val start = content.indexOf('{')
        val end = content.lastIndexOf('}')
        if (start < 0 || end <= start) {
            Log.e(TAG, "GLM 返回非JSON: $content")
            return null
        }
        val json = JSONObject(content.substring(start, end + 1))
        // 严格校验:必须是模型确认的账单页
        if (!json.optBoolean("isBill", false)) {
            Log.i(TAG, "非账单页,已忽略")
            return null
        }
        // GLM 可能给支出金额带负号,统一取绝对值;收支由 type 字段决定
        val money = kotlin.math.abs(json.optDouble("money", 0.0))
        if (money <= 0) {
            Log.i(TAG, "GLM 未识别到有效金额")
            return null
        }
        // 账户归一化:含"支付宝"→支付宝,否则默认微信(不因账户判断而丢弃账单)
        val accRaw = json.optString("account", "")
        val account = if (accRaw.contains("支付宝") || accRaw.contains("花呗") ||
            accRaw.contains("余额宝")) "支付宝" else "微信"
        return Bill(
            money = money,
            isExpense = json.optString("type", "expense") != "income",
            category = json.optString("category", "其他"),
            merchant = json.optString("merchant", ""),
            account = account,
        )
    }
}
