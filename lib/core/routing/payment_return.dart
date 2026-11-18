String? paymentOrderFromUri(Uri uri) {
  final direct = uri.queryParameters['order_id'] ?? uri.queryParameters['orderId'];
  if (direct != null && direct.isNotEmpty) return direct;
  final fragment = Uri.tryParse(uri.fragment);
  final nested = fragment?.queryParameters['order_id'] ??
      fragment?.queryParameters['orderId'];
  return nested == null || nested.isEmpty ? null : nested;
}

String paymentResultLocation(String orderId) =>
    Uri(path: '/payment-result', queryParameters: {'order_id': orderId}).toString();
