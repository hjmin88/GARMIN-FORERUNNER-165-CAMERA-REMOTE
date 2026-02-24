import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class CameraRemoteApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new RemoteView();
        var delegate = new RemoteDelegate(view);
        return [view, delegate];
    }
}
