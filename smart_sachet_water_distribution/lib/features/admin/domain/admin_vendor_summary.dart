/// Vendor row for admin approval workflows.
class AdminVendorSummary {
  const AdminVendorSummary({
    required this.slug,
    required this.name,
    this.email,
    this.businessName,
    this.ghanaCardNumber,
    this.approvalStatus,
    required this.raw,
  });

  final String slug;
  final String name;
  final String? email;
  final String? businessName;
  final String? ghanaCardNumber;
  final String? approvalStatus;
  final Map<String, dynamic> raw;

  factory AdminVendorSummary.fromJson(Map<String, dynamic> json) {
    final slug = (json['slug'] ?? json['id'])?.toString() ?? '';
    final name = (json['name'] ?? json['business_name'] ?? 'Vendor').toString();

    String? status = json['approval_status']?.toString() ??
        json['approvalStatus']?.toString();

    final rawStatus = json['status']?.toString();
    if (status == null && rawStatus != null) {
      final lower = rawStatus.toLowerCase();
      if (lower == 'pending' ||
          lower == 'approved' ||
          lower == 'rejected' ||
          lower == 'active' ||
          lower == 'suspended' ||
          lower == 'inactive') {
        status = lower;
      }
    }

    if (status == null) {
      final approved = json['is_approved'] ?? json['isApproved'];
      if (approved is bool) {
        status = approved ? 'approved' : 'pending';
      }
    }

    final ghana = (json['ghana_card_number'] ??
            json['ghana_card'] ??
            json['ghanaCardNumber'] ??
            json['ghanaCard'])
        ?.toString();

    return AdminVendorSummary(
      slug: slug,
      name: name,
      email: json['email']?.toString(),
      businessName: json['business_name']?.toString(),
      ghanaCardNumber: (ghana != null && ghana.trim().isNotEmpty) ? ghana.trim() : null,
      approvalStatus: status,
      raw: json,
    );
  }

  bool get isApproved {
    final s = approvalStatus?.toLowerCase();
    return s == 'approved' || s == 'active';
  }

  bool get isRejected {
    final s = approvalStatus?.toLowerCase();
    return s == 'rejected' || s == 'suspended' || s == 'inactive';
  }

  bool get isPending => !isApproved && !isRejected;

  String get statusLabel {
    if (isApproved) return 'Approved';
    if (isRejected) return 'Rejected';
    return 'Pending';
  }

  String get displayTitle =>
      businessName != null && businessName!.isNotEmpty ? businessName! : name;
}
