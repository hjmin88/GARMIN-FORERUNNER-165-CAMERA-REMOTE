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
        } else if (currentState == STATE_WAITING) {
            drawWaiting(dc, cx, cy, h);
        } else if (currentState == STATE_PHOTO) {
            drawPhoto(dc, cx, cy, h);
        } else if (currentState == STATE_PHOTO_FAILED) {
            drawMessage(dc, cx, cy, Rez.Strings.PhotoNotReceived,
                        _commManager.shutterConfirmed ? Rez.Strings.ShutterWorked : Rez.Strings.CheckPhone);
        } else if (currentState == STATE_PHOTO_OFF) {
            drawMessage(dc, cx, cy, Rez.Strings.PhotoAccessOff, Rez.Strings.AllowPhotos);
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

    // "Sending photo..." until the first chunk, then the photo fills in from the
    // top with a progress bar under it.
    private function drawWaiting(dc as Graphics.Dc, cx as Number, cy as Number, h as Number) as Void {
        var p = (_commManager as CommManager).photo;
        if (p.received == 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, Graphics.FONT_SMALL, WatchUi.loadResource(Rez.Strings.SendingPhoto) as String,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        drawBitmapOf(dc, p, cx, cy);
        var barW = 120;
        var barY = cy + p.dispH / 2 + 10;
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - barW / 2, barY, barW, 6);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - barW / 2, barY, barW * p.received / p.total, 6);
    }

    // Nothing is drawn over the photo. "Partial" goes on the rim below it.
    private function drawPhoto(dc as Graphics.Dc, cx as Number, cy as Number, h as Number) as Void {
        var p = (_commManager as CommManager).photo;
        drawBitmapOf(dc, p, cx, cy);
        if (!p.isComplete()) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + p.dispH / 2 + 4, Graphics.FONT_XTINY,
                        WatchUi.loadResource(Rez.Strings.Partial) as String, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    private function drawBitmapOf(dc as Graphics.Dc, p as PhotoReceiver, cx as Number, cy as Number) as Void {
        var ref = p.bitmap;
        if (ref != null) {
            dc.drawBitmap(cx - p.dispW / 2, cy - p.dispH / 2, ref.get() as Graphics.BufferedBitmap);
        }
    }

    private function drawMessage(dc as Graphics.Dc, cx as Number, cy as Number,
                                 title as ResourceId, detail as ResourceId) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 15, Graphics.FONT_SMALL, WatchUi.loadResource(title) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 20, Graphics.FONT_XTINY, WatchUi.loadResource(detail) as String,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function getCommManager() as CommManager or Null {
        return _commManager;
    }
}
