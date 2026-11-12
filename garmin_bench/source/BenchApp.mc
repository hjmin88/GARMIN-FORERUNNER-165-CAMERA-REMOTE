import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class BenchApp extends Application.AppBase {
    private var _bench as Bench or Null;

    function initialize() {
        AppBase.initialize();
    }

    function onStop(state as Dictionary or Null) as Void {
        // Tell the phone to stop sending. If this never reaches the phone
        // (crash, BLE drop), the phone's own 5 s watchdog stops it.
        if (_bench != null) {
            _bench.stop();
        }
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new BenchView();
        var bench = new Bench(view);
        view.setBench(bench);
        _bench = bench;
        return [view, new BenchDelegate(bench)];
    }
}

class BenchDelegate extends WatchUi.BehaviorDelegate {
    private var _bench as Bench;

    function initialize(bench as Bench) {
        BehaviorDelegate.initialize();
        _bench = bench;
    }

    function onSelect() as Boolean {
        _bench.startIfIdle();
        return true;
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        _bench.startIfIdle();
        return true;
    }
}
