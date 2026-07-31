import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'services/rider_order_actions.dart';
import 'utils/driving_route_service.dart';
import 'utils/travel_vehicle_map_marker.dart';
import 'utils/travel_vehicle_type.dart';

enum RiderTravelMapLeg { pickup, destination }

void showRiderTravelRouteMap({
  required BuildContext context,
  required Map<String, dynamic> orderData,
  required RiderTravelMapLeg leg,
}) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => TravelRouteMapScreen(
        orderData: orderData,
        leg: leg,
      ),
    ),
  );
}

class TravelRouteMapScreen extends StatefulWidget {
  const TravelRouteMapScreen({
    super.key,
    required this.orderData,
    required this.leg,
  });

  final Map<String, dynamic> orderData;
  final RiderTravelMapLeg leg;

  @override
  State<TravelRouteMapScreen> createState() => _TravelRouteMapScreenState();
}

class _TravelRouteMapScreenState extends State<TravelRouteMapScreen> {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _riderDocSubscription;

  LatLng? _riderPosition;
  List<LatLng> _routePoints = const <LatLng>[];
  int? _etaMinutes;
  bool _isLoadingRoute = false;
  BitmapDescriptor? _vehicleMarkerIcon;
  int _routeRequestId = 0;
  DateTime? _lastRouteFetchAt;

  static const Color _routeLineColor = Color(0xFFDC2626);
  static const Duration _routeRefreshInterval = Duration(minutes: 1);

  TravelVehicleType get _vehicleType =>
      readTravelVehicleTypeFromOrder(widget.orderData);

  @override
  void initState() {
    super.initState();
    unawaited(_ensureVehicleMarkerIcon());
    _startRiderLocationTracking();
    unawaited(_refreshRoute(force: true));
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _riderDocSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _ensureVehicleMarkerIcon() async {
    final icon = await travelVehicleMapMarker(_vehicleType);
    if (!mounted) {
      return;
    }
    setState(() => _vehicleMarkerIcon = icon);
  }

  void _startRiderLocationTracking() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      _riderDocSubscription = FirebaseFirestore.instance
          .collection('riders')
          .doc(uid)
          .snapshots()
          .listen((snapshot) {
        final data = snapshot.data();
        if (data == null) {
          return;
        }
        final geo = data['currentLocation'];
        if (geo is GeoPoint) {
          _updateRiderPosition(LatLng(geo.latitude, geo.longitude));
        }
      });
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 40,
      ),
    ).listen((position) {
      _updateRiderPosition(LatLng(position.latitude, position.longitude));
    });
  }

  void _updateRiderPosition(LatLng position) {
    if (!mounted) {
      return;
    }
    setState(() => _riderPosition = position);
    _maybeRefreshRoute();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_fitMapBounds());
    });
  }

  LatLng? _readPickupLatLng() {
    final travelRequest = widget.orderData['travelRequest'];
    if (travelRequest is Map) {
      final pickup = travelRequest['pickup'];
      if (pickup is Map) {
        final lat = _toDouble(pickup['latitude']) ?? _toDouble(pickup['lat']);
        final lng =
            _toDouble(pickup['longitude']) ?? _toDouble(pickup['lng']);
        if (lat != null && lng != null) {
          return LatLng(lat, lng);
        }
      }
    }

    final lat = _toDouble(widget.orderData['shopLatitude']);
    final lng = _toDouble(widget.orderData['shopLongitude']);
    if (lat == null || lng == null) {
      return null;
    }
    return LatLng(lat, lng);
  }

  LatLng? _readDestinationLatLng() {
    final coords =
        RiderOrderActions.instance.readDestinationCoordinates(widget.orderData);
    if (coords == null) {
      return null;
    }
    return LatLng(coords['lat']!, coords['lng']!);
  }

  ({LatLng origin, LatLng destination, String etaTargetLabel})? _routeEndpoints() {
    final pickup = _readPickupLatLng();
    final destination = _readDestinationLatLng();
    final rider = _riderPosition;

    switch (widget.leg) {
      case RiderTravelMapLeg.pickup:
        if (pickup == null) {
          return null;
        }
        final origin = rider ?? pickup;
        return (
          origin: origin,
          destination: pickup,
          etaTargetLabel: 'จุดรับ',
        );
      case RiderTravelMapLeg.destination:
        if (pickup == null || destination == null) {
          return null;
        }
        return (
          origin: pickup,
          destination: destination,
          etaTargetLabel: 'ปลายทาง',
        );
    }
  }

  void _maybeRefreshRoute({bool force = false}) {
    final endpoints = _routeEndpoints();
    if (endpoints == null) {
      return;
    }

    final lastFetch = _lastRouteFetchAt;
    if (!force &&
        lastFetch != null &&
        DateTime.now().difference(lastFetch) < _routeRefreshInterval) {
      return;
    }

    _lastRouteFetchAt = DateTime.now();
    unawaited(_refreshRoute(force: true));

    if (widget.leg == RiderTravelMapLeg.destination && _riderPosition != null) {
      unawaited(_refreshEtaToDestination());
    }
  }

  Future<void> _refreshRoute({bool force = false}) async {
    if (!force) {
      return;
    }

    final endpoints = _routeEndpoints();
    if (endpoints == null) {
      return;
    }

    final requestId = ++_routeRequestId;
    setState(() => _isLoadingRoute = true);
    final result = await DrivingRouteService.fetchDrivingRoute(
      originLat: endpoints.origin.latitude,
      originLng: endpoints.origin.longitude,
      destinationLat: endpoints.destination.latitude,
      destinationLng: endpoints.destination.longitude,
    );

    if (!mounted || requestId != _routeRequestId) {
      return;
    }

    setState(() {
      _isLoadingRoute = false;
      _routePoints = result?.points ??
          <LatLng>[endpoints.origin, endpoints.destination];
      if (widget.leg == RiderTravelMapLeg.pickup &&
          result != null &&
          result.durationSeconds > 0) {
        _etaMinutes = (result.durationSeconds / 60).ceil().clamp(1, 240);
      }
    });
    await _fitMapBounds();
  }

  Future<void> _refreshEtaToDestination() async {
    final destination = _readDestinationLatLng();
    final rider = _riderPosition;
    if (destination == null || rider == null) {
      return;
    }

    final result = await DrivingRouteService.fetchDrivingRoute(
      originLat: rider.latitude,
      originLng: rider.longitude,
      destinationLat: destination.latitude,
      destinationLng: destination.longitude,
    );
    if (!mounted || result == null || result.durationSeconds <= 0) {
      return;
    }

    setState(() {
      _etaMinutes = (result.durationSeconds / 60).ceil().clamp(1, 240);
    });
  }

  double? _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  Future<void> _fitMapBounds() async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    final points = <LatLng>[
      if (_readPickupLatLng() case final pickup?) pickup,
      if (_readDestinationLatLng() case final destination?) destination,
      if (_riderPosition case final rider?) rider,
      ..._routePoints,
    ];
    if (points.isEmpty) {
      return;
    }
    if (points.length == 1) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 14),
      );
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        100,
      ),
    );
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    final pickup = _readPickupLatLng();
    if (pickup != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'จุดรับ'),
        ),
      );
    }

    final destination = _readDestinationLatLng();
    if (destination != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: destination,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'ปลายทาง'),
        ),
      );
    }

    final rider = _riderPosition;
    if (rider != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('rider'),
          position: rider,
          icon: _vehicleMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          anchor: const Offset(0.5, 1.0),
          infoWindow: InfoWindow(
            title: 'ตำแหน่งของคุณ',
            snippet: _vehicleType.label,
          ),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> _buildPolylines() {
    if (_routePoints.length < 2) {
      return const <Polyline>{};
    }

    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('route_outline'),
        points: _routePoints,
        color: Colors.white,
        width: 12,
        geodesic: true,
      ),
      Polyline(
        polylineId: const PolylineId('route'),
        points: _routePoints,
        color: _routeLineColor,
        width: 7,
        geodesic: true,
      ),
    };
  }

  String get _title {
    return switch (widget.leg) {
      RiderTravelMapLeg.pickup => 'แผนที่จุดรับ',
      RiderTravelMapLeg.destination => 'แผนที่ปลายทาง',
    };
  }

  String get _subtitle {
    return switch (widget.leg) {
      RiderTravelMapLeg.pickup => 'เส้นทางไปจุดรับผู้โดยสาร',
      RiderTravelMapLeg.destination => 'เส้นทางจากจุดรับไปปลายทาง',
    };
  }

  String? get _etaLine {
    if (_etaMinutes == null) {
      return null;
    }
    final target = widget.leg == RiderTravelMapLeg.pickup ? 'จุดรับ' : 'ปลายทาง';
    final arrival = DateTime.now().add(Duration(minutes: _etaMinutes!));
    final hour = arrival.hour.toString().padLeft(2, '0');
    final minute = arrival.minute.toString().padLeft(2, '0');
    return 'ถึง$targetประมาณ $_etaMinutes นาที (โดยประมาณ $hour:$minute น.)';
  }

  @override
  Widget build(BuildContext context) {
    final initial = _readPickupLatLng() ??
        _readDestinationLatLng() ??
        _riderPosition ??
        const LatLng(13.7563, 100.5018);

    return Scaffold(
      body: Stack(
        children: <Widget>[
          GoogleMap(
            initialCameraPosition: CameraPosition(target: initial, zoom: 14),
            onMapCreated: (controller) {
              _mapController = controller;
              unawaited(_fitMapBounds());
            },
            markers: _buildMarkers(),
            polylines: _buildPolylines(),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 4,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          if (_isLoadingRoute)
            const SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: 64),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text('กำลังอัปเดตเส้นทาง...'),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(16),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        _title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (_etaLine != null) ...<Widget>[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            children: <Widget>[
                              const Icon(
                                Icons.schedule_rounded,
                                size: 18,
                                color: Color(0xFFDC2626),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _etaLine!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: const Color(0xFF991B1B),
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
