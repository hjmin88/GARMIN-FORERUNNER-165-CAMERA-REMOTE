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
        if (b.state == BENCH_RUNNING) {
            _drawRunning(dc, b);
        } else if (b.state == BENCH_DONE) {
            _drawSummary(dc, b.results, "Done - photo this screen");
        } else if (b.lastResults != null) {
            _drawSummary(dc, b.lastResults as Array, "Last run. Tap to rerun");
        } else {
            _drawIdle(dc);
        }
    }

    private function _drawIdle(dc as Graphics.Dc) as Void {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 40, Graphics.FONT_SMALL, "Tap or START",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Graphics.FONT_XTINY, "4 sizes x 20 s",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, cy + 28, Graphics.FONT_XTINY, "Open companion app first",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function _drawRunning(dc as Graphics.Dc, b as Bench) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var c = b.config();

        var ref = b.bitmap;
        if (ref != null && b.frames > 0) {
            var scale = 200 / c[0];
            var size = c[0] * scale;
            dc.drawScaledBitmap(cx - size / 2, h / 2 - size / 2, size, size,
                                ref.get() as Graphics.BufferedBitmap);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var label = (b.phase + 1).toString() + "/" + Bench.CONFIGS.size() + "  "
                    + c[0] + "x" + c[1] + " " + c[2] + "b";
        dc.drawText(cx, 40, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER);

        var fps10 = b.liveFps10();
        var rtt = b.rttCount > 0 ? b.rttSum / b.rttCount : 0;
        dc.drawText(cx, h - 78, Graphics.FONT_TINY,
                    _fps(fps10) + " fps  " + rtt + " ms",
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h - 48, Graphics.FONT_XTINY,
                    "mem " + (b.memPeak / 1024) + "K  err " + b.txErrors,
                    Graphics.TEXT_JUSTIFY_CENTER);

        if (!"".equals(b.status)) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, h / 2, Graphics.FONT_SMALL, b.status,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // One row per configuration: size  fps  avg/max rtt  draw  mem
    private function _drawSummary(dc as Graphics.Dc, rows as Array, footer as String) as Void {
        var cx = dc.getWidth() / 2;
        var y = 60;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY, "size fps rtt/max draw",
                    Graphics.TEXT_JUSTIFY_CENTER);
        y += 30;
        var memLine = "";
        var errs = 0;
        for (var i = 0; i < rows.size(); i++) {
            var r = rows[i] as Dictionary;
            var line = r["cfg"] + " " + _fps(r["fps10"] as Number) + " "
                       + r["rtt"] + "/" + r["rttMax"] + " " + r["draw"];
            dc.drawText(cx, y, Graphics.FONT_XTINY, line, Graphics.TEXT_JUSTIFY_CENTER);
            y += 30;
            memLine = "mem peak " + r["memKB"] + "/" + r["memTotKB"] + "K";
            errs += (r["err"] as Number) + (r["stall"] as Number);
        }
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Graphics.FONT_XTINY, memLine + " err+stall " + errs,
                    Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, y + 30, Graphics.FONT_XTINY, footer, Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function _fps(fps10 as Number) as String {
        return (fps10 / 10).toString() + "." + (fps10 % 10);
    }
}
