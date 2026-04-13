import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ShopQrScannerScreen extends StatefulWidget {
  const ShopQrScannerScreen({super.key});

  @override
  State<ShopQrScannerScreen> createState() => _ShopQrScannerScreenState();
}

class _ShopQrScannerScreenState extends State<ShopQrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  String? _lastCode;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!mounted) return;
    final raw = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (raw == null || raw.isEmpty) return;
    if (_lastCode == raw) return;
    _lastCode = raw;

    _controller.stop();
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สแกน QR ร้านค้า'),
        backgroundColor: const Color(0xFFF57C00),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xCC111827),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'สแกน QR หน้าร้าน เพื่อเปิดรายการสินค้าออนไลน์ของร้านนั้น',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
