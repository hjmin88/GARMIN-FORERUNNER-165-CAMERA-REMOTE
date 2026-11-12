import Toybox.Graphics;
import Toybox.Lang;
import Toybox.StringUtil;

// Rebuilds the post-shot photo from the phone's chunks.
//
// Chunk: {"t":"s","id":k,"i":i,"n":n,"w":W,"h":H,"r0":row,"rows":r,"px":base64}
// px is run-length coded gray: one byte per run, (level << 4) | (run - 1), runs
// of 1..16 pixels, 16 gray levels, never crossing a row. Chunks may arrive in any
// order or twice; missing ones leave black bands (shown as "Partial").
class PhotoReceiver {
    const VIEW_PX = 276;         // largest square inside the 390 px round screen

    var id as Number = -1;
    var received as Number = 0;
    var total as Number = 0;
    var dispW as Number = 0;
    var dispH as Number = 0;
    var bitmap as Graphics.BufferedBitmapReference or Null = null;

    private var _srcW as Number = 0;
    private var _srcH as Number = 0;
    private var _seen as Array<Boolean> = [] as Array<Boolean>;
    private var _palette as Array<Graphics.ColorType> = [] as Array<Graphics.ColorType>;

    function initialize() {
        for (var i = 0; i < 16; i++) {
            var g = (i * 255) / 15;
            _palette.add((g << 16) | (g << 8) | g);
        }
    }

    // Start listening for photo [newId]; drops the previous photo and its late chunks.
    function reset(newId as Number) as Void {
        id = newId;
        received = 0;
        total = 0;
        bitmap = null;
        _seen = [] as Array<Boolean>;
    }

    function isComplete() as Boolean {
        return total > 0 && received >= total;
    }

    // Returns true when the chunk belonged to the current photo and was new.
    function addChunk(d as Dictionary) as Boolean {
        if (d.get("id") != id) {
            return false;
        }
        var n = d.get("n");
        var i = d.get("i");
        if (!(n instanceof Number) || !(i instanceof Number) || i < 0 || i >= n) {
            return false;
        }
        if (_seen.size() != n) {
            _seen = new Array<Boolean>[n];
            total = n;
        }
        if (_seen[i] == true) {
            return false;
        }
        if (bitmap == null) {
            _allocate(d.get("w") as Number, d.get("h") as Number);
        }
        var bytes = StringUtil.convertEncodedString(d.get("px") as String, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_BASE64,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        }) as ByteArray;
        _paintRows(bytes, d.get("r0") as Number, d.get("rows") as Number);
        _seen[i] = true;
        received += 1;
        return true;
    }

    private function _allocate(w as Number, h as Number) as Void {
        _srcW = w;
        _srcH = h;
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

    // Runs are painted as rectangles at fractional scale, so the photo fills the
    // screen without Dc.drawScaledBitmap (missing on FR165).
    private function _paintRows(bytes as ByteArray, row0 as Number, rows as Number) as Void {
        var ref = bitmap;
        if (ref == null) {
            return;
        }
        var dc = (ref.get() as Graphics.BufferedBitmap).getDc();
        var w = _srcW;
        var y = row0;
        var yEnd = row0 + rows;
        var x = 0;
        var y0 = y * dispH / _srcH;
        var y1 = (y + 1) * dispH / _srcH;
        for (var k = 0; k < bytes.size() && y < yEnd; k++) {
            var b = bytes[k];
            var run = (b & 0x0F) + 1;
            if (y1 > y0) {
                var x0 = x * dispW / w;
                var x1 = (x + run) * dispW / w;
                if (x1 > x0) {
                    var color = _palette[(b >> 4) & 0x0F];
                    dc.setColor(color, color);
                    dc.fillRectangle(x0, y0, x1 - x0, y1 - y0);
                }
            }
            x += run;
            if (x >= w) {
                x = 0;
                y += 1;
                y0 = y1;
                y1 = (y + 1) * dispH / _srcH;
            }
        }
    }
}
