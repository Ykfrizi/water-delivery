/// App-wide currency: Ghanaian Cedi (display / product prices).
const String kAppCurrency = 'GHS';

/// Currency sent to checkout & Paystack.
///
/// Leave empty to omit the field so the backend / Paystack merchant default
/// is used (avoids "Currency not supported by merchant" when the Paystack
/// account is not enabled for GHS).
///
/// Override at build time, e.g.:
/// `flutter run --dart-define=PAYMENT_CURRENCY=GHS`
const String kPaymentCurrency = String.fromEnvironment(
  'PAYMENT_CURRENCY',
  defaultValue: '',
);

/// Always return [kAppCurrency], ignoring API values like USD.
String appCurrencyCode([String? ignored]) => kAppCurrency;

/// Formats a money amount for display, e.g. `GHS 25.00`.
String formatMoney(num? amount, {String? currency}) {
  if (amount == null) return '—';
  final code = appCurrencyCode(currency);
  final text = amount % 1 == 0
      ? amount.toInt().toString()
      : amount.toStringAsFixed(2);
  return '$code $text';
}

/// Parses a dynamic price/total and formats as GHS.
String formatMoneyDynamic(dynamic value, {String? currency}) {
  if (value == null) return '—';
  if (value is num) return formatMoney(value, currency: currency);
  final parsed = num.tryParse(value.toString().replaceAll(RegExp(r'[^\d.-]'), ''));
  if (parsed != null) return formatMoney(parsed, currency: currency);
  return formatMoney(null);
}

/// Pretty-prints totals payloads, forcing GHS labels.
String prettyMoneyTotals(dynamic v) {
  if (v == null) return '';
  if (v is num) return formatMoney(v);
  if (v is String) {
    final parsed = num.tryParse(v);
    if (parsed != null) return formatMoney(parsed);
    return v.replaceAll(RegExp(r'\bUSD\b', caseSensitive: false), kAppCurrency);
  }
  if (v is Map) {
    final buf = StringBuffer();
    v.forEach((key, value) {
      final keyUpper = key.toString().toUpperCase();
      if (keyUpper == 'CURRENCY' ||
          keyUpper == 'CODE' ||
          keyUpper == 'CURRENCY_CODE') {
        return;
      }
      final label = keyUpper == 'USD'
          ? kAppCurrency
          : key.toString().replaceAll(
                RegExp(r'\bUSD\b', caseSensitive: false),
                kAppCurrency,
              );
      if (value is num) {
        buf.writeln('$label: ${formatMoney(value)}');
      } else if (value is Map || value is List) {
        final nested = prettyMoneyTotals(value);
        if (nested.isEmpty) return;
        buf.writeln('$label:');
        buf.writeln(nested);
      } else {
        final raw = value?.toString() ?? '';
        if (raw.toUpperCase() == kAppCurrency) return;
        final asNum = num.tryParse(raw.replaceAll(RegExp(r'[^\d.-]'), ''));
        if (asNum != null) {
          buf.writeln('$label: ${formatMoney(asNum)}');
        } else if (raw.trim().isNotEmpty) {
          buf.writeln(
            '$label: ${raw.replaceAll(RegExp(r'\bUSD\b', caseSensitive: false), kAppCurrency)}',
          );
        }
      }
    });
    return buf.toString().trim();
  }
  if (v is List) {
    return v.map(prettyMoneyTotals).join('\n');
  }
  return v
      .toString()
      .replaceAll(RegExp(r'\bUSD\b', caseSensitive: false), kAppCurrency);
}
