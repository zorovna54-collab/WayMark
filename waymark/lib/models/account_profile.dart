class AccountProfile {
  const AccountProfile({
    required this.userName,
    required this.displayName,
    required this.email,
    required this.emailVerified,
    required this.roles,
    this.canCreatePersonalMaps = false,
    this.canManageMaps = false,
    this.canManageFacility = false,
    this.isSystemAdmin = false,
    this.managedSites = const [],
  });
  final String userName, displayName;
  final String? email;
  final bool emailVerified;
  final List<String> roles;
  final bool canCreatePersonalMaps,
      canManageMaps,
      canManageFacility,
      isSystemAdmin;
  final List<Map<String, dynamic>> managedSites;
  bool get canEditMaps => canManageMaps;

  factory AccountProfile.fromJson(Map<String, dynamic> json) {
    if (json['userName'] is! String ||
        json['displayName'] is! String ||
        json['emailVerified'] is! bool ||
        json['roles'] is! List ||
        (json['roles'] as List).any((r) => r is! String) ||
        (json['email'] != null && json['email'] is! String)) {
      throw const FormatException('Dữ liệu hồ sơ không hợp lệ.');
    }
    final raw = json['capabilities'];
    if (raw != null && raw is! Map<String, dynamic>) {
      throw const FormatException('Quyền tài khoản không hợp lệ.');
    }
    final capabilities = raw as Map<String, dynamic>? ?? const {};
    for (final key in [
      'canCreatePersonalMaps',
      'canManageMaps',
      'canManageFacility',
      'isSystemAdmin',
    ]) {
      if (capabilities[key] != null && capabilities[key] is! bool) {
        throw const FormatException('Quyền tài khoản không hợp lệ.');
      }
    }
    final sites = capabilities['managedSites'];
    if (sites != null &&
        (sites is! List ||
            sites.any(
              (s) => s is! Map || s['id'] is! int || s['name'] is! String,
            ))) {
      throw const FormatException('Phạm vi Site không hợp lệ.');
    }
    return AccountProfile(
      userName: json['userName'],
      displayName: json['displayName'],
      email: json['email'],
      emailVerified: json['emailVerified'],
      roles: List<String>.unmodifiable(json['roles']),
      canCreatePersonalMaps: capabilities['canCreatePersonalMaps'] == true,
      canManageMaps: capabilities['canManageMaps'] == true,
      canManageFacility: capabilities['canManageFacility'] == true,
      isSystemAdmin: capabilities['isSystemAdmin'] == true,
      managedSites: ((capabilities['managedSites'] as List?) ?? const [])
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList(),
    );
  }
}
