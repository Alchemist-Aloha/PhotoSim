package org.photosim.photosim

import android.content.ContentValues
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(
            messenger,
            "photosim/export",
            StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
            if (call.method != "savePng") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("bytes")
            val name = call.argument<String>("name")
            if (bytes == null || bytes.isEmpty() || bytes.size > 64 * 1024 * 1024 ||
                name == null || !name.matches(Regex("photosim-[0-9]+\\.png"))) {
                result.error("invalid_export", "A valid PNG and filename are required.", null)
                return@setMethodCallHandler
            }
            var pending: android.net.Uri? = null
            try {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/PhotoSim")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                    ?: error("Could not create an image in MediaStore")
                pending = uri
                val stream = contentResolver.openOutputStream(uri)
                    ?: error("Could not open the export destination")
                stream.use { it.write(bytes) }
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                check(contentResolver.update(uri, values, null, null) == 1)
                pending = null
                result.success(uri.toString())
            } catch (error: Exception) {
                pending?.let {
                    try { contentResolver.delete(it, null, null) } catch (_: Exception) { }
                }
                result.error("export_failed", "Could not save PNG. Check available storage and try again.", null)
            }
        }
    }
}
