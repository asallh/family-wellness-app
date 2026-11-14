import Toybox.Lang;
import Toybox.WatchUi;

// START or MENU opens the API tester menu.
class family_wellnessDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onMenu() as Boolean {
        openTesterMenu();
        return true;
    }

    function onSelect() as Boolean {
        openTesterMenu();
        return true;
    }

}
