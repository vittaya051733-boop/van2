import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'cart_screen.dart';
import 'config/payment_collection_config.dart';
import 'services/payment_qr_service.dart';

typedef TravelConfirmCashOnDelivery = Future<List<String>> Function();
typedef TravelSubmitPromptPaySlip =
    Future<PaymentSlipSubmissionResult> Function(
      PaymentSlipSubmissionRequest request,
    );
typedef TravelOrderCompleted = Future<void> Function(List<String> orderIds);

Future<void> showTravelPaymentFlow({
  required BuildContext context,
  required double grandTotal,
  required String pickupLabel,
  required String destinationLabel,
  required double distanceKm,
  String? vehicleTypeLabel,
  String? scheduleLabel,
  required TravelConfirmCashOnDelivery? onConfirmCashOnDelivery,
  required TravelSubmitPromptPaySlip? onSubmitPromptPaySlip,
  required TravelOrderCompleted onOrderCompleted,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return _TravelPaymentSheet(
        grandTotal: grandTotal,
        pickupLabel: pickupLabel,
        destinationLabel: destinationLabel,
        distanceKm: distanceKm,
        vehicleTypeLabel: vehicleTypeLabel,
        scheduleLabel: scheduleLabel,
        onConfirmCashOnDelivery: onConfirmCashOnDelivery,
        onSubmitPromptPaySlip: onSubmitPromptPaySlip,
        onOrderCompleted: onOrderCompleted,
      );
    },
  );
}

enum _TravelPaymentMethod { cashOnDelivery, trueMoney }

class _TravelPaymentSheet extends StatefulWidget {
  const _TravelPaymentSheet({
    required this.grandTotal,
    required this.pickupLabel,
    required this.destinationLabel,
    required this.distanceKm,
    required this.vehicleTypeLabel,
    required this.scheduleLabel,
    required this.onConfirmCashOnDelivery,
    required this.onSubmitPromptPaySlip,
    required this.onOrderCompleted,
  });

  final double grandTotal;
  final String pickupLabel;
  final String destinationLabel;
  final double distanceKm;
  final String? vehicleTypeLabel;
  final String? scheduleLabel;
  final TravelConfirmCashOnDelivery? onConfirmCashOnDelivery;
  final TravelSubmitPromptPaySlip? onSubmitPromptPaySlip;
  final TravelOrderCompleted onOrderCompleted;

  @override
  State<_TravelPaymentSheet> createState() => _TravelPaymentSheetState();
}

class _TravelPaymentSheetState extends State<_TravelPaymentSheet> {
  _TravelPaymentMethod _selectedPaymentMethod =
      _TravelPaymentMethod.cashOnDelivery;
  bool _isSubmittingCashOnDelivery = false;

  String _formatDistanceKm(double value) {
    if (value < 1) {
      return '${(value * 1000).round()} เมตร';
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} กม.';
  }

  Future<void> _handleCashOnDelivery() async {
    final callback = widget.onConfirmCashOnDelivery;
    if (callback == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ระบบสร้างออเดอร์เดินทางยังไม่พร้อมใช้งาน'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('ยืนยันการชำระเงินปลายทาง'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'ยืนยันการสร้างออเดอร์เดินทางและชำระเงินเมื่อถึงปลายทาง',
                ),
                const SizedBox(height: 14),
                _TravelOrderSummaryCard(
                  pickupLabel: widget.pickupLabel,
                  destinationLabel: widget.destinationLabel,
                  distanceLabel: _formatDistanceKm(widget.distanceKm),
                  totalLabel: '฿${widget.grandTotal.toStringAsFixed(2)}',
                  vehicleTypeLabel: widget.vehicleTypeLabel,
                  scheduleLabel: widget.scheduleLabel,
                  dense: true,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('ยืนยัน'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _isSubmittingCashOnDelivery = true);
    try {
      final orderIds = await callback();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      await widget.onOrderCompleted(orderIds);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('สร้างออเดอร์เดินทางไม่สำเร็จ: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingCashOnDelivery = false);
      }
    }
  }

  Future<void> _handlePromptPay() async {
    final callback = widget.onSubmitPromptPaySlip;
    if (callback == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ระบบชำระเงินด้วยสลิปยังไม่พร้อมใช้งาน')),
      );
      return;
    }

    Navigator.of(context).pop();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final viewport = MediaQuery.of(dialogContext).size;
        return PopScope(
          canPop: false,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: viewport.height * 0.78,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'จ่ายค่าเดินทางด้วยทรูมันนี่',
                      style: Theme.of(dialogContext).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: viewport.height * 0.58,
                      child: _TravelPromptPayDialogContent(
                        grandTotal: widget.grandTotal,
                        pickupLabel: widget.pickupLabel,
                        destinationLabel: widget.destinationLabel,
                        distanceLabel: _formatDistanceKm(widget.distanceKm),
                        vehicleTypeLabel: widget.vehicleTypeLabel,
                        scheduleLabel: widget.scheduleLabel,
                        onSubmitPromptPaySlip: callback,
                        onSubmissionCompleted: widget.onOrderCompleted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('ปิด'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
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
        child: Column(
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
              'ชำระค่าการเดินทาง',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'เลือกระบบชำระเงินเดียวกับหน้าตะกร้าก่อนสร้างออเดอร์และแมตช์ไรเดอร์',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
            ),
            const SizedBox(height: 18),
            Text(
              'ยอดที่ต้องชำระ ฿${widget.grandTotal.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: const Color(0xFFE55A00),
              ),
            ),
            const SizedBox(height: 16),
            _TravelOrderSummaryCard(
              pickupLabel: widget.pickupLabel,
              destinationLabel: widget.destinationLabel,
              distanceLabel: _formatDistanceKm(widget.distanceKm),
              totalLabel: '฿${widget.grandTotal.toStringAsFixed(2)}',
              vehicleTypeLabel: widget.vehicleTypeLabel,
              scheduleLabel: widget.scheduleLabel,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _TravelPaymentActionButton(
                  label: const Text('จ่ายปลายทาง'),
                  selected:
                      _selectedPaymentMethod ==
                      _TravelPaymentMethod.cashOnDelivery,
                  icon: _isSubmittingCashOnDelivery
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delivery_dining_rounded, size: 20),
                  onTap: _isSubmittingCashOnDelivery
                      ? null
                      : () async {
                          setState(
                            () => _selectedPaymentMethod =
                                _TravelPaymentMethod.cashOnDelivery,
                          );
                          await _handleCashOnDelivery();
                        },
                ),
                _TravelPaymentActionButton(
                  label: const Text('จ่ายด้วยทรูมันนี่'),
                  selected:
                      _selectedPaymentMethod == _TravelPaymentMethod.trueMoney,
                  icon: const _TravelTrueMoneyLogoMark(),
                  iconOnly: true,
                  onTap: _isSubmittingCashOnDelivery
                      ? null
                      : () async {
                          setState(
                            () => _selectedPaymentMethod =
                                _TravelPaymentMethod.trueMoney,
                          );
                          await _handlePromptPay();
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelPaymentActionButton extends StatelessWidget {
  const _TravelPaymentActionButton({
    required this.label,
    required this.selected,
    required this.icon,
    required this.onTap,
    this.iconOnly = false,
  });

  final Widget label;
  final bool selected;
  final Widget icon;
  final VoidCallback? onTap;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    if (iconOnly) {
      return Semantics(
        button: true,
        label: 'จ่ายด้วยทรูมันนี่',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: icon,
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFEDD5) : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? const Color(0xFFE55A00)
                  : const Color(0xFFE5E7EB),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              icon,
              const SizedBox(width: 8),
              DefaultTextStyle.merge(
                style: TextStyle(
                  color: selected
                      ? const Color(0xFF9A3412)
                      : const Color(0xFF374151),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                child: label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TravelTrueMoneyLogoMark extends StatelessWidget {
  const _TravelTrueMoneyLogoMark();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 162,
        height: 84,
        child: Image.asset(
          'assets/file_000000002938720996c731fc647871c3.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      ),
    );
  }
}

class _TravelPromptPayDialogContent extends StatefulWidget {
  const _TravelPromptPayDialogContent({
    required this.grandTotal,
    required this.pickupLabel,
    required this.destinationLabel,
    required this.distanceLabel,
    required this.vehicleTypeLabel,
    required this.scheduleLabel,
    required this.onSubmitPromptPaySlip,
    required this.onSubmissionCompleted,
  });

  final double grandTotal;
  final String pickupLabel;
  final String destinationLabel;
  final String distanceLabel;
  final String? vehicleTypeLabel;
  final String? scheduleLabel;
  final TravelSubmitPromptPaySlip onSubmitPromptPaySlip;
  final TravelOrderCompleted onSubmissionCompleted;

  @override
  State<_TravelPromptPayDialogContent> createState() =>
      _TravelPromptPayDialogContentState();
}

class _TravelPromptPayDialogContentState
    extends State<_TravelPromptPayDialogContent> {
  final GlobalKey _qrBoundaryKey = GlobalKey();

  bool _isSavingQr = false;
  bool _isSubmittingSlip = false;
  PlatformFile? _attachedSlip;

  String _formatDialogMoney(num value) {
    final fixed = value.toStringAsFixed(1);
    if (fixed.endsWith('.0')) {
      return fixed.substring(0, fixed.length - 2);
    }
    return fixed;
  }

  Future<void> _saveQrCode() async {
    final messenger = ScaffoldMessenger.of(context);
    final boundary =
        _qrBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;

    if (boundary == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('ยังจับภาพคิวอาร์โค้ดไม่ได้ ลองใหม่อีกครั้ง'),
        ),
      );
      return;
    }

    setState(() => _isSavingQr = true);
    try {
      final permissionGranted = await _ensureGalleryPermission();
      if (!permissionGranted) {
        if (!mounted) {
          return;
        }
        messenger.showSnackBar(
          const SnackBar(content: Text('ไม่ได้รับสิทธิ์บันทึกรูปลงเครื่อง')),
        );
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData?.buffer.asUint8List();

      if (pngBytes == null) {
        if (!mounted) {
          return;
        }
        messenger.showSnackBar(
          const SnackBar(content: Text('สร้างไฟล์คิวอาร์โค้ดไม่สำเร็จ')),
        );
        return;
      }

      final result = await ImageGallerySaverPlus.saveImage(
        pngBytes,
        quality: 100,
        name: 'van2_travel_qr_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (!mounted) {
        return;
      }

      final succeeded =
          result != null && result.toString().toLowerCase() != 'false';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            succeeded
                ? 'บันทึกคิวอาร์โค้ดลงเครื่องแล้ว'
                : 'บันทึกคิวอาร์โค้ดไม่สำเร็จ ลองใหม่อีกครั้ง',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('บันทึกคิวอาร์โค้ดไม่สำเร็จ ลองใหม่อีกครั้ง'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingQr = false);
      }
    }
  }

  Future<bool> _ensureGalleryPermission() async {
    if (kIsWeb) {
      return false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final status = await Permission.photosAddOnly.request();
      return status.isGranted || status.isLimited;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final photosStatus = await Permission.photos.request();
      if (photosStatus.isGranted || photosStatus.isLimited) {
        return true;
      }
      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted;
    }
    return true;
  }

  Future<void> _pickSlipImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      withData: true,
      allowedExtensions: const <String>['jpg', 'jpeg', 'png', 'webp'],
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    setState(() => _attachedSlip = result.files.single);
  }

  String? _inferSlipContentType(PlatformFile file) {
    final extension = (file.extension ?? '').toLowerCase();
    switch (extension) {
      case 'jpg':
      case 'jpeg':
      case 'jfif':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return null;
    }
  }

  Future<void> _showVerificationFeedback(
    PaymentSlipSubmissionResult result,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(
            result.verificationStatus == 'verified'
                ? 'Slip OK ตรวจสอบผ่าน'
                : 'ผลการตรวจสลิป',
          ),
          content: Text(result.message),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('รับทราบ'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _submitSlipForVerification() async {
    final attachedSlip = _attachedSlip;
    final slipBytes = attachedSlip?.bytes;
    if (attachedSlip == null || slipBytes == null || slipBytes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกรูปสลิปก่อนส่งตรวจ')),
      );
      return;
    }

    setState(() => _isSubmittingSlip = true);
    try {
      final result = await widget.onSubmitPromptPaySlip(
        PaymentSlipSubmissionRequest(
          bytes: slipBytes,
          fileName: attachedSlip.name,
          contentType: _inferSlipContentType(attachedSlip),
          sizeBytes: attachedSlip.size,
          grandTotal: widget.grandTotal,
        ),
      );

      if (!mounted) {
        return;
      }

      await _showVerificationFeedback(result);

      if (!mounted) {
        return;
      }

      if (result.verificationStatus == 'verified') {
        Navigator.of(context).pop();
        await widget.onSubmissionCompleted(result.orderIds);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ส่งสลิปไม่สำเร็จ: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSubmittingSlip = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: FutureBuilder<PaymentCollectionSettings>(
        initialData: PaymentCollectionSettings.defaults,
        future: PaymentCollectionConfigService.instance.loadOnce(),
        builder: (context, snapshot) {
          final settings = PaymentQrService.resolveSettingsForQr(
            snapshot.data ?? PaymentCollectionSettings.defaults,
          );
          final channel = PaymentQrService.pickDefaultChannel(
            amount: widget.grandTotal,
            config: settings,
          );
          final hasPromptPayQr =
              settings.promptPayPhoneNumber?.trim().isNotEmpty == true ||
              settings.promptPayNationalIdOrTaxId?.trim().isNotEmpty == true;
          final canSaveQr = channel.qrPayload != null || hasPromptPayQr;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'ยอดที่ต้องชำระ ฿${_formatDialogMoney(widget.grandTotal)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFE55A00),
                ),
              ),
              const SizedBox(height: 12),
              _TravelOrderSummaryCard(
                pickupLabel: widget.pickupLabel,
                destinationLabel: widget.destinationLabel,
                distanceLabel: widget.distanceLabel,
                totalLabel: '฿${widget.grandTotal.toStringAsFixed(2)}',
                vehicleTypeLabel: widget.vehicleTypeLabel,
                scheduleLabel: widget.scheduleLabel,
                dense: true,
              ),
              const SizedBox(height: 10),
              _TravelPromptPayQrCard(
                qrBoundaryKey: _qrBoundaryKey,
                channel: channel,
                amount: widget.grandTotal,
                settings: settings,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canSaveQr && !_isSavingQr ? _saveQrCode : null,
                  icon: _isSavingQr
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(
                    _isSavingQr
                        ? 'กำลังบันทึก...'
                        : 'บันทึกคิวอาร์โค้ดลงเครื่อง',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _TravelSlipAttachmentSection(
                slip: _attachedSlip,
                onAttach: _pickSlipImage,
                onClear: _attachedSlip == null
                    ? null
                    : () {
                        setState(() => _attachedSlip = null);
                      },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSubmittingSlip
                      ? null
                      : _submitSlipForVerification,
                  icon: _isSubmittingSlip
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.receipt_long_rounded),
                  label: Text(
                    _isSubmittingSlip
                        ? 'กำลังส่งสลิป...'
                        : 'ส่งสลิปเพื่อตรวจสอบ',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TravelPromptPayQrCard extends StatelessWidget {
  const _TravelPromptPayQrCard({
    required this.qrBoundaryKey,
    required this.channel,
    required this.amount,
    required this.settings,
  });

  final GlobalKey qrBoundaryKey;
  final PaymentChannelDefinition channel;
  final double amount;
  final PaymentCollectionSettings settings;

  @override
  Widget build(BuildContext context) {
    final promptPayPhone = settings.promptPayPhoneNumber?.trim();
    final promptPayId = settings.promptPayNationalIdOrTaxId?.trim();
    final payload =
        channel.qrPayload ??
        (promptPayPhone != null && promptPayPhone.isNotEmpty
            ? PromptPayQrPayload.fromPhoneNumber(
                phoneNumber: promptPayPhone,
                amount: amount,
              )
            : (promptPayId != null && promptPayId.isNotEmpty
                  ? PromptPayQrPayload.fromNationalIdOrTaxId(
                      nationalIdOrTaxId: promptPayId,
                      amount: amount,
                    )
                  : null));

    return RepaintBoundary(
      key: qrBoundaryKey,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          children: <Widget>[
            if (payload != null)
              QrImageView(
                data: payload,
                size: 220,
                backgroundColor: Colors.white,
              )
            else
              Container(
                width: 220,
                height: 220,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: const Text('ยังไม่มีข้อมูล QR สำหรับชำระเงิน'),
              ),
            const SizedBox(height: 12),
            Text(
              channel.destinationLabel ??
                  '${settings.bankName} ${settings.bankAccountNumber}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF374151),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelSlipAttachmentSection extends StatelessWidget {
  const _TravelSlipAttachmentSection({
    required this.slip,
    required this.onAttach,
    required this.onClear,
  });

  final PlatformFile? slip;
  final VoidCallback onAttach;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'แนบสลิปการชำระเงิน',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            slip == null ? 'ยังไม่ได้เลือกไฟล์สลิป' : slip!.name,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAttach,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: const Text('เลือกรูปสลิป'),
                ),
              ),
              if (onClear != null) ...<Widget>[
                const SizedBox(width: 10),
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TravelOrderSummaryCard extends StatelessWidget {
  const _TravelOrderSummaryCard({
    required this.pickupLabel,
    required this.destinationLabel,
    required this.distanceLabel,
    required this.totalLabel,
    this.vehicleTypeLabel,
    this.scheduleLabel,
    this.dense = false,
  });

  final String pickupLabel;
  final String destinationLabel;
  final String distanceLabel;
  final String totalLabel;
  final String? vehicleTypeLabel;
  final String? scheduleLabel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: const Color(0xFF111827),
    );
    final spacing = dense ? 8.0 : 10.0;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(dense ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('รายละเอียดออเดอร์', style: titleStyle),
          SizedBox(height: spacing),
          _TravelSummaryItem(label: 'จุดรับผู้โดยสาร', value: pickupLabel),
          SizedBox(height: spacing),
          _TravelSummaryItem(label: 'จุดส่งผู้โดยสาร', value: destinationLabel),
          SizedBox(height: spacing),
          _TravelSummaryItem(label: 'ระยะทาง', value: distanceLabel),
          SizedBox(height: spacing),
          _TravelSummaryItem(label: 'ค่าบริการ', value: totalLabel),
          if (vehicleTypeLabel != null &&
              vehicleTypeLabel!.isNotEmpty) ...<Widget>[
            SizedBox(height: spacing),
            _TravelSummaryItem(label: 'ประเภทรถ', value: vehicleTypeLabel!),
          ],
          if (scheduleLabel != null && scheduleLabel!.isNotEmpty) ...<Widget>[
            SizedBox(height: spacing),
            _TravelSummaryItem(label: 'เวลาเดินทาง', value: scheduleLabel!),
          ],
        ],
      ),
    );
  }
}

class _TravelSummaryItem extends StatelessWidget {
  const _TravelSummaryItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF111827),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
