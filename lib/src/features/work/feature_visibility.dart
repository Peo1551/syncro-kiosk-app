import '../flexi/models/flexi_summary.dart';
import '../status/employee_status.dart';

/// The kiosk's employee features: the phone app's "My Work" tab, nothing more.
enum KioskFeature {
  requestLeave,
  requestHistory,
  upcomingLeave,
  myEntitlement,
  myClockingHub,
  myFlexi,
}

/// Which tiles the signed-in employee sees.
///
/// As in the employee app: the leave tiles always show and the leave types
/// inside them come from the leave API (which applies the mobile app group);
/// team and company tabs in Upcoming Leave come from the upcoming-leave
/// permissions; My Flexi shows only when flexi-summary says on_flexi.
/// My Clocking Hub follows the group's view_time_sheet switch, because the
/// server refuses timesheets.php without it.
List<KioskFeature> visibleFeatures({
  required MobilePermissions permissions,
  required FlexiSummary? flexi,
}) {
  return [
    KioskFeature.requestLeave,
    KioskFeature.requestHistory,
    KioskFeature.upcomingLeave,
    KioskFeature.myEntitlement,
    if (permissions.viewTimeSheet) KioskFeature.myClockingHub,
    if (FlexiSummary.shouldShow(flexi)) KioskFeature.myFlexi,
  ];
}
