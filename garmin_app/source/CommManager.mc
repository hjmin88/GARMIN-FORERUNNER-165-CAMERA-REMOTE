import Toybox.Communications;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

enum /* AppState */ {
    STATE_NOT_CONNECTED,
    STATE_READY,
    STATE_SENT
}

class CommManager {
    var state as Number = STATE_READY;
    private var _view as RemoteView;
    private var _resetTimer as Timer.Timer or Null;

    function initialize(view as RemoteView) {
        _view = view;
        state = STATE_READY;
        Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
    }

    function sendShutter() as Void {
        if (state == STATE_SENT) {
            return;
        }

        var message = { "cmd" => "shutter" };
        Communications.transmit(message, null, new CommListener(self));
        state = STATE_SENT;
        WatchUi.requestUpdate();

        _resetTimer = new Timer.Timer();
        _resetTimer.start(method(:resetToReady), 1500, false);
    }

    function onTransmitComplete() as Void {
    }

    function onTransmitError() as Void {
        if (_resetTimer != null) {
            _resetTimer.stop();
            _resetTimer = null;
        }
        state = STATE_NOT_CONNECTED;
        WatchUi.requestUpdate();
    }

    function resetToReady() as Void {
        _resetTimer = null;
        state = STATE_READY;
        WatchUi.requestUpdate();
    }

    function onPhoneMessage(msg as Communications.PhoneAppMessage) as Void {
        var data = msg.data;
        if (data instanceof Dictionary) {
            var status = (data as Dictionary).get("status");
            if ("ok".equals(status)) {
                state = STATE_READY;
            } else {
                state = STATE_NOT_CONNECTED;
            }
        }
        WatchUi.requestUpdate();
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
