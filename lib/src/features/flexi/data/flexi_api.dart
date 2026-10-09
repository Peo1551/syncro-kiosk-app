import '../../../config/app_config.dart';
import '../../../core/http/api_client.dart';
import '../../../core/session.dart';
import '../models/flexi_summary.dart';

class FlexiApi {
  const FlexiApi({required AppSession session, required ApiClient client})
    : _session = session,
      _client = client;

  final AppSession _session;
  final ApiClient _client;

  Future<FlexiSummary> fetchSummary() async {
    final json = await _client.getJson(
      path: AppConfig.flexiSummaryPath,
      cookieHeader: _session.cookieHeader,
    );
    return FlexiSummary.fromJson(json);
  }
}
