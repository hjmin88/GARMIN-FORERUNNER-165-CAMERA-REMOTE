import Toybox.Lang;
import Toybox.WatchUi;

class RemoteDelegate extends WatchUi.BehaviorDelegate {
    private var _view as RemoteView;

    function initialize(view as RemoteView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // START: shoot, also from a shown photo ("shoot again").
    function onSelect() as Boolean {
        triggerShutter();
        return true;
    }

    // Tap: close the photo (or stop waiting); otherwise shoot.
    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        var cm = _view.getCommManager();
        if (cm != null && cm.isShowingPhotoFlow()) {
            cm.dismiss();
        } else {
            triggerShutter();
        }
        return true;
    }

    // BACK: close the photo (or stop waiting); otherwise leave the widget.
    function onBack() as Boolean {
        var cm = _view.getCommManager();
        if (cm != null && cm.isShowingPhotoFlow()) {
            cm.dismiss();
            return true;
        }
        return false;
    }

    private function triggerShutter() as Void {
        var commManager = _view.getCommManager();
        if (commManager != null) {
            commManager.sendShutter();
        }
    }
}
