import 'package:flutter/material.dart';

import '../services/rider_availability_service.dart';
import '../travel_vehicle_type.dart';
import '../utils/rider_pool_filters.dart';

enum OnlineRiderSliderMode { delivery, travel }

/// Horizontal slider of online riders from [system/rider_availability].
class OnlineRiderSlider extends StatelessWidget {
  const OnlineRiderSlider({
    super.key,
    required this.mode,
    this.referenceLatitude,
    this.referenceLongitude,
    this.vehicleType,
    this.title,
  });

  final OnlineRiderSliderMode mode;
  final double? referenceLatitude;
  final double? referenceLongitude;
  final TravelVehicleType? vehicleType;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final stream = mode == OnlineRiderSliderMode.delivery
        ? RiderAvailabilityService.instance.watchDeliveryRiderEntries()
        : RiderAvailabilityService.instance.watchTravelRiderEntries();

    return StreamBuilder<List<RiderAvailabilityEntry>>(
      stream: stream,
      initialData: mode == OnlineRiderSliderMode.delivery
          ? RiderAvailabilityService.instance.peekDeliveryRiderEntries
          : RiderAvailabilityService.instance.peekTravelRiderEntries,
      builder: (context, snapshot) {
        final hasError = snapshot.hasError;
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;

        final items = _buildItems(snapshot.data ?? const []);
        final headerTitle = title ?? _defaultTitle(items.length);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    mode == OnlineRiderSliderMode.delivery
                        ? Icons.delivery_dining
                        : Icons.directions_car_filled_rounded,
                    size: 18,
                    color: hasError
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF16A34A),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasError
                          ? 'สถานะไรเดอร์ไม่พร้อมใช้งาน'
                          : isLoading
                          ? 'กำลังโหลดไรเดอร์ออนไลน์...'
                          : headerTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'อัปเดตสด',
                      style: TextStyle(
                        color: Color(0xFF166534),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (hasError)
                Text(
                  'เช็กการเชื่อมต่อหรือสิทธิ์อ่าน system/rider_availability',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                )
              else if (isLoading)
                const _RiderSliderSkeleton()
              else if (items.isEmpty)
                Text(
                  mode == OnlineRiderSliderMode.delivery
                      ? 'ยังไม่มีไรเดอร์ออนไลน์รับส่งของ'
                      : 'ยังไม่มีรถประเภทนี้ออนไลน์',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                )
              else
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      return _RiderSliderCard(item: items[index]);
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _defaultTitle(int count) {
    if (mode == OnlineRiderSliderMode.delivery) {
      return count > 0
          ? 'ไรเดอร์ออนไลน์ $count คน'
          : 'ยังไม่มีไรเดอร์ออนไลน์';
    }
    final vehicleLabel = vehicleType?.label ?? 'รถ';
    return count > 0
        ? '$vehicleLabel ออนไลน์ $count คัน'
        : 'ยังไม่มี$vehicleLabelออนไลน์';
  }

  List<RiderSliderItem> _buildItems(List<RiderAvailabilityEntry> entries) {
    if (mode == OnlineRiderSliderMode.delivery) {
      return buildDeliverySliderItems(
        entries: entries,
        referenceLatitude: referenceLatitude,
        referenceLongitude: referenceLongitude,
      );
    }

    final selectedVehicle = vehicleType ?? TravelVehicleType.motorcycle;
    return buildTravelSliderItems(
      entries: entries,
      vehicleType: selectedVehicle,
      referenceLatitude: referenceLatitude,
      referenceLongitude: referenceLongitude,
    );
  }
}

/// Compact single-rider strip for cart (saves vertical space).
class OnlineRiderCartCompact extends StatelessWidget {
  const OnlineRiderCartCompact({
    super.key,
    this.referenceLatitude,
    this.referenceLongitude,
  });

  final double? referenceLatitude;
  final double? referenceLongitude;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RiderAvailabilityEntry>>(
      stream: RiderAvailabilityService.instance.watchDeliveryRiderEntries(),
      initialData: RiderAvailabilityService.instance.peekDeliveryRiderEntries,
      builder: (context, snapshot) {
        final hasError = snapshot.hasError;
        final isLoading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;

        final items = buildDeliverySliderItems(
          entries: snapshot.data ?? const [],
          referenceLatitude: referenceLatitude,
          referenceLongitude: referenceLongitude,
        );
        final onlineCount = items.length;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: onlineCount > 0
                  ? const Color(0xFFBBF7D0)
                  : const Color(0xFFE5E7EB),
            ),
          ),
          child: _buildMessage(
            context,
            hasError: hasError,
            isLoading: isLoading,
            onlineCount: onlineCount,
          ),
        );
      },
    );
  }

  Widget _buildMessage(
    BuildContext context, {
    required bool hasError,
    required bool isLoading,
    required int onlineCount,
  }) {
    if (hasError) {
      return Text(
        'สถานะไรเดอร์ไม่พร้อมใช้งาน',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFFDC2626),
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (isLoading) {
      return Text(
        'กำลังตรวจสอบไรเดอร์...',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF6B7280),
          fontWeight: FontWeight.w600,
        ),
      );
    }
    if (onlineCount <= 0) {
      return Text(
        'ยังไม่มีไรเดอร์ออนไลน์',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF6B7280),
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Row(
      children: <Widget>[
        Icon(
          Icons.delivery_dining,
          size: 14,
          color: const Color(0xFF16A34A),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'ไรเดอร์ออนไลน์ $onlineCount คน',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFF111827),
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _RiderSliderCard extends StatelessWidget {
  const _RiderSliderCard({required this.item});

  final RiderSliderItem item;

  @override
  Widget build(BuildContext context) {
    final data = item.entry.data;
    final displayName = readRiderDisplayLabel(data);
    final vehicleLabel = readRiderVehicleLabel(data);
    final profileImageUrl = (data['profileImageUrl'] as String?)?.trim();
    final rating = data['rating'];
    final ratingLabel = rating is num ? rating.toStringAsFixed(1) : null;

    return Container(
      width: 168,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _RiderAvatar(imageUrl: profileImageUrl),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF111827),
                      ),
                    ),
                    if (vehicleLabel != null)
                      Text(
                        vehicleLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'ออนไลน์',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF16A34A),
                ),
              ),
              const Spacer(),
              if (ratingLabel != null) ...<Widget>[
                const Icon(Icons.star_rounded, size: 12, color: Color(0xFFF59E0B)),
                const SizedBox(width: 2),
                Text(
                  ratingLabel,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF92400E),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                formatDistanceKm(item.distanceKm),
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RiderAvatar extends StatelessWidget {
  const _RiderAvatar({this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    return CircleAvatar(
      radius: 16,
      backgroundColor: const Color(0xFFDCFCE7),
      backgroundImage: url != null && url.isNotEmpty ? NetworkImage(url) : null,
      child: url == null || url.isEmpty
          ? const Icon(Icons.person, size: 16, color: Color(0xFF16A34A))
          : null,
    );
  }
}

class _RiderSliderSkeleton extends StatelessWidget {
  const _RiderSliderSkeleton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return Container(
            width: 168,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
          );
        },
      ),
    );
  }
}
