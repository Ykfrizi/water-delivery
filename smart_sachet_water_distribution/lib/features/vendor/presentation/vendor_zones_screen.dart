import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/location/device_location_service.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/service_area.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_api.dart';

/// CRUD /vendor/delivery-zones
class VendorZonesScreen extends StatefulWidget {
  const VendorZonesScreen({super.key});

  @override
  State<VendorZonesScreen> createState() => _VendorZonesScreenState();
}

class _VendorZonesScreenState extends State<VendorZonesScreen> {
  List<Map<String, dynamic>> _zones = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    final api = VendorApi(context.read<Dio>());
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await api.listZones(token);
      if (!mounted) return;
      setState(() {
        _zones = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _zoneTitle(Map<String, dynamic> z) {
    return z['name']?.toString() ??
        z['label']?.toString() ??
        'Zone ${z['id'] ?? ''}';
  }

  String _zoneSubtitle(Map<String, dynamic> z) {
    final lat = z['latitude'] ?? z['lat'];
    final lng = z['longitude'] ?? z['lng'];
    final r = z['radius_km'] ?? z['radius'];
    return '${lat ?? '—'}, ${lng ?? '—'} · ${r ?? '—'} km';
  }

  Future<void> _upsert({Map<String, dynamic>? existing}) async {
    final nameCtrl = TextEditingController(
      text: existing?['name']?.toString() ?? 'Ho',
    );
    final latCtrl = TextEditingController(
      text:
          (existing?['latitude'] ?? existing?['lat'])?.toString() ??
          ServiceArea.center.latitude.toString(),
    );
    final lngCtrl = TextEditingController(
      text:
          (existing?['longitude'] ?? existing?['lng'])?.toString() ??
          ServiceArea.center.longitude.toString(),
    );
    final radiusCtrl = TextEditingController(
      text:
          (existing?['radius_km'] ?? existing?['radius'])?.toString() ??
          ServiceArea.radiusKm.toString(),
    );
    var locating = false;

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(existing == null ? 'New zone' : 'Edit zone'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Label'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: locating
                        ? null
                        : () async {
                            setDialogState(() => locating = true);
                            final pos = await const DeviceLocationService()
                                .getPositionOrExplain(context);
                            if (pos != null) {
                              latCtrl.text = pos.latitudeLabel;
                              lngCtrl.text = pos.longitudeLabel;
                              if (radiusCtrl.text.trim().isEmpty) {
                                radiusCtrl.text = '5';
                              }
                            }
                            if (context.mounted) {
                              setDialogState(() => locating = false);
                            }
                          },
                    icon: locating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded),
                    label: Text(locating ? 'Reading GPS…' : 'Use my location'),
                  ),
                  TextField(
                    controller: latCtrl,
                    decoration: const InputDecoration(labelText: 'Latitude'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                  TextField(
                    controller: lngCtrl,
                    decoration: const InputDecoration(labelText: 'Longitude'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                  TextField(
                    controller: radiusCtrl,
                    decoration: const InputDecoration(labelText: 'Radius (km)'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    void disposeCtrls() {
      nameCtrl.dispose();
      latCtrl.dispose();
      lngCtrl.dispose();
      radiusCtrl.dispose();
    }

    if (ok != true) {
      disposeCtrls();
      return;
    }

    final name = nameCtrl.text.trim();
    final lat = latCtrl.text.trim();
    final lng = lngCtrl.text.trim();
    final rad = radiusCtrl.text.trim();
    disposeCtrls();

    final body = <String, dynamic>{
      if (name.isNotEmpty) 'name': name,
      if (lat.isNotEmpty) 'latitude': double.tryParse(lat),
      if (lng.isNotEmpty) 'longitude': double.tryParse(lng),
      if (rad.isNotEmpty) 'radius_km': double.tryParse(rad),
    };

    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    final api = VendorApi(context.read<Dio>());

    try {
      if (existing == null) {
        await api.createZone(token, body);
      } else {
        final id = existing['id'];
        if (id == null) {
          if (mounted) showErrorSnackBar(context, 'Missing zone id from API.');
          return;
        }
        await api.updateZone(token, id, body);
      }
      if (mounted) await _load();
    } on ApiException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => AlertDialog(
        title: const Text('Delete zone?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    try {
      await VendorApi(context.read<Dio>()).deleteZone(token, id);
      if (mounted) await _load();
    } on ApiException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = vendorAppTheme();
    final accent = roleAccent(UserRole.vendor);

    return Theme(
      data: theme,
      child: Container(
        decoration: roleGradientDecoration(UserRole.vendor),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BrandHeader(
                title: 'Delivery zones',
                subtitle: 'Where you deliver',
                actions: [
                  HeaderIconButton(
                    icon: Icons.add_rounded,
                    onPressed: () => _upsert(),
                    tooltip: 'Add zone',
                  ),
                ],
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EAF6),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_error!),
                                  FilledButton(
                                    onPressed: _load,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            color: accent,
                            onRefresh: _load,
                            child: _zones.isEmpty
                                ? ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    children: const [
                                      SizedBox(height: 80),
                                      Center(child: Text('No zones yet')),
                                    ],
                                  )
                                : ListView.builder(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.all(14),
                                    itemCount: _zones.length,
                                    itemBuilder: (context, i) {
                                      final z = _zones[i];
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: Material(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          elevation: 2,
                                          child: ListTile(
                                            title: Text(
                                              _zoneTitle(z),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            subtitle: Text(_zoneSubtitle(z)),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.edit_outlined,
                                                  ),
                                                  onPressed: () =>
                                                      _upsert(existing: z),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                  ),
                                                  onPressed: () => _delete(z),
                                                ),
                                              ],
                                            ),
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
