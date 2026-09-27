/// Vendor order lifecycle helpers.
bool orderNeedsVendorApproval(String? status) {
  final s = status?.toLowerCase().trim() ?? '';
  return s.isEmpty ||
      s == 'pending' ||
      s == 'awaiting_approval' ||
      s == 'awaiting_vendor' ||
      s == 'new';
}

bool orderIsApprovedByVendor(String? status) {
  final s = status?.toLowerCase().trim() ?? '';
  return s == 'processing' ||
      s == 'confirmed' ||
      s == 'accepted' ||
      s == 'approved' ||
      s == 'preparing' ||
      s == 'shipped' ||
      s == 'out_for_delivery' ||
      s == 'delivered';
}

bool orderIsPaidOnline(Map<String, dynamic> order) {
  final v = (order['payment_status'] ??
          (order['payment'] is Map ? order['payment']['status'] : null))
      ?.toString()
      .toLowerCase()
      .trim();
  if (order['paid_at'] != null) return true;
  return v == 'paid' || v == 'success' || v == 'successful' || v == 'completed';
}

bool orderIsPayOnDelivery(Map<String, dynamic> order) {
  if (order['pay_on_delivery'] == true) return true;
  final method = [
    order['payment_method'],
    order['payment_provider'],
    order['payment_label'],
  ].where((e) => e != null).map((e) => e.toString().toLowerCase()).join(' ');
  return method.contains('cash') ||
      method.contains('cod') ||
      method.contains('pod') ||
      method.contains('delivery');
}

/// Orders the vendor should see: paid online, or pay-on-delivery.
bool orderIsPaidForVendor(Map<String, dynamic> order) {
  return orderIsPaidOnline(order) || orderIsPayOnDelivery(order);
}

String vendorPaymentKindLabel(Map<String, dynamic> order) {
  if (orderIsPayOnDelivery(order)) return 'Pay on delivery';
  if (orderIsPaidOnline(order)) return 'Paid';
  return 'Unpaid';
}

String vendorOrderStatusLabel(String? status) {
  final s = status?.toLowerCase().trim() ?? '';
  if (orderNeedsVendorApproval(status)) return 'Needs your approval';
  if (s == 'cancelled' || s == 'rejected') return 'Rejected / cancelled';
  if (s == 'processing' ||
      s == 'confirmed' ||
      s == 'accepted' ||
      s == 'approved' ||
      s == 'preparing') {
    return 'Approved · preparing';
  }
  if (s == 'shipped' || s == 'out_for_delivery') return 'Approved · shipping';
  if (s == 'delivered') return 'Delivered';
  return status?.toString() ?? '—';
}
