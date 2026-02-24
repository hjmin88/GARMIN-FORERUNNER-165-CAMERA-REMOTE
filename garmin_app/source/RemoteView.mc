import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class RemoteView extends WatchUi.View {
    private var _commManager as CommManager or Null;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Graphics.Dc) as Void {
    }

    function onShow() as Void {
        if (_commManager == null) {
            _commManager = new CommManager(self);
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;

        if (_commManager == null) {
            return;
        }

        var currentState = _commManager.state;

        if (currentState == STATE_NOT_CONNECTED) {
            drawNotConnected(dc, cx, cy);
        } else if (currentState == STATE_READY) {
            drawReady(dc, cx, cy, h);
        } else if (currentState == STATE_SENT) {
            drawSent(dc, cx, cy);
        }
    }

    private function drawNotConnected(dc as Graphics.Dc, cx as Number, cy as Number) as Void {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - 15, cy - 40, 30, 50, 4);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - 12, cy - 35, 24, 40);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy + 6, 3);

        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(cx - 20, cy - 45, cx + 20, cy + 15);
        dc.drawLine(cx + 20, cy - 45, cx - 20, cy + 15);
        dc.setPenWidth(1);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 35, Graphics.FONT_SMALL, "No Phone",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, cy + 60, Graphics.FONT_XTINY, "Open companion app",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawReady(dc as Graphics.Dc, cx as Number, cy as Number, h as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(4);
        dc.drawCircle(cx, cy, 60);
        dc.setPenWidth(1);

        dc.fillCircle(cx, cy, 50);

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, 46);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, 42);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h - 45, Graphics.FONT_XTINY, "Tap or START",
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawSent(dc as Graphics.Dc, cx as Number, cy as Number) as Void {
        dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, 55);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(6);
        dc.drawLine(cx - 20, cy, cx - 5, cy + 18);
        dc.drawLine(cx - 5, cy + 18, cx + 22, cy - 15);
        dc.setPenWidth(1);
    }

    function getCommManager() as CommManager or Null {
        return _commManager;
    }
}
