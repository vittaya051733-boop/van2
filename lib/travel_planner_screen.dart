import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cart_screen.dart';
import 'map_picker_screen.dart';
import 'travel_payment_flow.dart';

class TravelPlannerResult {
  const TravelPlannerResult({
    required this.pickup,
    required this.destination,
    required this.rideSelection,
    required this.distanceKm,
  });

  final PickedLocation pickup;
  final PickedLocation destination;
  final TravelRideSelection rideSelection;
  final double distanceKm;
}

enum TravelVehicleType { motorcycle, sedan, pickup }

extension TravelVehicleTypePresentation on TravelVehicleType {
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
}

class TravelRideSelection {
  const TravelRideSelection({
    required this.vehicleType,
    required this.scheduledAt,
    required this.isImmediate,
  });

  final TravelVehicleType vehicleType;
  final DateTime scheduledAt;
  final bool isImmediate;

  String get scheduleLabel {
    if (isImmediate) {
      return 'ให้รถออกตอนนี้';
    }

    final day = scheduledAt.day.toString().padLeft(2, '0');
    final month = scheduledAt.month.toString().padLeft(2, '0');
    final year = scheduledAt.year.toString();
    final hour = scheduledAt.hour.toString().padLeft(2, '0');
    final minute = scheduledAt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute น.';
  }
}

class TravelPlannerScreen extends StatefulWidget {
  const TravelPlannerScreen({
    super.key,
    required this.initialPickup,
    required this.initialDestination,
    this.initialRideSelection,
    this.onConfirmCashOnDelivery,
    this.onSubmitPromptPaySlip,
    this.onOpenOrderRoadmap,
  });

  final PickedLocation initialPickup;
  final PickedLocation initialDestination;
  final TravelRideSelection? initialRideSelection;
  final Future<List<String>> Function(TravelPlannerResult request)? onConfirmCashOnDelivery;
  final Future<PaymentSlipSubmissionResult> Function(
    TravelPlannerResult request,
    PaymentSlipSubmissionRequest slipRequest,
  )? onSubmitPromptPaySlip;
  final Future<void> Function(List<String> orderIds)? onOpenOrderRoadmap;

  @override
  State<TravelPlannerScreen> createState() => _TravelPlannerScreenState();
}

class _TravelPlannerScreenState extends State<TravelPlannerScreen> {
  late PickedLocation _pickup;
  late PickedLocation _destination;
  TravelRideSelection? _rideSelection;
  late bool _locationsConfirmed;

  @override
  void initState() {
    super.initState();
    _pickup = widget.initialPickup;
    _destination = widget.initialDestination;
    _rideSelection = widget.initialRideSelection;
    _locationsConfirmed = widget.initialRideSelection != null;
  }

  double get _distanceKm {
    final meters = Geolocator.distanceBetween(
      _pickup.latitude,
      _pickup.longitude,
      _destination.latitude,
      _destination.longitude,
    );
    return meters / 1000;
  }

  double get _estimatedFare {
    final billableKm = _distanceKm < 1 ? 1.0 : _distanceKm;
    final fee = 25 + ((billableKm - 1) * 12.5);
    return double.parse(fee.toStringAsFixed(2));
  }

  String _formatLocationLabel(PickedLocation location) {
    final subtitle = location.subtitle?.trim();
    if (subtitle == null || subtitle.isEmpty || subtitle == location.title) {
      return location.title;
    }
    return '${location.title} - $subtitle';
  }

  Future<PickedLocation?> _pickTravelLocation({
    required String title,
    required String confirmLabel,
    required PickedLocation initialLocation,
  }) {
    return Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute<PickedLocation>(
        builder: (context) => MapPickerScreen(
          title: title,
          confirmLabel: confirmLabel,
          initialLocation: initialLocation,
        ),
      ),
    );
  }

  Future<void> _pickPickup() async {
    final selected = await _pickTravelLocation(
      title: 'กำหนดจุดรับผู้โดยสาร',
      confirmLabel: 'ใช้เป็นจุดรับ',
      initialLocation: _pickup,
    );

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      _pickup = selected;
      _locationsConfirmed = false;
    });
  }

  Future<void> _pickDestination() async {
    final selected = await _pickTravelLocation(
      title: 'กำหนดจุดส่งผู้โดยสาร',
      confirmLabel: 'ใช้เป็นจุดส่ง',
      initialLocation: _destination,
    );

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      _destination = selected;
      _locationsConfirmed = false;
    });
  }

  Future<void> _confirmLocations() async {
    FocusScope.of(context).unfocus();
    setState(() => _locationsConfirmed = true);
    await _configureRide();
  }

  Future<void> _configureRide() async {
    final rideSelection = await showModalBottomSheet<TravelRideSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _TravelRideSetupSheet(initialSelection: _rideSelection);
      },
    );

    if (!mounted || rideSelection == null) {
      return;
    }

    setState(() => _rideSelection = rideSelection);
  }

  TravelPlannerResult _buildSubmissionResult() {
    final rideSelection = _rideSelection!;
    return TravelPlannerResult(
      pickup: _pickup,
      destination: _destination,
      rideSelection: rideSelection,
      distanceKm: _distanceKm,
    );
  }

  Future<void> _completeOrder(List<String> orderIds) async {
    if (orderIds.isEmpty) {
      return;
    }

    if (widget.onOpenOrderRoadmap != null) {
      await widget.onOpenOrderRoadmap!(orderIds);
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(_buildSubmissionResult());
  }

  Future<void> _submit() async {
    final rideSelection = _rideSelection;
    if (rideSelection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกเวลาและประเภทรถก่อน')),
      );
      return;
    }

    await showTravelPaymentFlow(
      context: context,
      grandTotal: _estimatedFare,
      pickupLabel: _formatLocationLabel(_pickup),
      destinationLabel: _formatLocationLabel(_destination),
      distanceKm: _distanceKm,
      vehicleTypeLabel: rideSelection.vehicleType.label,
      scheduleLabel: rideSelection.scheduleLabel,
      onConfirmCashOnDelivery: widget.onConfirmCashOnDelivery == null
          ? null
          : () => widget.onConfirmCashOnDelivery!(_buildSubmissionResult()),
      onSubmitPromptPaySlip: widget.onSubmitPromptPaySlip == null
          ? null
          : (slipRequest) =>
              widget.onSubmitPromptPaySlip!(_buildSubmissionResult(), slipRequest),
      onOrderCompleted: _completeOrder,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF6),
      appBar: AppBar(
        title: const Text('ตั้งค่าการเดินทาง'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _locationsConfirmed
                        ? 'ขั้นตอนที่ 2 เลือกรถและเวลา'
                        : 'ขั้นตอนที่ 1 ยืนยันจุดรับส่งผู้โดยสาร',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _locationsConfirmed
                        ? 'เมื่อยืนยันจุดรับส่งแล้ว ค่อยเลือกเวลาและประเภทรถในขั้นถัดไป'
                        : 'กำหนดจุดรับและจุดส่งให้เรียบร้อยก่อน แล้วระบบจะแสดงขั้นเลือกรถและเวลา',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _TravelLocationCard(
              title: 'จุดรับผู้โดยสาร',
              icon: Icons.my_location_outlined,
              location: _pickup,
              actionLabel: 'เลือกจุดรับ',
              onTap: _pickPickup,
            ),
            const SizedBox(height: 12),
            _TravelLocationCard(
              title: 'จุดส่งผู้โดยสาร',
              icon: Icons.location_on_outlined,
              location: _destination,
              actionLabel: 'เลือกจุดส่ง',
              onTap: _pickDestination,
            ),
            const SizedBox(height: 16),
            TravelSummaryCard(
              pickup: _pickup,
              destination: _destination,
              distanceKm: _distanceKm,
              rideSelection: _locationsConfirmed ? _rideSelection : null,
            ),
            const SizedBox(height: 16),
            if (!_locationsConfirmed) ...<Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: Text(
                  'ยืนยันจุดรับและจุดส่งก่อน ระบบจึงจะแสดงตัวเลือกประเภทรถและเวลาให้ตามลำดับ',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF9A3412),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ] else ...<Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Text(
                  'ขั้นต่อไป เลือกเวลาเดินทางและประเภทรถที่ต้องการ',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF166534),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _configureRide,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF57C00),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: const Icon(Icons.tune_rounded),
                label: Text(
                  _rideSelection == null
                      ? 'เลือกเวลาและประเภทรถ'
                      : 'แก้ไขเวลาและประเภทรถ',
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _locationsConfirmed ? _submit : _confirmLocations,
            style: FilledButton.styleFrom(
              backgroundColor: _locationsConfirmed
                  ? const Color(0xFF0D6B45)
                  : const Color(0xFFF57C00),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: Icon(
              _locationsConfirmed ? Icons.check_circle : Icons.route_rounded,
            ),
            label: Text(
              _locationsConfirmed
                  ? 'ยืนยันการเดินทาง'
                  : 'ยืนยันจุดรับส่งผู้โดยสาร',
            ),
          ),
        ),
      ),
    );
  }
}

class TravelSummaryCard extends StatelessWidget {
  const TravelSummaryCard({
    super.key,
    required this.pickup,
    required this.destination,
    required this.distanceKm,
    required this.rideSelection,
  });

  final PickedLocation pickup;
  final PickedLocation destination;
  final double? distanceKm;
  final TravelRideSelection? rideSelection;

  Future<void> _openGoogleMapsDirections(BuildContext context) async {
    final uri = Uri.https('www.google.com', '/maps/dir/', <String, String>{
      'api': '1',
      'origin': '${pickup.latitude},${pickup.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'travelmode': 'driving',
    });

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิด Google Maps ได้')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final distanceText = distanceKm == null
        ? 'รอการคำนวณระยะทาง'
        : 'จากตำแหน่งปัจจุบัน ${distanceKm!.toStringAsFixed(1)} กม.';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const _TravelHeroPlaceholder(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'ปลายทางเริ่มต้น',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      destination.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      distanceText,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF0D6B45),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () => _openGoogleMapsDirections(context),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB45309),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.navigation_outlined, size: 18),
                      label: const Text('เปิด Google Maps'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (rideSelection != null) ...<Widget>[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'รายละเอียดการเดินทาง',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF9A3412),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _TravelSelectionSummaryRow(
                    icon: rideSelection!.vehicleType.icon,
                    label: 'ประเภทรถ',
                    value: rideSelection!.vehicleType.label,
                  ),
                  const SizedBox(height: 8),
                  _TravelSelectionSummaryRow(
                    icon: Icons.schedule,
                    label: 'เวลา',
                    value: rideSelection!.scheduleLabel,
                  ),
                  const SizedBox(height: 8),
                  _TravelSelectionSummaryRow(
                    icon: Icons.my_location_outlined,
                    label: 'จุดรับ',
                    value: pickup.title,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TravelVehicleAvailabilityCard(
              selectedVehicle: rideSelection!.vehicleType,
            ),
          ],
        ],
      ),
    );
  }
}

class _TravelHeroPlaceholder extends StatelessWidget {
  const _TravelHeroPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Icon(
        Icons.route_rounded,
        color: Color(0xFFF57C00),
        size: 34,
      ),
    );
  }
}

class _TravelLocationCard extends StatelessWidget {
  const _TravelLocationCard({
    required this.title,
    required this.icon,
    required this.location,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final PickedLocation location;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: const Color(0xFFF57C00)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            location.title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF111827),
            ),
          ),
          if (location.subtitle?.trim().isNotEmpty ?? false) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              location.subtitle!.trim(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6B7280),
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onTap,
            icon: const Icon(Icons.edit_location_alt_outlined),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _TravelRideSetupSheet extends StatefulWidget {
  const _TravelRideSetupSheet({this.initialSelection});

  final TravelRideSelection? initialSelection;

  @override
  State<_TravelRideSetupSheet> createState() => _TravelRideSetupSheetState();
}

class _TravelRideSetupSheetState extends State<_TravelRideSetupSheet> {
  static const Locale _thaiLocale = Locale('th', 'TH');
  static const List<String> _thaiMonths = <String>[
    'มกราคม',
    'กุมภาพันธ์',
    'มีนาคม',
    'เมษายน',
    'พฤษภาคม',
    'มิถุนายน',
    'กรกฎาคม',
    'สิงหาคม',
    'กันยายน',
    'ตุลาคม',
    'พฤศจิกายน',
    'ธันวาคม',
  ];

  late TravelVehicleType _selectedVehicle;
  late bool _isImmediate;
  DateTime? _scheduledAt;

  @override
  void initState() {
    super.initState();
    _selectedVehicle = widget.initialSelection?.vehicleType ?? TravelVehicleType.motorcycle;
    _isImmediate = widget.initialSelection?.isImmediate ?? true;
    _scheduledAt = widget.initialSelection?.isImmediate == true
        ? null
        : widget.initialSelection?.scheduledAt;
  }

  DateTime _defaultScheduledAt() {
    final now = DateTime.now();
    return _scheduledAt ?? now.add(const Duration(minutes: 30));
  }

  String _formatThaiDate(DateTime value) {
    final buddhistYear = value.year + 543;
    final monthName = _thaiMonths[value.month - 1];
    return '${value.day} $monthName $buddhistYear';
  }

  String _formatThaiTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute น.';
  }

  Widget _thaiPickerLocalization(BuildContext context, Widget? child) {
    return Localizations.override(
      context: context,
      locale: _thaiLocale,
      delegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: child,
    );
  }

  void _enableScheduledMode() {
    setState(() {
      _isImmediate = false;
      _scheduledAt ??= _defaultScheduledAt();
    });
  }

  Future<void> _pickScheduleDate() async {
    final now = DateTime.now();
    final initial = _defaultScheduledAt();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      locale: _thaiLocale,
      builder: _thaiPickerLocalization,
    );

    if (!mounted || pickedDate == null) {
      return;
    }

    final base = _defaultScheduledAt();

    setState(() {
      _isImmediate = false;
      _scheduledAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        base.hour,
        base.minute,
      );
    });
  }

  Future<void> _pickScheduleTime() async {
    final initial = _defaultScheduledAt();

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: _thaiPickerLocalization,
    );

    if (!mounted || pickedTime == null) {
      return;
    }

    setState(() {
      _isImmediate = false;
      final base = _defaultScheduledAt();
      _scheduledAt = DateTime(
        base.year,
        base.month,
        base.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFFBF6),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
      child: SafeArea(
        top: false,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('riders')
              .where('passengerReady', isEqualTo: true)
              .snapshots(includeMetadataChanges: true),
          builder: (context, snapshot) {
            final vehicleCounts = _countOnlineTravelVehicles(
              snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6D3D1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'เลือกเวลาและประเภทรถ',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ลูกค้าสามารถเลือกเวลารถออกและดูสถานะออนไลน์ของแต่ละประเภทได้ทันที',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'เวลาเดินทาง',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    ChoiceChip(
                      label: const Text('ตอนนี้'),
                      selected: _isImmediate,
                      onSelected: (_) {
                        setState(() {
                          _isImmediate = true;
                          _scheduledAt = null;
                        });
                      },
                    ),
                    ChoiceChip(
                      label: const Text('กำหนดวันและเวลา'),
                      selected: !_isImmediate,
                      onSelected: (_) => _enableScheduledMode(),
                    ),
                  ],
                ),
                if (!_isImmediate) ...<Widget>[
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _TravelScheduleFieldCard(
                          label: 'วันที่เดินทาง',
                          value: _scheduledAt == null
                              ? 'เลือกวันที่'
                              : _formatThaiDate(_scheduledAt!),
                          icon: Icons.calendar_month_rounded,
                          onTap: _pickScheduleDate,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TravelScheduleFieldCard(
                          label: 'เวลาเดินทาง',
                          value: _scheduledAt == null
                              ? 'เลือกเวลา'
                              : _formatThaiTime(_scheduledAt!),
                          icon: Icons.access_time_rounded,
                          onTap: _pickScheduleTime,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _scheduledAt == null
                        ? 'กรุณาเลือกวันที่และเวลาเดินทาง'
                        : 'กำหนดเดินทางวันที่ ${_formatThaiDate(_scheduledAt!)} เวลา ${_formatThaiTime(_scheduledAt!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'ประเภทรถ',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: TravelVehicleType.values
                      .map(
                        (vehicle) => Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: vehicle == TravelVehicleType.pickup ? 0 : 10,
                            ),
                            child: _TravelVehicleOptionCard(
                              vehicle: vehicle,
                              isSelected: vehicle == _selectedVehicle,
                              onlineCount: vehicleCounts[vehicle] ?? 0,
                              onTap: () {
                                setState(() => _selectedVehicle = vehicle);
                              },
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Color(0xFFDCFCE7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.trip_origin,
                          size: 16,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'จุดสีเขียวหมายถึงมีรถประเภทนั้นออนไลน์อยู่ตอนนี้ ถ้าไม่พบระบบจะแสดงว่าออฟไลน์',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF374151),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop(
                        TravelRideSelection(
                          vehicleType: _selectedVehicle,
                          scheduledAt: _scheduledAt ?? DateTime.now(),
                          isImmediate: _isImmediate,
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF57C00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('ยืนยันตัวเลือกนี้'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TravelVehicleOptionCard extends StatelessWidget {
  const _TravelVehicleOptionCard({
    required this.vehicle,
    required this.isSelected,
    required this.onlineCount,
    required this.onTap,
  });

  final TravelVehicleType vehicle;
  final bool isSelected;
  final int onlineCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOnline = onlineCount > 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF7ED) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? vehicle.accentColor : const Color(0xFFE5E7EB),
            width: isSelected ? 1.6 : 1,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: vehicle.accentColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(vehicle.icon, color: vehicle.accentColor),
                ),
                const Spacer(),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isOnline
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFD1D5DB),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              vehicle.label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              isOnline ? 'ออนไลน์ $onlineCount คัน' : 'ออฟไลน์',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isOnline
                        ? const Color(0xFF166534)
                        : const Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelSelectionSummaryRow extends StatelessWidget {
  const _TravelSelectionSummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: const Color(0xFFB45309)),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF374151),
                  ),
              children: <InlineSpan>[
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class TravelVehicleAvailabilityCard extends StatelessWidget {
  const TravelVehicleAvailabilityCard({
    super.key,
    required this.selectedVehicle,
  });

  final TravelVehicleType selectedVehicle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('riders')
          .where('passengerReady', isEqualTo: true)
            .snapshots(includeMetadataChanges: true),
        builder: (context, snapshot) {
          final vehicleCounts = _countOnlineTravelVehicles(
            snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'สถานะรถออนไลน์',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
              ),
              const SizedBox(height: 12),
              Row(
                children: TravelVehicleType.values
                    .map(
                      (vehicle) => Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: vehicle == TravelVehicleType.pickup ? 0 : 10,
                          ),
                          child: _TravelAvailabilityStatusPill(
                            vehicle: vehicle,
                            isSelected: vehicle == selectedVehicle,
                            onlineCount: vehicleCounts[vehicle] ?? 0,
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TravelAvailabilityStatusPill extends StatelessWidget {
  const _TravelAvailabilityStatusPill({
    required this.vehicle,
    required this.isSelected,
    required this.onlineCount,
  });

  final TravelVehicleType vehicle;
  final bool isSelected;
  final int onlineCount;

  @override
  Widget build(BuildContext context) {
    final isOnline = onlineCount > 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFFFF7ED) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSelected ? vehicle.accentColor : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(vehicle.icon, color: vehicle.accentColor, size: 22),
          const SizedBox(height: 8),
          Text(
            vehicle.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF111827),
                ),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isOnline
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFD1D5DB),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isOnline ? 'ออนไลน์ $onlineCount' : 'ออฟไลน์',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isOnline
                            ? const Color(0xFF166534)
                            : const Color(0xFF6B7280),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Map<TravelVehicleType, int> _countOnlineTravelVehicles(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final counts = <TravelVehicleType, int>{
    for (final vehicle in TravelVehicleType.values) vehicle: 0,
  };

  for (final doc in docs) {
    final data = doc.data();
    if (!_isTravelRiderOnline(data)) {
      continue;
    }

    final vehicleType = _readTravelVehicleType(data);
    if (vehicleType == null) {
      continue;
    }

    counts[vehicleType] = (counts[vehicleType] ?? 0) + 1;
  }

  return counts;
}

bool _isTravelRiderOnline(Map<String, dynamic> data) {
  final locationStatus = (data['locationStatus'] as String?)?.trim().toLowerCase();
  if (locationStatus == 'offline') {
    return false;
  }

  final geo = data['currentLocation'];
  final latitude = geo is GeoPoint
      ? geo.latitude
      : _travelToDouble(data['latitude']) ?? _travelToDouble(data['lat']);
  final longitude = geo is GeoPoint
      ? geo.longitude
      : _travelToDouble(data['longitude']) ?? _travelToDouble(data['lng']);
  if (latitude == null || longitude == null) {
    return false;
  }

  final updatedAtRaw = data['locationUpdatedAt'] ?? data['updatedAt'];
  final updatedAt = updatedAtRaw is Timestamp ? updatedAtRaw.toDate() : null;
  if (updatedAt == null) {
    return true;
  }

  return DateTime.now().difference(updatedAt).inMinutes <= 10;
}

double? _travelToDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }

  if (value is String) {
    return double.tryParse(value.trim());
  }

  return null;
}

TravelVehicleType? _readTravelVehicleType(Map<String, dynamic> data) {
  final rawCandidates = <String?>[
    data['vehicleType']?.toString(),
    data['vehicle_type']?.toString(),
    data['vehicle']?.toString(),
    data['type']?.toString(),
    data['riderType']?.toString(),
    data['serviceType']?.toString(),
    data['vehicleName']?.toString(),
  ];

  for (final rawValue in rawCandidates) {
    final normalized = rawValue?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      continue;
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
  }

  return null;
}

class _TravelScheduleFieldCard extends StatelessWidget {
  const _TravelScheduleFieldCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 18, color: const Color(0xFFF57C00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6B7280),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: const Color(0xFF111827),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}