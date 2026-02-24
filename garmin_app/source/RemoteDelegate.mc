import Toybox.Lang;
import Toybox.WatchUi;

class RemoteDelegate extends WatchUi.BehaviorDelegate {
    private var _view as RemoteView;

    function initialize(view as RemoteView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        triggerShutter();
        return true;
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        triggerShutter();
        return true;
    }

    private function triggerShutter() as Void {
        var commManager = _view.getCommManager();
        if (commManager != null) {
            commManager.sendShutter();
        }
    }
}
