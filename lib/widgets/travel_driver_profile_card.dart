import 'package:flutter/material.dart';

import '../models/rider_vehicle_profile.dart';

/// Driver summary row shared by travel tracking and customer order cards.
class TravelDriverProfileCard extends StatelessWidget {
  const TravelDriverProfileCard({
    super.key,
    required this.rider,
    this.rating,
    this.showSectionLabel = true,
    this.etaMinutes,
    this.etaTargetLabel = 'จุดรับ',
  });

  final RiderVehicleProfile rider;
  final double? rating;
  final bool showSectionLabel;
  final int? etaMinutes;
  final String etaTargetLabel;

  @override
  Widget build(BuildContext context) {
    final resolvedRating = rating ?? rider.rating ?? 5.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFFE5E7EB),
                backgroundImage: rider.profilePhotoUrl != null
                    ? NetworkImage(rider.profilePhotoUrl!)
                    : null,
                child: rider.profilePhotoUrl == null
                    ? Text(
                        rider.displayName.trim().isNotEmpty
                            ? rider.displayName
                                .trim()
                                .substring(0, 1)
                                .toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      )
                    : null,
              ),
              if (rider.isElectricVehicle)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.bolt,
                      size: 14,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (showSectionLabel)
                  Text(
                    'รายละเอียดคนขับ',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: const Color(0xFF6B7280),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                if (showSectionLabel) const SizedBox(height: 4),
                if (rider.licensePlate?.isNotEmpty == true)
                  Text(
                    rider.licensePlate!,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                  ),
                Text(
                  rider.vehicleSummary,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF4B5563),
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: <Widget>[
                    Text(
                      rider.displayName,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.star,
                      size: 16,
                      color: Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      resolvedRating.toStringAsFixed(1),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
                if (etaMinutes != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
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
                            _formatEtaLine(etaMinutes!, etaTargetLabel),
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
        ],
      ),
    );
  }

  String _formatEtaLine(int minutes, String targetLabel) {
    final arrival = DateTime.now().add(Duration(minutes: minutes));
    final hour = arrival.hour.toString().padLeft(2, '0');
    final minute = arrival.minute.toString().padLeft(2, '0');
    return 'ถึง$targetLabelประมาณ $minutes นาที (โดยประมาณ $hour:$minute น.)';
  }
}
