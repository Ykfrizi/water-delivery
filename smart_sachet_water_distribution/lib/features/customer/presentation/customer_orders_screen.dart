import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/cache/app_cache.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/pagination/paginated_result.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/data/customer_api.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/customer_order_detail_screen.dart';

/// GET /customer/orders · detail · cancel while pending
class CustomerOrdersScreen extends StatefulWidget {
  const CustomerOrdersScreen({
    super.key,
    this.isActive = true,
  });

  final bool isActive;

  @override
  State<CustomerOrdersScreen> createState() => _CustomerOrdersScreenState();
}

class _CustomerOrdersScreenState extends State<CustomerOrdersScreen> {
  PaginatedResult<Map<String, dynamic>> _page =
      const PaginatedResult(items: []);
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isActive) _load(reset: true);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CustomerOrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _load(reset: true);
    }
  }

  void _onScroll() {
    if (_loadingMore || !_page.hasMore) return;
    if (_scroll.position.pixels >
        _scroll.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  String get _cacheHint =>
      (context.read<AuthController>().session?.token.hashCode ?? 0)
          .toRadixString(16);

  Future<void> _load({bool reset = false}) async {
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    final api = CustomerApi(context.read<Dio>());
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await api.listOrdersPage(token, page: 1, perPage: 20);
      await AppCache.putMapList(AppCache.ordersKey(_cacheHint), page.items);
      if (!mounted) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } on ApiException catch (e) {
      final cached = await AppCache.getMapList(AppCache.ordersKey(_cacheHint));
      if (!mounted) return;
      setState(() {
        if (cached.isNotEmpty) {
          _page = PaginatedResult(items: cached, page: 1, perPage: cached.length);
          _error = null;
        } else {
          _error = e.message;
        }
        _loading = false;
      });
    } catch (e) {
      final cached = await AppCache.getMapList(AppCache.ordersKey(_cacheHint));
      if (!mounted) return;
      setState(() {
        if (cached.isNotEmpty) {
          _page = PaginatedResult(items: cached, page: 1, perPage: cached.length);
        } else {
          _error = e.toString();
        }
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_page.hasMore) return;
    setState(() => _loadingMore = true);
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    final api = CustomerApi(context.read<Dio>());
    try {
      final next = await api.listOrdersPage(
        token,
        page: _page.page + 1,
        perPage: _page.perPage,
      );
      if (!mounted) return;
      setState(() {
        _page = _page.append(next);
        _loadingMore = false;
      });
      await AppCache.putMapList(AppCache.ordersKey(_cacheHint), _page.items);
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String _orderLabel(Map<String, dynamic> o) {
    final n = o['order_number'] ?? o['orderNumber'] ?? o['id'];
    return n == null ? 'Order' : '#$n';
  }

  Future<void> _openDetail(Map<String, dynamic> summary) async {
    final num =
        (summary['order_number'] ?? summary['orderNumber'] ?? summary['id'])
            ?.toString();
    if (num == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerOrderDetailScreen(
          orderNumber: num,
          summaryRow: summary,
        ),
      ),
    );
    if (changed == true && mounted) _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Container(
          decoration: authGradientDecoration(),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BrandHeader(
                  title: 'Orders',
                  subtitle: 'Track deliveries and past purchases',
                  actions: [
                    HeaderIconButton(
                      icon: Icons.refresh_rounded,
                      onPressed:
                          _loading ? null : () => _load(reset: true),
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    decoration: BoxDecoration(
                      color: kCustomerGray,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(_error!, textAlign: TextAlign.center),
                                        const SizedBox(height: 12),
                                        FilledButton(
                                          onPressed: () => _load(reset: true),
                                          child: const Text('Retry'),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: () => _load(reset: true),
                                  child: ListView.builder(
                                    controller: _scroll,
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.all(12),
                                    itemCount: _page.items.length +
                                        (_loadingMore || _page.hasMore ? 1 : 0),
                                    itemBuilder: (context, i) {
                                      if (i >= _page.items.length) {
                                        return const Padding(
                                          padding: EdgeInsets.all(16),
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        );
                                      }
                                      final o = _page.items[i];
                                      final status =
                                          o['status']?.toString() ?? '—';
                                      final highlighted = i == 0;
                                      final fg = highlighted
                                          ? Colors.white
                                          : const Color(0xFF000000);
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: Material(
                                          color: highlighted
                                              ? kCustomerBlue
                                              : kCustomerGray,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          child: ListTile(
                                            title: Text(
                                              _orderLabel(o),
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: fg,
                                              ),
                                            ),
                                            subtitle: Text(
                                              status,
                                              style: TextStyle(
                                                color: highlighted
                                                    ? Colors.white
                                                        .withValues(alpha: 0.85)
                                                    : Colors.black54,
                                              ),
                                            ),
                                            trailing: Icon(
                                              Icons.chevron_right_rounded,
                                              color: highlighted
                                                  ? Colors.white
                                                  : const Color(0xFF424242),
                                            ),
                                            onTap: () => _openDetail(o),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}
