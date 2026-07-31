import 'package:flutter/material.dart';

import '../utils/travel_vehicle_type.dart';

class TravelOrderAvatar extends StatelessWidget {
  const TravelOrderAvatar({
    super.key,
    required this.vehicleType,
    this.size = 52,
    this.borderRadius = 14,
  });

  final TravelVehicleType vehicleType;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final iconSize = size * 0.52;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: vehicleType.avatarBackgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        vehicleType.icon,
        size: iconSize,
        color: vehicleType.accentColor,
      ),
    );
  }
}
