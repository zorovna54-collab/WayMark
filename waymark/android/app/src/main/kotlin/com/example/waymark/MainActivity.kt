package com.example.waymark

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import android.util.AtomicFile
import java.io.File
import java.security.MessageDigest
import com.example.waymark.sensors.AndroidSensorBridge

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var saveBytes: ByteArray? = null
    private var limit = 0
    private val openRequest = 9721
    private val saveRequest = 9722
    private var sensorBridge: AndroidSensorBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sensorBridge?.dispose()
        sensorBridge = AndroidSensorBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "waymark/ai_preferences")
            .setMethodCallHandler { call, result ->
                val scope = call.argument<String>("scope")
                if (scope !in setOf("openai-compatible-graph-v2", "openai-compatible-nodes-v1")) {
                    result.error("AI_SETTINGS", "Không xác định được cấu hình AI.", null)
                    return@setMethodCallHandler
                }
                val preferences = getSharedPreferences("waymark_ai_timeout", MODE_PRIVATE)
                when (call.method) {
                    "readTimeout" -> result.success(if (preferences.contains(scope)) preferences.getInt(scope, 0) else null)
                    "writeTimeout" -> {
                        val seconds = call.argument<Int>("seconds")
                        if (seconds == null || seconds !in 10..600) {
                            result.error("AI_SETTINGS", "Thời gian chờ cần 10–600 giây.", null)
                        } else {
                            // Persist only the bounded integer; no credentials or URLs.
                            worker.execute {
                                val saved = preferences.edit().putInt(scope, seconds).commit()
                                runOnUiThread { result.success(saved) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "waymark/draft_files")
            .setMethodCallHandler { call, result ->
                if (call.method == "recoveryRead" || call.method == "recoveryWrite") {
                    val owner = call.argument<String>("owner") ?: ""
                    val project = call.argument<String>("project") ?: ""
                    if (owner.isBlank() || owner.length > 1000 || !project.matches(Regex("[a-fA-F0-9-]{36}"))) {
                        result.error("RECOVERY", "Không xác định được bản đồ khôi phục.", null)
                        return@setMethodCallHandler
                    }
                    val bytes = call.argument<ByteArray>("bytes")
                    worker.execute {
                        try {
                            val scope = MessageDigest.getInstance("SHA-256").digest(owner.toByteArray()).joinToString("") { "%02x".format(it) }
                            val directory = File(noBackupFilesDir, "map-recovery/$scope")
                            val file = AtomicFile(File(directory, "${project.lowercase()}.json"))
                            if (call.method == "recoveryWrite") {
                                require(bytes != null && bytes.isNotEmpty() && bytes.size <= 64 * 1024 * 1024)
                                require(directory.isDirectory || directory.mkdirs())
                                val stream = file.startWrite()
                                try { stream.write(bytes); file.finishWrite(stream) }
                                catch (error: Exception) { file.failWrite(stream); throw error }
                                runOnUiThread { result.success(null) }
                            } else {
                                val restored = if (file.baseFile.exists() || File(file.baseFile.path + ".bak").exists()) file.openRead().use {
                                    require(it.available() <= 64 * 1024 * 1024)
                                    it.readBytes()
                                } else null
                                runOnUiThread { result.success(restored) }
                            }
                        } catch (error: Exception) {
                            runOnUiThread { result.error("RECOVERY", "Không đọc/ghi được bản khôi phục trên thiết bị. Hãy xuất JSON.", null) }
                        }
                    }
                    return@setMethodCallHandler
                }
                if (call.method != "pick" && call.method != "save") {
                    result.notImplemented(); return@setMethodCallHandler
                }
                if (pending != null) {
                    result.error("BUSY", "Một hộp thoại file đang mở.", null); return@setMethodCallHandler
                }
                try {
                    val saving = call.method == "save"
                    if (saving) {
                        saveBytes = call.argument<ByteArray>("bytes")
                        require(saveBytes != null && saveBytes!!.size <= 64 * 1024 * 1024)
                    } else {
                        limit = call.argument<Int>("maxBytes") ?: 0
                        require(limit in 1..(64 * 1024 * 1024))
                    }
                    val image = call.argument<Boolean>("image") == true
                    val saveMime = call.argument<String>("mime") ?: "application/json"
                    if (saving) require(saveMime in setOf("application/json", "image/png", "image/jpeg"))
                    val intent = Intent(if (saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = if (saving) saveMime else if (image) "image/*" else "*/*"
                        if (!saving && image) putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/png", "image/jpeg"))
                        if (saving) putExtra(Intent.EXTRA_TITLE, (call.argument<String>("name") ?: "waymark-draft.json").substringAfterLast('/').substringAfterLast('\\'))
                    }
                    pending = result
                    startActivityForResult(intent, if (saving) saveRequest else openRequest)
                } catch (e: Exception) {
                    pending = null; saveBytes = null
                    result.error("PICKER", "Không thể mở trình chọn file trên thiết bị.", null)
                }
            }
    }

    @Deprecated("Android document picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != openRequest && requestCode != saveRequest) return
        val reply = pending ?: return
        val bytes = saveBytes
        val max = limit
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null; saveBytes = null
            reply.success(if (requestCode == saveRequest) false else null)
            return
        }
        worker.execute {
            try {
                if (requestCode == saveRequest) {
                    contentResolver.openOutputStream(uri, "w")?.use { it.write(bytes ?: error("No bytes")) }
                        ?: error("No output stream")
                    runOnUiThread { if (pending === reply) { pending = null; saveBytes = null; reply.success(true) } }
                } else {
                    var name = "selected-file"
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            name = cursor.getString(0) ?: name
                            if (!cursor.isNull(1)) require(cursor.getLong(1) <= max) { "File vượt giới hạn dung lượng." }
                        }
                    }
                    val output = ByteArrayOutputStream()
                    contentResolver.openInputStream(uri)?.use { input ->
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            require(output.size() + count <= max) { "File vượt giới hạn dung lượng." }
                            output.write(buffer, 0, count)
                        }
                    } ?: error("No input stream")
                    val response = mapOf("bytes" to output.toByteArray(), "name" to name,
                        "mime" to (contentResolver.getType(uri) ?: ""))
                    runOnUiThread { if (pending === reply) { pending = null; reply.success(response) } }
                }
            } catch (e: Exception) {
                runOnUiThread {
                    if (pending === reply) {
                        pending = null; saveBytes = null
                        reply.error("FILE", "Không đọc/ghi được file hoặc file vượt giới hạn. Bản nháp đang giữ nguyên.", null)
                    }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        sensorBridge?.onResume()
    }

    override fun onPause() {
        sensorBridge?.onPause()
        super.onPause()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        sensorBridge?.onRequestPermissionsResult(requestCode)
    }

    override fun onDestroy() {
        sensorBridge?.dispose()
        sensorBridge = null
        pending?.error("CLOSED", "Màn hình chọn file đã đóng; hãy mở lại bản nháp đã lưu.", null)
        pending = null; saveBytes = null
        worker.shutdown()
        super.onDestroy()
    }
}
