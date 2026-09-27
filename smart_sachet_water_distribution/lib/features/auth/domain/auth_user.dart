class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.extra = const {},
  });

  final String id;
  final String name;
  final String email;
  final Map<String, dynamic> extra;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final nested = json['user'];
    final source = nested is Map
        ? {...json, ...Map<String, dynamic>.from(nested)}
        : json;

    final id = (source['id'] ?? json['id'])?.toString() ?? '';
    final email = (source['email'] ?? json['email'] ?? '').toString();
    final name = _extractName(source) ?? _extractName(json) ?? 'User';

    return AuthUser(id: id, name: name, email: email, extra: json);
  }

  static String? _extractName(Map<String, dynamic> json) {
    for (final key in const [
      'name',
      'full_name',
      'fullName',
      'display_name',
      'displayName',
      'business_name',
      'businessName',
      'store_name',
      'storeName',
    ]) {
      final v = json[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }

    final first = (json['first_name'] ?? json['firstName'])?.toString().trim();
    final last = (json['last_name'] ?? json['lastName'])?.toString().trim();
    final parts = <String>[
      if (first != null && first.isNotEmpty) first,
      if (last != null && last.isNotEmpty) last,
    ];
    if (parts.isNotEmpty) return parts.join(' ');
    return null;
  }

  /// First word of [name] for greetings like "Hello Fred!".
  String get firstName {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'user') return 'there';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  String get greeting => 'Hello $firstName!';

  String? get phone {
    for (final source in [extra, extra['user'], extra['data']]) {
      if (source is! Map) continue;
      final v = (source['phone'] ?? source['mobile'])?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  String? get ghanaCardNumber {
    final v = extra['ghana_card_number'] ??
        extra['ghana_card'] ??
        extra['ghanaCardNumber'] ??
        extra['ghanaCard'];
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Normalized approval status: approved | pending | rejected | unknown
  String get approvalStatus {
    final approval = (extra['approval_status'] ?? extra['approvalStatus'])
        ?.toString()
        .toLowerCase()
        .trim();
    if (approval != null && approval.isNotEmpty) {
      if (approval == 'active') return 'approved';
      if (approval == 'suspended' || approval == 'inactive') return 'rejected';
      return approval;
    }

    final approved = extra['is_approved'] ?? extra['isApproved'];
    if (approved is bool) return approved ? 'approved' : 'pending';

    final status = extra['status']?.toString().toLowerCase().trim();
    if (status != null && status.isNotEmpty) {
      if (status == 'approved' || status == 'active') return 'approved';
      if (status == 'rejected' ||
          status == 'suspended' ||
          status == 'inactive' ||
          status == 'declined') {
        return 'rejected';
      }
      if (status == 'pending' || status == 'awaiting_approval') return 'pending';
    }

    return 'unknown';
  }

  bool get isVendorApproved =>
      approvalStatus == 'approved' || approvalStatus == 'active';

  bool get isVendorRejected =>
      approvalStatus == 'rejected' ||
      approvalStatus == 'suspended' ||
      approvalStatus == 'inactive';

  /// Vendors may use the dashboard only after admin approval.
  bool get canAccessVendorDashboard => isVendorApproved;
}
