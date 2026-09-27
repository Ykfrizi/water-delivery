import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:smart_sachet_water_distribution/core/config/maps_config.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_location_parser.dart';

/// Compact customer pin so vendors can see where to deliver before approving.
class OrderLocationPreview extends StatefulWidget {
  const OrderLocationPreview({
    super.key,
    required this.order,
    this.height = 168,
  });

  final Map<String, dynamic> order;
  final double height;

  @override
  State<OrderLocationPreview> createState() => _OrderLocationPreviewState();
}

class _OrderLocationPreviewState extends State<OrderLocationPreview> {
  MapType _mapType = MapType.normal;

  bool get _isSatellite =>
      _mapType == MapType.satellite || _mapType == MapType.hybrid;

  String get _caption {
    final customer = widget.order['customer'];
    if (customer is Map && customer['last_located_at'] != null) {
      return 'Live customer GPS';
    }
    return 'Customer location';
  }

  @override
  Widget build(BuildContext context) {
    final coords = parseCoordinates(widget.order);
    if (coords == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.amber.shade200),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_off_outlined, color: Color(0xFFF9A825)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No customer pin yet. Ask them to keep the app open with location on — you will see them here before you approve.',
                style: TextStyle(height: 1.35, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final pin = LatLng(coords.lat, coords.lng);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.place_rounded, size: 18, color: Color(0xFF1565C0)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _caption,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _mapType = _isSatellite ? MapType.normal : MapType.hybrid;
                });
              },
              icon: Icon(
                _isSatellite
                    ? Icons.map_rounded
                    : Icons.satellite_alt_rounded,
                size: 18,
              ),
              label: Text(_isSatellite ? 'Street' : 'Satellite'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: MapsConfig.isConfigured
                ? GoogleMap(
                    key: ValueKey(
                      '${coords.lat.toStringAsFixed(4)},'
                      '${coords.lng.toStringAsFixed(4)},$_mapType',
                    ),
                    initialCameraPosition: CameraPosition(
                      target: pin,
                      zoom: 15.2,
                    ),
                    mapType: _mapType,
                    markers: {
                      Marker(
                        markerId: const MarkerId('customer'),
                        position: pin,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueAzure,
                        ),
                        infoWindow: const InfoWindow(title: 'Customer'),
                      ),
                    },
                    liteModeEnabled: false,
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    scrollGesturesEnabled: true,
                    zoomGesturesEnabled: true,
                  )
                : ColoredBox(
                    color: const Color(0xFFE3F2FD),
                    child: Center(
                      child: Text(
                        'Customer pin: ${coords.lat.toStringAsFixed(5)}, '
                        '${coords.lng.toStringAsFixed(5)}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
