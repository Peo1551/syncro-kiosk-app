/// The signed-in employee. Held in memory only and dropped at sign-out; it is
/// never written to storage.
class AppSession {
  const AppSession({
    required this.cookieHeader,
    this.csrf = '',
    this.companyId,
    this.employeeId,
    this.employeeFirstName = '',
    this.employeeLastName = '',
    this.employeeDisplayName = '',
    this.idleSeconds = 60,
  });

  final String cookieHeader;
  final String csrf;
  final int? companyId;
  final int? employeeId;
  final String employeeFirstName;
  final String employeeLastName;
  final String employeeDisplayName;
  final int idleSeconds;

  String get fullName {
    final display = employeeDisplayName.trim();
    if (display.isNotEmpty) return display;
    final joined = [
      employeeFirstName.trim(),
      employeeLastName.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
    return joined.isEmpty ? 'Employee' : joined;
  }

  String get initials {
    final first = employeeFirstName.trim();
    final last = employeeLastName.trim();
    if (first.isNotEmpty || last.isNotEmpty) {
      return '${first.isEmpty ? '' : first[0]}${last.isEmpty ? '' : last[0]}'
          .toUpperCase();
    }
    final parts = fullName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0]).join().toUpperCase();
  }

  AppSession copyWith({
    String? employeeFirstName,
    String? employeeLastName,
    String? employeeDisplayName,
  }) {
    return AppSession(
      cookieHeader: cookieHeader,
      csrf: csrf,
      companyId: companyId,
      employeeId: employeeId,
      employeeFirstName: employeeFirstName ?? this.employeeFirstName,
      employeeLastName: employeeLastName ?? this.employeeLastName,
      employeeDisplayName: employeeDisplayName ?? this.employeeDisplayName,
      idleSeconds: idleSeconds,
    );
  }
}
