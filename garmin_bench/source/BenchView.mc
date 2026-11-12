import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class BenchView extends WatchUi.View {
    private var _bench as Bench or Null = null;

    function initialize() {
        View.initialize();
    }

    function setBench(bench as Bench) as Void {
        _bench = bench;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var b = _bench;
        if (b == null) {
            return;
        }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        var ref = b.bitmap;
        if (ref != null) {
            dc.drawBitmap(cx - b.dispW / 2, h / 2 - b.dispH / 2, ref.get() as Graphics.BufferedBitmap);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (b.state == STILL_IDLE) {
            dc.drawText(cx, h / 2 - 30, Graphics.FONT_SMALL, "Tap or START",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h / 2 + 10, Graphics.FONT_XTINY, "Sends newest phone photo",
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            var t = b.state == STILL_DONE ? b.doneMs : b.elapsedMs();
            var head = b.received + "/" + (b.total > 0 ? b.total.toString() : "?")
                       + "  " + _sec(t);
            dc.drawText(cx, 18, Graphics.FONT_XTINY, head, Graphics.TEXT_JUSTIFY_CENTER);
            if (b.state == STILL_WAITING && b.received == 0) {
                dc.drawText(cx, h / 2, Graphics.FONT_SMALL, "Sending photo...",
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        }

        // Bottom rim, outside the photo: first-chunk time, decode cost, errors, history.
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        if (b.state != STILL_IDLE) {
            dc.drawText(cx, h - 62, Graphics.FONT_XTINY,
                        "1st " + _sec(b.firstChunkMs) + " draw " + b.drawMs + "ms err " + b.txErrors,
                        Graphics.TEXT_JUSTIFY_CENTER);
        }
        var hist = "";
        for (var i = 0; i < b.history.size(); i++) {
            hist += (i > 0 ? " " : "") + b.history[i];
        }
        dc.drawText(cx, h - 38, Graphics.FONT_XTINY, hist, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function _sec(ms as Number) as String {
        if (ms < 0) {
            return "-";
        }
        return (ms / 1000) + "." + ((ms / 100) % 10) + "s";
    }
}
