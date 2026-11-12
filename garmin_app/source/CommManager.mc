import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

enum /* AppState */ {
    STATE_NOT_CONNECTED,
    STATE_READY,
    STATE_WAITING,       // shutter sent, photo on its way
    STATE_PHOTO,         // photo shown until the user closes it
    STATE_PHOTO_FAILED,  // no chunk arrived in time
    STATE_PHOTO_OFF,     // phone has no photo permission
    STATE_NOT_CAMERA,    // phone pressed nothing: a non-camera app is in front
    STATE_SHUTTER_FAILED // phone could not find or press the shutter
}

class CommManager {
    // No chunk at all this long after the shutter: give up.
    const FIRST_CHUNK_TIMEOUT_MS = 15000;
    // Chunks take 2-5 s each (slower while the camera app is open), so a fixed
    // total cut off slow but healthy transfers. Give up only when they stop.
    const NEXT_CHUNK_TIMEOUT_MS = 8000;
    const TICK_MS = 250;

    var state as Number = STATE_READY;
    var photo as PhotoReceiver = new PhotoReceiver();
    var shutterConfirmed as Boolean = false;   // phone said the shutter was pressed

    private var _timer as Timer.Timer or Null;
    private var _nextId as Number = 0;
    private var _shutterAt as Number = 0;
    private var _lastChunkAt as Number = 0;

    function initialize(view as RemoteView) {
        state = STATE_READY;
        _nextId = System.getTimer() % 100000; // ids must not repeat across widget launches
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
    }

    // START always shoots, also from a shown or pending photo ("shoot again").
    function sendShutter() as Void {
        _nextId += 1;
        photo.reset(_nextId);
        shutterConfirmed = false;
        _shutterAt = System.getTimer();
        Communications.transmit({ "cmd" => "shutter", "id" => _nextId }, null, new CommListener(self));
        state = STATE_WAITING;
        _startTimer();
        WatchUi.requestUpdate();
    }

    // Close the photo or stop waiting for it. Late chunks of that photo are ignored.
    function dismiss() as Void {
        _stopTimer();
        photo.reset(-1);
        state = STATE_READY;
        WatchUi.requestUpdate();
    }

    function isShowingPhotoFlow() as Boolean {
        return state == STATE_WAITING || state == STATE_PHOTO
            || state == STATE_PHOTO_FAILED || state == STATE_PHOTO_OFF
            || state == STATE_NOT_CAMERA || state == STATE_SHUTTER_FAILED;
    }

    function onTransmitComplete() as Void {
    }

    function onTransmitError() as Void {
        _stopTimer();
        state = STATE_NOT_CONNECTED;
        WatchUi.requestUpdate();
    }

    function onTick() as Void {
        var now = System.getTimer();
        if (state == STATE_WAITING) {
            if (photo.received == 0 && now - _shutterAt > FIRST_CHUNK_TIMEOUT_MS) {
                _stopTimer();
                state = STATE_PHOTO_FAILED;
            } else if (photo.received > 0 && now - _lastChunkAt > NEXT_CHUNK_TIMEOUT_MS) {
                _stopTimer();
                state = STATE_PHOTO; // shown as "Partial"
            }
        }
        WatchUi.requestUpdate();
    }

    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        var data = msg.data;
        if (!(data instanceof Dictionary)) {
            return;
        }
        var d = data as Dictionary;
        var t = d.get("t");
        if ("s".equals(t)) {
            if (state == STATE_WAITING && photo.addChunk(d)) {
                _lastChunkAt = System.getTimer();
                if (photo.isComplete()) {
                    _stopTimer();
                    state = STATE_PHOTO;
                }
            }
        } else if ("p".equals(t)) {
            if (state == STATE_WAITING && d.get("id") == photo.id) {
                _stopTimer();
                state = "perm".equals(d.get("err")) ? STATE_PHOTO_OFF : STATE_PHOTO_FAILED;
            }
        } else if (d.hasKey("status")) {
            var id = d.get("id");
            if (id != null && id != photo.id) {
                return; // answer to an earlier shutter
            }
            var status = d.get("status");
            if ("ok".equals(status)) {
                shutterConfirmed = true;
            } else if (state == STATE_WAITING) {
                // The phone answered, so it is connected; it just did not shoot.
                _stopTimer();
                photo.reset(-1);
                state = "not_camera".equals(status) ? STATE_NOT_CAMERA : STATE_SHUTTER_FAILED;
            }
        }
        WatchUi.requestUpdate();
    }

    private function _startTimer() as Void {
        if (_timer == null) {
            _timer = new Timer.Timer();
            (_timer as Timer.Timer).start(method(:onTick), TICK_MS, true);
        }
    }

    private function _stopTimer() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }
}

class CommListener extends Communications.ConnectionListener {
    private var _manager as CommManager;

    function initialize(manager as CommManager) {
        ConnectionListener.initialize();
        _manager = manager;
    }

    function onComplete() as Void {
        _manager.onTransmitComplete();
    }

    function onError() as Void {
        _manager.onTransmitError();
    }
}
