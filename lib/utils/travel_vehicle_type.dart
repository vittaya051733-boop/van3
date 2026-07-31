import 'package:flutter/material.dart';

enum TravelVehicleType { motorcycle, sedan, pickup }

extension TravelVehicleTypePresentation on TravelVehicleType {
  IconData get icon {
    switch (this) {
      case TravelVehicleType.motorcycle:
        return Icons.two_wheeler;
      case TravelVehicleType.sedan:
        return Icons.directions_car_filled_rounded;
      case TravelVehicleType.pickup:
        return Icons.local_shipping_rounded;
    }
  }

  IconData get mapMarkerIcon {
    switch (this) {
      case TravelVehicleType.motorcycle:
        return Icons.moped;
      case TravelVehicleType.sedan:
        return Icons.directions_car_filled_rounded;
      case TravelVehicleType.pickup:
        return Icons.local_shipping_rounded;
    }
  }

  String get label {
    switch (this) {
      case TravelVehicleType.motorcycle:
        return 'มอเตอร์ไซค์';
      case TravelVehicleType.sedan:
        return 'รถเก๋ง';
      case TravelVehicleType.pickup:
        return 'รถกระบะ';
    }
  }

  Color get accentColor {
    switch (this) {
      case TravelVehicleType.motorcycle:
        return const Color(0xFF16A34A);
      case TravelVehicleType.sedan:
        return const Color(0xFF2563EB);
      case TravelVehicleType.pickup:
        return const Color(0xFFB45309);
    }
  }

  Color get avatarBackgroundColor {
    switch (this) {
      case TravelVehicleType.motorcycle:
        return const Color(0xFFDCFCE7);
      case TravelVehicleType.sedan:
        return const Color(0xFFDBEAFE);
      case TravelVehicleType.pickup:
        return const Color(0xFFFFEDD5);
    }
  }
}

TravelVehicleType readTravelVehicleTypeFromOrder(Map<String, dynamic> data) {
  final candidates = <String?>[];

  final travelRequest = data['travelRequest'];
  if (travelRequest is Map) {
    candidates.add(travelRequest['vehicleType']?.toString());
    candidates.add(travelRequest['vehicleTypeLabel']?.toString());
  }

  candidates.add(data['vehicleType']?.toString());
  candidates.add(data['vehicleTypeLabel']?.toString());

  for (final raw in candidates) {
    final parsed = _parseTravelVehicleType(raw);
    if (parsed != null) {
      return parsed;
    }
  }

  return TravelVehicleType.motorcycle;
}

TravelVehicleType? _parseTravelVehicleType(String? rawValue) {
  final normalized = rawValue?.trim().toLowerCase() ?? '';
  if (normalized.isEmpty) {
    return null;
  }

  if (normalized.contains('motor') ||
      normalized.contains('bike') ||
      normalized.contains('motorcycle') ||
      normalized.contains('มอเตอร์')) {
    return TravelVehicleType.motorcycle;
  }

  if (normalized.contains('pickup') ||
      normalized.contains('truck') ||
      normalized.contains('กระบะ')) {
    return TravelVehicleType.pickup;
  }

  if (normalized.contains('sedan') ||
      normalized.contains('car') ||
      normalized.contains('เก๋ง')) {
    return TravelVehicleType.sedan;
  }

  switch (normalized) {
    case 'motorcycle':
    case 'bike':
    case 'motorbike':
      return TravelVehicleType.motorcycle;
    case 'sedan':
      return TravelVehicleType.sedan;
    case 'pickup':
      return TravelVehicleType.pickup;
  }

  return null;
}
