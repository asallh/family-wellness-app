import Toybox.Lang;
import Toybox.WatchUi;

class family_wellnessDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onMenu() as Boolean {
        WatchUi.pushView(new Rez.Menus.MainMenu(), new family_wellnessMenuDelegate(), WatchUi.SLIDE_UP);
        return true;
    }

}