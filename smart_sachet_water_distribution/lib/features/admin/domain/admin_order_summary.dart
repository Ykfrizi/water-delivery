/// Loose model — Laravel resource shapes vary; [raw] keeps extra fields for UI/debug.
class AdminOrderSummary {
  const AdminOrderSummary({
    required this.orderNumber,
    this.status,
    this.customerEmail,
    this.vendorSlug,
    required this.raw,
  });

  final String orderNumber;
  final String? status;
  final String? customerEmail;
  final String? vendorSlug;
  final Map<String, dynamic> raw;

  factory AdminOrderSummary.fromJson(Map<String, dynamic> json) {
    final orderNum = (json['order_number'] ?? json['orderNumber'] ?? json['id'])
        ?.toString();

    String? customerEmail =
        json['customer_email']?.toString() ?? json['email']?.toString();
    final customer = json['customer'];
    if (customerEmail == null && customer is Map) {
      customerEmail =
          (customer['email'] ?? customer['name'])?.toString();
    }

    String? vendorSlug = json['vendor_slug']?.toString();
    final vendor = json['vendor'];
    if (vendorSlug == null && vendor is Map) {
      vendorSlug = (vendor['slug'] ?? vendor['business_name'] ?? vendor['name'])
          ?.toString();
    }

    return AdminOrderSummary(
      orderNumber: orderNum ?? '',
      status: json['status']?.toString(),
      customerEmail: customerEmail,
      vendorSlug: vendorSlug,
      raw: json,
    );
  }

  String get title => orderNumber.isEmpty ? 'Order' : 'Order #$orderNumber';

  bool get needsApproval {
    final s = status?.toLowerCase().trim() ?? '';
    return s.isEmpty ||
        s == 'pending' ||
        s == 'awaiting_approval' ||
        s == 'awaiting_admin' ||
        s == 'new';
  }

  String get statusLabel {
    if (needsApproval) return 'Needs approval';
    final s = status?.toLowerCase() ?? '';
    if (s == 'processing' || s == 'confirmed') return 'Approved · processing';
    if (s == 'shipped' || s == 'out_for_delivery') return 'Shipping';
    if (s == 'delivered') return 'Delivered';
    if (s == 'cancelled' || s == 'rejected') return 'Cancelled';
    return status ?? '—';
  }
}
