package com.example.cameraremote

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Base64
import android.util.Log
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Stage-0 benchmark sender. Answers the CamBench watch app with synthetic
 * grayscale frames, one in flight at a time (stop-and-wait).
 *
 * The watch drives everything: each "ack" names the frame size it wants next.
 * If no ack arrives for [WATCHDOG_MS], sending stops on its own so a crashed or
 * closed watch app cannot keep the phone transmitting.
 */
class BenchSender(
    private val ciq: () -> ConnectIQ?,
    private val device: () -> IQDevice?,
    private val onStatus: (String) -> Unit,
) {
    companion object {
        private const val TAG = "BenchSender"
        const val BENCH_APP_ID = "8f4b84a4-c51f-4258-800f-4e711eeb8108"
        private const val WATCHDOG_MS = 5000L
        private const val STATUS_EVERY_MS = 2000L
    }

    val app = IQApp(BENCH_APP_ID)

    private val main = Handler(Looper.getMainLooper())
    private var active = false
    private var lastSentSeq = 0
    private var lastSentAt = 0L
    private var lastRtt = 0
    private var rttMeasuredFor = 0
    private var lastActivityAt = 0L
    private var sent = 0
    private var sendFailures = 0
    private var lastStatusAt = 0L

    private val watchdog = object : Runnable {
        override fun run() {
            if (!active) return
            if (SystemClock.elapsedRealtime() - lastActivityAt > WATCHDOG_MS) {
                Log.w(TAG, "No ack for ${WATCHDOG_MS}ms, stopping")
                stop("Bench stopped: watch silent")
                return
            }
            main.postDelayed(this, 1000)
        }
    }

    /** Messages from the bench app. Called on whatever thread the SDK uses. */
    fun onMessage(messageData: List<Any>?) {
        val msg = messageData?.firstOrNull() as? Map<*, *> ?: return
        main.post { handle(msg) }
    }

    private fun handle(msg: Map<*, *>) {
        when (msg["cmd"] as? String) {
            "ack" -> {
                val seq = (msg["seq"] as? Number)?.toInt() ?: return
                val w = (msg["w"] as? Number)?.toInt() ?: return
                val h = (msg["h"] as? Number)?.toInt() ?: return
                val bpp = (msg["bpp"] as? Number)?.toInt() ?: return
                if (bpp !in setOf(1, 2, 4, 8) || (w * bpp) % 8 != 0 || w > 200 || h > 200) {
                    Log.w(TAG, "Unsupported config ${w}x$h/$bpp")
                    return
                }
                val now = SystemClock.elapsedRealtime()
                // Only the first ack for the frame we just sent is a real round trip.
                // Re-sent acks (watch stall recovery, phase change) are not.
                if (seq == lastSentSeq && seq != rttMeasuredFor && lastSentSeq > 0) {
                    lastRtt = (now - lastSentAt).toInt()
                    rttMeasuredFor = seq
                }
                if (!active) {
                    active = true
                    sent = 0
                    sendFailures = 0
                    main.postDelayed(watchdog, 1000)
                }
                lastActivityAt = now
                sendFrame(seq + 1, w, h, bpp)
            }
            "stop" -> stop("Bench finished")
        }
    }

    fun stop(reason: String) {
        if (!active) return
        active = false
        main.removeCallbacks(watchdog)
        onStatus("$reason (sent $sent, failed $sendFailures, last rtt ${lastRtt}ms)")
    }

    private fun sendFrame(seq: Int, w: Int, h: Int, bpp: Int) {
        val c = ciq() ?: return
        val d = device() ?: return
        val payload = mapOf(
            "t" to "f",
            "seq" to seq,
            "w" to w,
            "h" to h,
            "bpp" to bpp,
            "rtt" to lastRtt,
            "px" to Base64.encodeToString(FramePattern.render(w, h, bpp, seq), Base64.NO_WRAP),
        )
        lastSentSeq = seq
        lastSentAt = SystemClock.elapsedRealtime()
        try {
            c.sendMessage(d, app, payload) { _, _, status ->
                if (status != ConnectIQ.IQMessageStatus.SUCCESS) {
                    sendFailures++
                    Log.w(TAG, "Frame $seq send status: $status")
                }
            }
            sent++
        } catch (e: Exception) {
            sendFailures++
            Log.e(TAG, "Frame $seq send failed", e)
        }

        val now = SystemClock.elapsedRealtime()
        if (now - lastStatusAt > STATUS_EVERY_MS) {
            lastStatusAt = now
            onStatus("Bench ${w}x$h/${bpp}b: frame $seq, rtt ${lastRtt}ms")
        }
    }
}

/**
 * Synthetic frame that looks roughly like a camera image (smooth gradient,
 * a moving bright blob, some texture) so run-length drawing on the watch costs
 * about what a real frame would. Packed row-major, MSB first.
 */
object FramePattern {
    fun render(w: Int, h: Int, bpp: Int, t: Int): ByteArray {
        val levels = (1 shl bpp) - 1
        val out = ByteArray(w * h * bpp / 8)
        val bx = w * (0.5 + 0.35 * sin(t * 0.3))
        val by = h * (0.5 + 0.35 * sin(t * 0.17 + 1.0))
        val r = w * 0.18
        var bit = 0
        for (y in 0 until h) {
            for (x in 0 until w) {
                val grad = (x + y).toDouble() / (w + h)
                val dx = x - bx
                val dy = y - by
                val blob = if (sqrt(dx * dx + dy * dy) < r) 0.8 else 0.0
                val texture = if (((x / 6) + (y / 6) + t) % 5 == 0) 0.15 else 0.0
                val v = (0.25 * grad + blob + texture).coerceIn(0.0, 1.0)
                val level = (v * levels + 0.5).toInt()
                val shift = 8 - bpp - (bit % 8)
                out[bit / 8] = (out[bit / 8].toInt() or (level shl shift)).toByte()
                bit += bpp
            }
        }
        return out
    }
}
