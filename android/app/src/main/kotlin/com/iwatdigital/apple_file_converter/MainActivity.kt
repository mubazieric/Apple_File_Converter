package com.iwatdigital.apple_file_converter

import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.media.MediaCodecList
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Hosts the "com.iwatdigital.apple_file_converter/codec" MethodChannel.
 *
 * Only operations that genuinely need Android APIs live here: HEIC/HEIF decoding through
 * [ImageDecoder], writing finished files into MediaStore, probing image bounds, and asking the
 * platform whether a hardware video encoder exists. Everything else is shared Dart code so the
 * two platforms behave identically. Every handler is defensive: when the OS cannot do the work
 * we return `null`/`false` and the Dart layer reports an honest failure instead of faking success.
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "supportsHeic" -> result.success(supportsHeic())
                        "decodeToRgba" -> handleDecodeToRgba(call, result)
                        "probeImage" -> handleProbeImage(call, result)
                        "saveToPhotoLibrary" -> handleSaveToPhotoLibrary(call, result)
                        "hasHardwareEncoder" -> result.success(hasHardwareEncoder(call.argument("codec")))
                        "deviceStorage" -> result.success(deviceStorage())
                        else -> result.notImplemented()
                    }
                } catch (throwable: Throwable) {
                    result.error("native_error", throwable.message ?: "Native operation failed", null)
                }
            }
    }

    private fun supportsHeic(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P

    private fun handleDecodeToRgba(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val maxMegapixels = (call.argument<Any>("maxMegapixels") as? Number)?.toInt() ?: 80
        if (path == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result.success(null)
            return
        }
        val bitmap = decodeBitmap(path, maxMegapixels)
        if (bitmap == null) {
            result.success(null)
            return
        }
        val width = bitmap.width
        val height = bitmap.height
        val buffer = ByteBuffer.allocate(bitmap.byteCount)
        bitmap.copyPixelsToBuffer(buffer)
        bitmap.recycle()
        result.success(
            hashMapOf<String, Any>(
                "pixels" to buffer.array(),
                "width" to width,
                "height" to height,
                "orientation" to 0,
            ),
        )
    }

    private fun decodeBitmap(path: String, maxMegapixels: Int): Bitmap? {
        if (!File(path).exists()) {
            return null
        }
        return try {
            val source = ImageDecoder.createSource(File(path))
            ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val megapixels =
                    (info.size.width.toLong() * info.size.height.toLong()) / 1_000_000.0
                if (maxMegapixels > 0 && megapixels > maxMegapixels) {
                    val scale = sqrt(maxMegapixels / megapixels)
                    decoder.setTargetSize(
                        max(1, (info.size.width * scale).roundToInt()),
                        max(1, (info.size.height * scale).roundToInt()),
                    )
                }
            }
        } catch (throwable: Throwable) {
            null
        }
    }

    private fun handleProbeImage(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path == null || !File(path).exists()) {
            result.success(null)
            return
        }
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, options)
        if (options.outWidth <= 0 || options.outHeight <= 0) {
            result.success(null)
            return
        }
        val mime = options.outMimeType ?: ""
        result.success(
            hashMapOf<String, Any>(
                "width" to options.outWidth,
                "height" to options.outHeight,
                "format" to mimeToFormatId(mime),
                "hasAlpha" to mimeSupportsAlpha(mime),
                "orientation" to 0,
            ),
        )
    }

    private fun handleSaveToPhotoLibrary(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val isVideo = call.argument<Boolean>("isVideo") ?: false
        if (path == null) {
            result.success(null)
            return
        }
        val source = File(path)
        if (!source.exists()) {
            result.success(null)
            return
        }
        val resolver = applicationContext.contentResolver
        val collection =
            if (isVideo) {
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, source.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeForFile(source.name, isVideo))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES,
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }
        val uri = resolver.insert(collection, values)
        if (uri == null) {
            result.success(null)
            return
        }
        try {
            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            }
        } catch (throwable: Throwable) {
            resolver.delete(uri, null, null)
            result.success(null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val done = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
            resolver.update(uri, done, null, null)
        }
        result.success(uri.toString())
    }

    private fun hasHardwareEncoder(codecId: String?): Boolean {
        val mime = when (codecId) {
            "h264" -> "video/avc"
            "hevc" -> "video/hevc"
            "vp8" -> "video/x-vnd.on2.vp8"
            "vp9" -> "video/x-vnd.on2.vp9"
            "av1" -> "video/av01"
            else -> return false
        }
        for (info in MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos) {
            if (!info.isEncoder) {
                continue
            }
            if (!info.supportedTypes.any { it.equals(mime, ignoreCase = true) }) {
                continue
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !info.isHardwareAccelerated) {
                continue
            }
            return true
        }
        return false
    }

    private fun deviceStorage(): Map<String, Long> {
        val stat = StatFs(Environment.getDataDirectory().absolutePath)
        return mapOf(
            "totalBytes" to stat.totalBytes,
            "freeBytes" to stat.availableBytes,
        )
    }

    private fun mimeToFormatId(mime: String): String = when (mime.lowercase()) {
        "image/jpeg" -> "jpeg"
        "image/png" -> "png"
        "image/webp" -> "webp"
        "image/gif" -> "gif"
        "image/bmp", "image/x-ms-bmp" -> "bmp"
        "image/tiff" -> "tiff"
        "image/heic", "image/heif" -> "heic"
        "image/avif" -> "avif"
        else -> "unknown"
    }

    private fun mimeSupportsAlpha(mime: String): Boolean = when (mime.lowercase()) {
        "image/png", "image/webp", "image/gif", "image/tiff" -> true
        else -> false
    }

    private fun mimeForFile(name: String, isVideo: Boolean): String {
        val extension = name.substringAfterLast('.', "").lowercase()
        return when (extension) {
            "mp4", "m4v" -> "video/mp4"
            "mov" -> "video/quicktime"
            "mkv" -> "video/x-matroska"
            "webm" -> "video/webm"
            "avi" -> "video/x-msvideo"
            "3gp", "3g2" -> "video/3gpp"
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            "gif" -> "image/gif"
            "bmp" -> "image/bmp"
            "tif", "tiff" -> "image/tiff"
            "heic" -> "image/heic"
            "heif" -> "image/heif"
            else -> if (isVideo) "video/mp4" else "image/jpeg"
        }
    }

    private companion object {
        const val CHANNEL = "com.iwatdigital.apple_file_converter/codec"
    }
}
