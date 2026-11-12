import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.StringUtil;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Stage-1 still transfer test: how long does one post-shot photo take to reach
// the watch, chunked, and does it arrive whole?
//
// Protocol:
//   watch -> phone  {"cmd":"still","id":k}
//   phone -> watch  {"t":"s","id":k,"i":i,"n":n,"w":W,"h":H,"r0":row,"rows":r,"px":base64}
// Chunks hold whole rows of 4-bit gray pixels, MSB first. The phone sends the
// next chunk when the previous send completes; the watch never acks a chunk,
// because watch->phone messages were often late or lost in stage 0.
//
// The stage-0 frame-rate bench (fixed sizes, stop-and-wait) lives in git history
// at 409911d; its result is recorded in the plan document.

enum StillState {
    STILL_IDLE,
    STILL_WAITING,
    STILL_DONE
}

const TIMEOUT_MS = 15000;        // give up and show what arrived
const TICK_MS = 200;
const VIEW_PX = 276;             // largest square inside the 390 px round screen
const BPP = 4;
const HISTORY = 5;

class Bench {
    var state as StillState = STILL_IDLE;
    var requestId as Number = 0;
    var received as Number = 0;
    var total as Number = 0;
    var startAt as Number = 0;
    var firstChunkMs as Number = -1;
    var doneMs as Number = -1;
    var srcW as Number = 0;
    var srcH as Number = 0;
    var dispW as Number = 0;
    var dispH as Number = 0;
    var drawMs as Number = 0;
    var txErrors as Number = 0;
    var history as Array<String> = [] as Array<String>;

    var bitmap as Graphics.BufferedBitmapReference or Null = null;

    private var _palette as Array<Graphics.ColorType> = [] as Array<Graphics.ColorType>;
    private var _timer as Timer.Timer or Null = null;

    function initialize() {
        var saved = Application.Storage.getValue("still");
        if (saved instanceof Array) {
            history = saved as Array<String>;
        }
        for (var i = 0; i < 16; i++) {
            var g = (i * 255) / 15;
            _palette.add((g << 16) | (g << 8) | g);
        }
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
    }

    function request() as Void {
        requestId += 1;
        state = STILL_WAITING;
        received = 0;
        total = 0;
        firstChunkMs = -1;
        doneMs = -1;
        drawMs = 0;
        txErrors = 0;
        bitmap = null;
        startAt = System.getTimer();
        Communications.transmit({ "cmd" => "still", "id" => requestId }, null, new BenchListener(self));
        if (_timer == null) {
            _timer = new Timer.Timer();
            (_timer as Timer.Timer).start(method(:onTick), TICK_MS, true);
        }
        WatchUi.requestUpdate();
    }

    function stop() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    function elapsedMs() as Number {
        return System.getTimer() - startAt;
    }

    function onTick() as Void {
        if (state == STILL_WAITING && elapsedMs() > TIMEOUT_MS) {
            _finish(false);
        }
        WatchUi.requestUpdate();
    }

    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        var data = msg.data;
        if (!(data instanceof Dictionary) || state != STILL_WAITING) {
            return;
        }
        var d = data as Dictionary;
        if (!"s".equals(d.get("t")) || d.get("id") != requestId) {
            return; // a late chunk of an earlier request
        }
        var now = System.getTimer();
        if (firstChunkMs < 0) {
            firstChunkMs = now - startAt;
        }
        if (bitmap == null) {
            _allocate(d.get("w") as Number, d.get("h") as Number);
        }
        total = d.get("n") as Number;
        var bytes = StringUtil.convertEncodedString(d.get("px") as String, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        }) as ByteArray;
        _paintRows(bytes, d.get("r0") as Number, d.get("rows") as Number);
        drawMs += System.getTimer() - now;
        received += 1;
        if (received >= total) {
            _finish(true);
        }
        WatchUi.requestUpdate();
    }

    function onTransmitError() as Void {
        txErrors += 1;
    }

    private function _allocate(w as Number, h as Number) as Void {
        srcW = w;
        srcH = h;
        if (w >= h) {
            dispW = VIEW_PX;
            dispH = VIEW_PX * h / w;
        } else {
            dispH = VIEW_PX;
            dispW = VIEW_PX * w / h;
        }
        bitmap = Graphics.createBufferedBitmap({
            :width => dispW,
            :height => dispH,
            :palette => _palette
        });
        var dc = ((bitmap as Graphics.BufferedBitmapReference).get() as Graphics.BufferedBitmap).getDc();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
    }

    // Paints runs of equal gray as rectangles at fractional scale, so the photo
    // fills the screen without Dc.drawScaledBitmap (missing on FR165).
    private function _paintRows(bytes as ByteArray, row0 as Number, rows as Number) as Void {
        var ref = bitmap;
        if (ref == null) {
            return;
        }
        var dc = (ref.get() as Graphics.BufferedBitmap).getDc();
        var w = srcW;
        var rowBytes = w / 2;
        var palette = _palette;
        for (var r = 0; r < rows; r++) {
            var y = row0 + r;
            var y0 = y * dispH / srcH;
            var y1 = (y + 1) * dispH / srcH;
            if (y1 <= y0) {
                continue;
            }
            var off = r * rowBytes;
            var runStart = 0;
            var runLevel = -1;
            for (var x = 0; x < w; x++) {
                var b = bytes[off + x / 2];
                var lv = (x % 2 == 0) ? ((b >> 4) & 0x0F) : (b & 0x0F);
                if (lv != runLevel) {
                    if (runLevel >= 0) {
                        _fill(dc, palette[runLevel], runStart, x, y0, y1);
                    }
                    runLevel = lv;
                    runStart = x;
                }
            }
            _fill(dc, palette[runLevel], runStart, w, y0, y1);
        }
    }

    private function _fill(dc as Graphics.Dc, color as Graphics.ColorType,
                           xa as Number, xb as Number, y0 as Number, y1 as Number) as Void {
        var x0 = xa * dispW / srcW;
        var x1 = xb * dispW / srcW;
        if (x1 > x0) {
            dc.setColor(color, color);
            dc.fillRectangle(x0, y0, x1 - x0, y1 - y0);
        }
    }

    private function _finish(complete as Boolean) as Void {
        state = STILL_DONE;
        doneMs = elapsedMs();
        stop();
        // "7.4s" for a whole photo, "4/6x" when chunks were missing at the timeout
        var entry = complete
            ? (doneMs / 1000) + "." + ((doneMs / 100) % 10) + "s"
            : received + "/" + (total > 0 ? total.toString() : "?") + "x";
        history.add(entry);
        if (history.size() > HISTORY) {
            history = history.slice(history.size() - HISTORY, null) as Array<String>;
        }
        Application.Storage.setValue("still", history);
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
