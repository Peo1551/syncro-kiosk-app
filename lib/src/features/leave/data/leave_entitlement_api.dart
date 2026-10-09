import '../../../config/app_config.dart';
import '../../../core/http/api_client.dart';
import '../../../core/session.dart';
import '../models/leave_entitlement.dart';

class LeaveEntitlementApi {
  const LeaveEntitlementApi({required AppSession session, required ApiClient client})
    : _session = session,
      _client = client;

  final AppSession _session;
  final ApiClient _client;

  Future<LeaveEntitlement> fetch() async {
    final json = await _client.getJson(
      path: AppConfig.leaveEntitlementPath,
      cookieHeader: _session.cookieHeader,
    );
    return LeaveEntitlement.fromJson(json);
  }
}
