import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.WatchUi;

class family_wellnessApp extends Application.AppBase {

    var tester as Tester?;
    var family as FamilyState?;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
        // Keep GPS and heart rate readings fresh for telemetry.
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE] as Array<Sensor.SensorType>);
        tester = new Tester();
        family = new FamilyState(tester);
        family.start();
        if (Config.AUTO_SELF_TEST) {
            tester.runSelfTest();
        }
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        if (tester != null) {
            tester.stop();
        }
        if (family != null) {
            family.stop();
        }
    }

    // Telemetry reads Position.getInfo(), so nothing to do here.
    function onPosition(info as Position.Info) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var list = new FamilyListView();
        return [ list, new FamilyListDelegate(list) ];
    }

}

function getApp() as family_wellnessApp {
    return Application.getApp() as family_wellnessApp;
}

function getTester() as Tester {
    return getApp().tester as Tester;
}

function getState() as FamilyState {
    return getApp().family as FamilyState;
}
