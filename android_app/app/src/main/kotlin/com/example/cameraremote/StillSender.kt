package com.example.cameraremote

import android.content.ContentUris
import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.provider.MediaStore
import android.util.Base64
import android.util.Log
import androidx.core.content.ContextCompat
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Sends one gallery photo to a watch app as a small gray image in row-aligned
 * chunks. Used by the CamRemote widget right after its shutter (the photo the
 * camera app just saved) and by the CamBench test app (the newest photo).
 *
 * If no photo can be sent, the watch gets {"t":"p","id":k,"err":"perm"|"none"}
 * so it can say why instead of waiting for its timeout.
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
        private const val CHUNK_RAW_BYTES = 900    // 1200 base64 chars; 1.4 KB arrived, 2.1 KB failed
        // Safety net only: Garmin Connect sometimes never calls back. A short timeout
        // re-sent chunks that were still in flight (each takes ~2 s) and doubled the
        // traffic, so wait long and never re-send (2026-11-13).
        private const val CHUNK_TIMEOUT_MS = 15000L
        private const val PHOTO_WAIT_MS = 8000L     // camera app saving the shot
        private const val PHOTO_POLL_MS = 300L
    }

    private val worker = HandlerThread("still-encode").apply { start() }
    private val bg = Handler(worker.looper)
    private val main = Handler(Looper.getMainLooper())
    // Read by the polling worker thread; a newer request must stop an older poll.
    @Volatile private var activeId = -1
    private var sendToken = 0

    /** CamBench: the newest photo in the gallery, whenever it was taken. */
    fun onRequest(id: Int) = start(id, sinceEpochSec = null)

    /**
     * CamRemote: wait for the photo the camera app saves after the shutter.
     * Only photos added in or after the shutter's second qualify (DATE_ADDED is
     * whole seconds, same phone clock), so photos taken earlier are never sent.
     */
    fun onShutter(id: Int, shutterAtEpochMs: Long) = start(id, shutterAtEpochMs / 1000)

    private fun start(id: Int, sinceEpochSec: Long?) {
        activeId = id
        val requestedAt = SystemClock.elapsedRealtime()
        if (!hasPhotoPermission()) {
            sendError(id, "perm")
            return
        }
        bg.post {
            val frame = try {
                val uri = if (sinceEpochSec == null) newestImageUri(null) else waitForNewPhoto(id, sinceEpochSec)
                uri?.let { decode(it) }?.let { StillEncoder.encode(it, PIXEL_BUDGET, CHUNK_RAW_BYTES) }
            } catch (e: Exception) {
                Log.e(TAG, "Encode failed", e)
                null
            }
            main.post {
                if (id != activeId) return@post
                if (frame == null) {
                    sendError(id, "none")
                    return@post
                }
                val prepMs = (SystemClock.elapsedRealtime() - requestedAt).toInt()
                Log.i(TAG, "still $id ${frame.width}x${frame.height} ${frame.chunks.sumOf { it.bytes.size }}B " +
                    "${frame.chunks.size} chunks prep ${prepMs}ms")
                sendChunk(id, frame, 0, requestedAt)
            }
        }
    }

    private fun sendChunk(id: Int, frame: StillEncoder.Frame, index: Int, requestedAt: Long) {
        if (id != activeId) return
        val total = frame.chunks.size
        if (index >= total) {
            val ms = SystemClock.elapsedRealtime() - requestedAt
            onStatus("Still $id sent in ${ms}ms ($total chunks)")
            return
        }
        val c = ciq() ?: return
        val d = device() ?: return
        val chunk = frame.chunks[index]
        val payload = mapOf(
            "t" to "s",
            "id" to id,
            "i" to index,
            "n" to total,
            "w" to frame.width,
            "h" to frame.height,
            "r0" to chunk.row0,
            "rows" to chunk.rows,
            "px" to Base64.encodeToString(chunk.bytes, Base64.NO_WRAP),
        )
        val token = ++sendToken
        val sentAt = SystemClock.elapsedRealtime()
        // Exactly one of callback / timeout advances the chain for this token.
        fun advance(outcome: String) {
            if (token != sendToken) return
            sendToken++
            val now = SystemClock.elapsedRealtime()
            Log.i(TAG, "still $id chunk ${index + 1}/$total ${chunk.bytes.size}B $outcome " +
                "${now - sentAt}ms (t=${now - requestedAt}ms)")
            sendChunk(id, frame, index + 1, requestedAt)
        }
        main.postDelayed({ advance("timeout") }, CHUNK_TIMEOUT_MS)
        try {
            c.sendMessage(d, app, payload) { _, _, status ->
                main.post { advance(status.toString()) }
            }
        } catch (e: Exception) {
            Log.e(TAG, "still $id chunk $index send failed", e)
            main.post { advance("exception") }
        }
    }

    private fun hasPhotoPermission(): Boolean {
        val perm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        return ContextCompat.checkSelfPermission(context, perm) == PackageManager.PERMISSION_GRANTED
    }

    private fun sendError(id: Int, err: String) {
        Log.w(TAG, "still $id not sent: $err")
        onStatus(if (err == "perm") "Photo access off" else "No new photo")
        val c = ciq() ?: return
        val d = device() ?: return
        try {
            c.sendMessage(d, app, mapOf("t" to "p", "id" to id, "err" to err)) { _, _, _ -> }
        } catch (e: Exception) {
            Log.e(TAG, "still $id error message failed", e)
        }
    }

    /** Polls until the camera app has finished saving a photo newer than [sinceEpochSec]. */
    private fun waitForNewPhoto(id: Int, sinceEpochSec: Long): Uri? {
        val deadline = SystemClock.elapsedRealtime() + PHOTO_WAIT_MS
        while (SystemClock.elapsedRealtime() < deadline && id == activeId) {
            newestImageUri(sinceEpochSec)?.let { return it }
            SystemClock.sleep(PHOTO_POLL_MS)
        }
        return null
    }

    private fun decode(uri: Uri): Bitmap? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        val source = ImageDecoder.createSource(context.contentResolver, uri)
        // Decode near 4x the target so the final downscale still averages pixels.
        return ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            val longest = max(info.size.width, info.size.height)
            val target = (sqrt(PIXEL_BUDGET.toDouble()) * 1.4 * 4).roundToInt()
            decoder.setTargetSampleSize(max(1, longest / target))
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
    }

    private fun newestImageUri(sinceEpochSec: Long?): Uri? {
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val where = ArrayList<String>()
        val args = ArrayList<String>()
        if (sinceEpochSec != null) {
            where.add("${MediaStore.Images.Media.DATE_ADDED} >= ?")
            args.add(sinceEpochSec.toString())
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            where.add("${MediaStore.MediaColumns.IS_PENDING} = 0") // still being written
        }
        context.contentResolver.query(
            collection,
            arrayOf(MediaStore.Images.Media._ID),
            where.joinToString(" AND ").ifEmpty { null },
            args.toTypedArray().ifEmpty { null },
            "${MediaStore.Images.Media.DATE_ADDED} DESC",
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return ContentUris.withAppendedId(collection, cursor.getLong(0))
            }
        }
        return null
    }
}

/**
 * Grayscale, contrast stretch, aspect-preserving resize, 16 gray levels, then
 * run-length coding per row: one byte = (level << 4) | (run - 1), runs of 1..16.
 * No dithering: its dot pattern makes runs short and RLE output larger than raw.
 * Rows are packed into chunks of at most [chunkBytes]; a run never crosses a row.
 */
object StillEncoder {
    class Chunk(val row0: Int, val rows: Int, val bytes: ByteArray)
    class Frame(val width: Int, val height: Int, val chunks: List<Chunk>)

    fun encode(src: Bitmap, pixelBudget: Int, chunkBytes: Int): Frame {
        val aspect = src.width.toDouble() / src.height
        val w = max(2, sqrt(pixelBudget * aspect).roundToInt())
        val h = max(1, (w / aspect).roundToInt())
        val small = Bitmap.createScaledBitmap(src, w, h, true)
        val px = IntArray(w * h)
        small.getPixels(px, 0, w, 0, 0, w, h)

        val gray = FloatArray(w * h) { i ->
            val c = px[i]
            0.299f * ((c shr 16) and 0xFF) + 0.587f * ((c shr 8) and 0xFF) + 0.114f * (c and 0xFF)
        }
        stretch(gray)
        val level = IntArray(w * h) { (gray[it].coerceIn(0f, 255f) / 255f * 15f).roundToInt() }

        val chunks = ArrayList<Chunk>()
        val buf = java.io.ByteArrayOutputStream()
        var chunkRow0 = 0
        for (y in 0 until h) {
            val row = encodeRow(level, y * w, w)
            if (buf.size() > 0 && buf.size() + row.size > chunkBytes) {
                chunks.add(Chunk(chunkRow0, y - chunkRow0, buf.toByteArray()))
                buf.reset()
                chunkRow0 = y
            }
            buf.write(row)
        }
        chunks.add(Chunk(chunkRow0, h - chunkRow0, buf.toByteArray()))
        return Frame(w, h, chunks)
    }

    private fun encodeRow(level: IntArray, off: Int, w: Int): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        var x = 0
        while (x < w) {
            val lv = level[off + x]
            var run = 1
            while (x + run < w && run < 16 && level[off + x + run] == lv) run++
            out.write((lv shl 4) or (run - 1))
            x += run
        }
        return out.toByteArray()
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
