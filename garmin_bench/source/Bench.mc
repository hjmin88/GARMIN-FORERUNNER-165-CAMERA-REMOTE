import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Stage-0 benchmark: how many grayscale frames per second survive the
// phone -> Garmin Connect -> BLE -> watch path, and what that costs the watch.
//
// Protocol (stop-and-wait, one frame in flight):
//   watch -> phone  {"cmd":"ack","seq":n,"w":W,"h":H,"bpp":B}   request frame n+1 at W x H, B bits/pixel
//   phone -> watch  {"t":"f","seq":n+1,"w":W,"h":H,"bpp":B,"rtt":ms,"px":base64}
//   watch -> phone  {"cmd":"stop"}
// "rtt" is the phone's send->ack time for the previous frame: transfer both ways
// plus decode/draw on the watch. One-way latency is lower than this.

enum BenchState {
    BENCH_IDLE,
    BENCH_RUNNING,
    BENCH_DONE
}

const PHASE_MS = 20000;          // time per configuration
const TICK_MS = 50;              // Connect IQ timer floor
const STALL_MS = 3000;           // re-send ack when no frame arrives this long
const NO_PHONE_MS = 5000;        // no frame at all in a phase -> show "phone not answering"
const PIXEL_BUDGET = 2000;       // pixels decoded per tick, to stay under the watchdog
const UI_REFRESH_MS = 500;       // status/live-stat redraw interval between frames

class Bench {
    // [width, height, bitsPerPixel]
    static const CONFIGS = [[64, 64, 2], [80, 80, 2], [80, 80, 4], [100, 100, 4]];

    var state as BenchState = BENCH_IDLE;
    var phase as Number = 0;
    var results as Array<Dictionary> = [];
    var lastResults as Array or Null = null;
    var status as String = "";

    // live counters for the current phase
    var frames as Number = 0;
    var rttSum as Number = 0;
    var rttCount as Number = 0;
    var rttMax as Number = 0;
    var drawSum as Number = 0;
    var drawMax as Number = 0;
    var memPeak as Number = 0;
    var memTotal as Number = 0;
    var txErrors as Number = 0;
    var stalls as Number = 0;
    var bytesIn as Number = 0;
    var phaseStart as Number = 0;

    var bitmap as Graphics.BufferedBitmapReference or Null = null;
    private var _palette as Array<Graphics.ColorType> = [] as Array<Graphics.ColorType>;

    private var _view as BenchView;
    private var _timer as Timer.Timer or Null = null;
    private var _lastSeq as Number = 0;
    private var _lastAckAt as Number = 0;
    private var _lastFrameAt as Number = 0;
    private var _lastUiAt as Number = 0;

    // frame being decoded across ticks
    private var _pending as ByteArray or Null = null;
    private var _pendingSeq as Number = 0;
    private var _pendingRow as Number = 0;
    private var _pendingStart as Number = 0;

    function initialize(view as BenchView) {
        _view = view;
        lastResults = Application.Storage.getValue("last") as Array or Null;
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
    }

    function config() as Array<Number> {
        return CONFIGS[phase] as Array<Number>;
    }

    function startIfIdle() as Void {
        if (state == BENCH_RUNNING) {
            return;
        }
        results = [];
        phase = 0;
        _lastSeq = 0;
        state = BENCH_RUNNING;
        _startPhase();
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), TICK_MS, true);
    }

    function stop() as Void {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
        if (state == BENCH_RUNNING) {
            state = BENCH_IDLE;
            _send({ "cmd" => "stop" });
        }
    }

    private function _startPhase() as Void {
        var c = config();
        frames = 0;
        rttSum = 0;
        rttCount = 0;
        rttMax = 0;
        drawSum = 0;
        drawMax = 0;
        memPeak = 0;
        txErrors = 0;
        stalls = 0;
        bytesIn = 0;
        _pending = null;
        status = "";
        phaseStart = System.getTimer();
        _lastFrameAt = 0;

        var levels = 1 << c[2];
        var palette = [] as Array<Graphics.ColorType>;
        for (var i = 0; i < levels; i++) {
            var g = (i * 255) / (levels - 1);
            palette.add((g << 16) | (g << 8) | g);
        }
        _palette = palette;
        bitmap = null; // release the previous phase's buffer first
        bitmap = Graphics.createBufferedBitmap({
            :width => c[0],
            :height => c[1],
            :palette => palette
        });
        _sendAck(_lastSeq);
    }

    private function _finishPhase(now as Number) as Void {
        var c = config();
        var elapsed = now - phaseStart;
        results.add({
            "cfg" => c[0].toString() + "x" + c[1] + "/" + c[2] + "b",
            "fps10" => elapsed > 0 ? (frames * 10000) / elapsed : 0,
            "rtt" => rttCount > 0 ? rttSum / rttCount : -1,
            "rttMax" => rttMax,
            "draw" => frames > 0 ? drawSum / frames : -1,
            "drawMax" => drawMax,
            "memKB" => memPeak / 1024,
            "memTotKB" => memTotal / 1024,
            "err" => txErrors,
            "stall" => stalls,
            "kb" => bytesIn / 1024
        });

        if (phase + 1 < CONFIGS.size()) {
            phase += 1;
            _startPhase();
            return;
        }

        state = BENCH_DONE;
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
        bitmap = null;
        _send({ "cmd" => "stop" });
        Application.Storage.setValue("last", results);
        lastResults = results;
        WatchUi.requestUpdate();
    }

    function onTick() as Void {
        if (state != BENCH_RUNNING) {
            return;
        }
        var now = System.getTimer();

        if (_pending != null) {
            _decodeChunk();
        }

        if (now - phaseStart >= PHASE_MS && _pending == null) {
            _finishPhase(now);
            return;
        }

        if (_pending == null && now - _lastAckAt > STALL_MS) {
            stalls += 1;
            _sendAck(_lastSeq);
        }

        if (frames == 0 && now - phaseStart > NO_PHONE_MS) {
            status = txErrors > 0 ? "Send error x" + txErrors : "Phone app not answering";
        } else if (_lastFrameAt > 0 && now - _lastFrameAt > STALL_MS) {
            status = "Waiting...";
        } else {
            status = "";
        }
        // Frames trigger their own redraw. Redrawing here every tick would spend
        // watch CPU the real preview never spends and skew fps/draw numbers.
        if (now - _lastUiAt >= UI_REFRESH_MS) {
            _lastUiAt = now;
            WatchUi.requestUpdate();
        }
    }

    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        if (state != BENCH_RUNNING) {
            return;
        }
        var data = msg.data;
        if (!(data instanceof Dictionary)) {
            return;
        }
        var d = data as Dictionary;
        if (!"f".equals(d.get("t"))) {
            return;
        }
        var seq = d.get("seq") as Number;
        if (seq <= _lastSeq || _pending != null) {
            return; // duplicate after a re-sent ack, or one already in progress
        }
        var c = config();
        if (d.get("w") != c[0] || d.get("h") != c[1] || d.get("bpp") != c[2]) {
            // frame for the previous phase; ask again with the current config
            _lastSeq = seq;
            _sendAck(seq);
            return;
        }

        // "rtt" describes the previous frame. For the first frame of a phase that
        // frame had the previous phase's size, so it does not belong here.
        var rtt = d.get("rtt");
        if (frames > 0 && rtt instanceof Number && rtt > 0) {
            rttSum += rtt;
            rttCount += 1;
            if (rtt > rttMax) {
                rttMax = rtt;
            }
        }

        var px = d.get("px") as String;
        bytesIn += px.length();
        _pending = StringUtil.convertEncodedString(px, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        }) as ByteArray;
        _pendingSeq = seq;
        _pendingRow = 0;
        _pendingStart = System.getTimer();
        _decodeChunk();
    }

    // Unpacks rows (MSB first) and paints runs of equal gray into the bitmap.
    private function _decodeChunk() as Void {
        var bytes = _pending;
        var ref = bitmap;
        if (bytes == null || ref == null) {
            _pending = null;
            return;
        }
        var c = config();
        var w = c[0];
        var h = c[1];
        var bpp = c[2];
        var mask = (1 << bpp) - 1;
        var perByte = 8 / bpp;
        var rowBytes = (w * bpp) / 8;
        var bmp = ref.get() as Graphics.BufferedBitmap;
        var dc = bmp.getDc();
        var palette = _palette;

        var budget = PIXEL_BUDGET;
        while (_pendingRow < h && budget > 0) {
            var y = _pendingRow;
            var off = y * rowBytes;
            var x = 0;
            var runStart = 0;
            var runLevel = -1;
            for (var i = 0; i < rowBytes; i++) {
                var b = bytes[off + i];
                for (var k = 1; k <= perByte; k++) {
                    var lv = (b >> (8 - bpp * k)) & mask;
                    if (lv != runLevel) {
                        if (runLevel >= 0) {
                            dc.setColor(palette[runLevel], palette[runLevel]);
                            dc.fillRectangle(runStart, y, x - runStart, 1);
                        }
                        runLevel = lv;
                        runStart = x;
                    }
                    x += 1;
                }
            }
            dc.setColor(palette[runLevel], palette[runLevel]);
            dc.fillRectangle(runStart, y, x - runStart, 1);
            _pendingRow += 1;
            budget -= w;
        }

        if (_pendingRow < h) {
            return; // continue on the next tick
        }

        var now = System.getTimer();
        var drawMs = now - _pendingStart;
        drawSum += drawMs;
        if (drawMs > drawMax) {
            drawMax = drawMs;
        }
        frames += 1;
        _lastFrameAt = now;
        _lastSeq = _pendingSeq;
        _pending = null;

        var stats = System.getSystemStats();
        memTotal = stats.totalMemory;
        if (stats.usedMemory > memPeak) {
            memPeak = stats.usedMemory;
        }
        _sendAck(_lastSeq);
        WatchUi.requestUpdate();
    }

    private function _sendAck(seq as Number) as Void {
        var c = config();
        _lastAckAt = System.getTimer();
        _send({ "cmd" => "ack", "seq" => seq, "w" => c[0], "h" => c[1], "bpp" => c[2] });
    }

    private function _send(payload as Dictionary) as Void {
        Communications.transmit(payload, null, new BenchListener(self));
    }

    function onTransmitError() as Void {
        txErrors += 1;
    }

    function liveFps10() as Number {
        var elapsed = System.getTimer() - phaseStart;
        return elapsed > 0 ? (frames * 10000) / elapsed : 0;
    }
}

class BenchListener extends Communications.ConnectionListener {
    private var _bench as Bench;

    function initialize(bench as Bench) {
        ConnectionListener.initialize();
        _bench = bench;
    }

    function onComplete() as Void {
    }

    function onError() as Void {
        _bench.onTransmitError();
    }
}
