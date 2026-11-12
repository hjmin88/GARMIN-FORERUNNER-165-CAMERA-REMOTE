package com.example.cameraremote

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.util.Base64
import android.util.Log
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Stage-1 still transfer test. On {"cmd":"still","id":k} from the CamBench
 * watch app, takes the newest photo in the gallery, encodes it the way the
 * post-shot preview will, and sends it in row-aligned chunks.
 *
 * Chunks go out one at a time, each after the previous one's send callback.
 * The watch never acks chunks: in stage 0 watch->phone messages were often
 * late or lost, while phone->watch delivery of ~1.4 KB messages worked.
 */
class StillSender(
    private val context: Context,
    private val ciq: () -> ConnectIQ?,
    private val device: () -> IQDevice?,
    private val app: IQApp,
    private val onStatus: (String) -> Unit,
) {
    companion object {
        private const val TAG = "StillSender"
        private const val PIXEL_BUDGET = 9216      // 96x96 class, chosen in stage 1 (1)
        private const val BPP = 4
        private const val CHUNK_RAW_BYTES = 900    // 1200 base64 chars; 1.4 KB arrived, 2.1 KB failed
        private const val MAX_RETRIES = 1
        // Garmin Connect sometimes never calls back for a message. Without this
        // the chain stalled after 2-3 chunks (2026-11-13).
        private const val CHUNK_TIMEOUT_MS = 3000L
    }

    private val worker = HandlerThread("still-encode").apply { start() }
    private val bg = Handler(worker.looper)
    private val main = Handler(Looper.getMainLooper())
    private var activeId = -1
    private var sendToken = 0

    fun onRequest(id: Int) {
        activeId = id
        val requestedAt = SystemClock.elapsedRealtime()
        bg.post {
            val frame = try {
                latestPhoto()?.let { StillEncoder.encode(it, PIXEL_BUDGET) }
            } catch (e: Exception) {
                Log.e(TAG, "Encode failed", e)
                null
            }
            main.post {
                if (id != activeId) return@post
                if (frame == null) {
                    onStatus("Still: no photo or no permission")
                    return@post
                }
                val prepMs = (SystemClock.elapsedRealtime() - requestedAt).toInt()
                Log.i(TAG, "still $id ${frame.width}x${frame.height} ${frame.packed.size}B prep ${prepMs}ms")
                sendChunk(id, frame, 0, 0, requestedAt)
            }
        }
    }

    private fun sendChunk(id: Int, frame: StillEncoder.Frame, index: Int, attempt: Int, requestedAt: Long) {
        if (id != activeId) return
        val rowBytes = frame.width * BPP / 8
        val rowsPerChunk = max(1, CHUNK_RAW_BYTES / rowBytes)
        val total = (frame.height + rowsPerChunk - 1) / rowsPerChunk
        if (index >= total) {
            val ms = SystemClock.elapsedRealtime() - requestedAt
            onStatus("Still $id sent in ${ms}ms ($total chunks)")
            return
        }
        val c = ciq() ?: return
        val d = device() ?: return
        val row0 = index * rowsPerChunk
        val rows = minOf(rowsPerChunk, frame.height - row0)
        val bytes = frame.packed.copyOfRange(row0 * rowBytes, (row0 + rows) * rowBytes)
        val payload = mapOf(
            "t" to "s",
            "id" to id,
            "i" to index,
            "n" to total,
            "w" to frame.width,
            "h" to frame.height,
            "r0" to row0,
            "rows" to rows,
            "px" to Base64.encodeToString(bytes, Base64.NO_WRAP),
        )
        val token = ++sendToken
        val sentAt = SystemClock.elapsedRealtime()
        // Exactly one of callback / timeout advances the chain for this token.
        fun advance(outcome: String, ok: Boolean) {
            if (token != sendToken) return
            sendToken++
            val now = SystemClock.elapsedRealtime()
            Log.i(TAG, "still $id chunk ${index + 1}/$total try ${attempt + 1} $outcome " +
                "${now - sentAt}ms (t=${now - requestedAt}ms)")
            when {
                ok -> sendChunk(id, frame, index + 1, 0, requestedAt)
                attempt < MAX_RETRIES -> sendChunk(id, frame, index, attempt + 1, requestedAt)
                else -> sendChunk(id, frame, index + 1, 0, requestedAt)
            }
        }
        main.postDelayed({ advance("timeout", false) }, CHUNK_TIMEOUT_MS)
        try {
            c.sendMessage(d, app, payload) { _, _, status ->
                main.post { advance(status.toString(), status == ConnectIQ.IQMessageStatus.SUCCESS) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "still $id chunk $index send failed", e)
            main.post { advance("exception", false) }
        }
    }

    private fun latestPhoto(): Bitmap? {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.P) return null
        val uri = newestImageUri() ?: return null
        val source = ImageDecoder.createSource(context.contentResolver, uri)
        // Decode near 4x the target so the final downscale still averages pixels.
        return ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            val longest = max(info.size.width, info.size.height)
            val target = (sqrt(PIXEL_BUDGET.toDouble()) * 1.4 * 4).roundToInt()
            decoder.setTargetSampleSize(max(1, longest / target))
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
    }

    private fun newestImageUri(): Uri? {
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        context.contentResolver.query(
            collection,
            arrayOf(MediaStore.Images.Media._ID),
            null, null,
            "${MediaStore.Images.Media.DATE_ADDED} DESC",
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return ContentUris.withAppendedId(collection, cursor.getLong(0))
            }
        }
        return null
    }
}

/** Grayscale, contrast stretch, aspect-preserving resize, 16 gray levels with dithering. */
object StillEncoder {
    class Frame(val width: Int, val height: Int, val packed: ByteArray)

    fun encode(src: Bitmap, pixelBudget: Int): Frame {
        val aspect = src.width.toDouble() / src.height
        var w = sqrt(pixelBudget * aspect).roundToInt()
        var h = (w / aspect).roundToInt()
        w -= w % 2 // two 4-bit pixels per byte
        h = max(1, h)
        val small = Bitmap.createScaledBitmap(src, w, h, true)
        val px = IntArray(w * h)
        small.getPixels(px, 0, w, 0, 0, w, h)

        val gray = FloatArray(w * h) { i ->
            val c = px[i]
            0.299f * ((c shr 16) and 0xFF) + 0.587f * ((c shr 8) and 0xFF) + 0.114f * (c and 0xFF)
        }
        stretch(gray)

        val levels = 15f
        val packed = ByteArray(w * h / 2)
        for (y in 0 until h) {
            for (x in 0 until w) {
                val i = y * w + x
                val old = gray[i].coerceIn(0f, 255f)
                val lv = (old / 255f * levels).roundToInt()
                val err = old - lv * 255f / levels
                if (x + 1 < w) gray[i + 1] += err * 7 / 16
                if (y + 1 < h) {
                    if (x > 0) gray[i + w - 1] += err * 3 / 16
                    gray[i + w] += err * 5 / 16
                    if (x + 1 < w) gray[i + w + 1] += err * 1 / 16
                }
                val b = i / 2
                packed[b] = if (i % 2 == 0) (lv shl 4).toByte() else (packed[b].toInt() or lv).toByte()
            }
        }
        return Frame(w, h, packed)
    }

    /** Stretch so the darkest and brightest 1% map to black and white. */
    private fun stretch(gray: FloatArray) {
        val hist = IntArray(256)
        for (g in gray) hist[g.toInt().coerceIn(0, 255)]++
        val cut = gray.size / 100
        var lo = 0
        var acc = 0
        while (lo < 255 && acc + hist[lo] <= cut) { acc += hist[lo]; lo++ }
        var hi = 255
        acc = 0
        while (hi > lo && acc + hist[hi] <= cut) { acc += hist[hi]; hi-- }
        if (hi <= lo) return
        val k = 255f / (hi - lo)
        for (i in gray.indices) gray[i] = (gray[i] - lo) * k
    }
}
