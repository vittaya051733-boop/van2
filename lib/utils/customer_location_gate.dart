import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

enum CustomerLocationGateResult {
  granted,
  denied,
  retryOnResume,
}

/// Ensures GPS is on and location permission is granted.
/// Shows dialogs to open Location Settings or App Settings when needed.
Future<CustomerLocationGateResult> ensureCustomerLocationAccess(
  BuildContext context, {
  void Function(String message)? onSnackBar,
}) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    if (kIsWeb) {
      onSnackBar?.call(
        'เบราว์เซอร์ไม่รองรับการระบุตำแหน่ง กรุณาเลือกพิกัดบนแผนที่แทน',
      );
      return CustomerLocationGateResult.denied;
    }

    if (!context.mounted) {
      return CustomerLocationGateResult.denied;
    }

    final openLocation = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('เปิดตำแหน่งลูกค้า'),
        content: const Text(
          'ระบบยังปิดตำแหน่งอยู่ ต้องเปิด Location ก่อนจึงจะระบุตำแหน่งอัตโนมัติได้',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ไปเปิดตำแหน่ง'),
          ),
        ],
      ),
    );

    if (openLocation == true) {
      final opened = await Geolocator.openLocationSettings();
      if (opened) {
        onSnackBar?.call('กลับเข้าแอปแล้วระบบจะลองระบุตำแหน่งให้อัตโนมัติ');
        return CustomerLocationGateResult.retryOnResume;
      }
      onSnackBar?.call(
        'ไม่สามารถเปิดหน้าตั้งค่าตำแหน่งได้ กรุณาเปิด Location ในเครื่องด้วยตนเอง',
      );
    }
    return CustomerLocationGateResult.denied;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.deniedForever) {
    if (kIsWeb) {
      onSnackBar?.call(
        'กรุณากดไอคอนแม่กุญแจในแถบที่อยู่ของเบราว์เซอร์ แล้วอนุญาตการเข้าถึงตำแหน่ง',
      );
      return CustomerLocationGateResult.denied;
    }

    if (!context.mounted) {
      return CustomerLocationGateResult.denied;
    }

    final openAppSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ต้องอนุญาตสิทธิ์ตำแหน่ง'),
        content: const Text(
          'คุณปิดสิทธิ์ตำแหน่งแบบถาวรไว้ กรุณาไปที่ตั้งค่าแอปเพื่ออนุญาตสิทธิ์ตำแหน่ง',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ไปตั้งค่าแอป'),
          ),
        ],
      ),
    );

    if (openAppSettings == true) {
      final opened = await Geolocator.openAppSettings();
      if (opened) {
        onSnackBar?.call('กลับเข้าแอปแล้วระบบจะลองระบุตำแหน่งให้อัตโนมัติ');
        return CustomerLocationGateResult.retryOnResume;
      }
      onSnackBar?.call(
        'ไม่สามารถเปิดหน้า App Settings ได้ กรุณาเปิดสิทธิ์ตำแหน่งในตั้งค่าแอปด้วยตนเอง',
      );
    }
    return CustomerLocationGateResult.denied;
  }

  if (permission == LocationPermission.denied) {
    onSnackBar?.call(
      kIsWeb
          ? 'กรุณาอนุญาตตำแหน่งเมื่อเบราว์เซอร์ถาม หรือเลือกพิกัดบนแผนที่'
          : 'ยังไม่ได้รับสิทธิ์ตำแหน่ง กรุณาอนุญาตเพื่อใช้งานต่อ',
    );
    return CustomerLocationGateResult.denied;
  }

  return CustomerLocationGateResult.granted;
}
