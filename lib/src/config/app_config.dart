/// The one place the server address and endpoint paths are set.
class AppConfig {
  const AppConfig._();

  static const String appName = 'Syncro Kiosk';
  static const String baseUrl = 'https://syncroconnect.com';

  // Tablet endpoints (X-Kiosk-Token).
  static const String pairPath = '/kiosk/api/pair.php';
  static const String heartbeatPath = '/kiosk/api/heartbeat.php';
  static const String adminPinPath = '/kiosk/api/admin-pin.php';
  static const String unpairPath = '/kiosk/api/unpair.php';
  static const String signInPath = '/kiosk/api/sign-in.php';
  static const String signOutPath = '/kiosk/api/sign-out.php';

  // Employee endpoints, called exactly as the employee app calls them.
  static const String statusPath = '/employee/status-json.php';
  static const String leaveRequestsPath = '/employee/api/leave-requests.php';
  static const String leaveUpcomingPath = '/employee/api/upcoming-leave.php';
  static const String leaveEntitlementPath = '/employee/api/holiday-summary.php';
  static const String flexiSummaryPath = '/employee/api/flexi-summary.php';
  static const String timesheetsPath = '/employee/api/timesheets.php';
  static const String timesheetApprovePath =
      '/employee/api/timesheet-approve.php';

  static const Duration heartbeatInterval = Duration(seconds: 60);
  static const int defaultIdleSeconds = 120;
}
