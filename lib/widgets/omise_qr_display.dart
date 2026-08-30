import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/l10n.dart';
import '../services/locale_service.dart';
import '../services/omise_payment_service.dart';
import '../utils/gallery_image_saver.dart';

class OmiseQrDisplay extends StatefulWidget {
  const OmiseQrDisplay({
    super.key,
    required this.session,
    this.showSaveButton = true,
  });

  final OmisePaymentSession session;
  final bool showSaveButton;

  @override
  State<OmiseQrDisplay> createState() => _OmiseQrDisplayState();
}

class _OmiseQrDisplayState extends State<OmiseQrDisplay> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _isSaving = false;

  _QrPayload? _payload;

  @override
  void initState() {
    super.initState();
    _payload = _decodeSession(widget.session);
  }

  @override
  void didUpdateWidget(covariant OmiseQrDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.qrImageDataUrl != widget.session.qrImageDataUrl ||
        oldWidget.session.qrImageUrl != widget.session.qrImageUrl) {
      _payload = _decodeSession(widget.session);
    }
  }

  Future<void> _saveToGallery() async {
    if (_isSaving) {
      return;
    }

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final permissionGranted = await GalleryImageSaver.ensurePermission();
      if (!permissionGranted) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text(L10n.photoPermissionDenied)),
          );
        }
        return;
      }

      final pngBytes = await GalleryImageSaver.capturePng(_boundaryKey);
      if (pngBytes == null) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text(L10n.qrCaptureFailed)),
          );
        }
        return;
      }

      final saved = await GalleryImageSaver.savePngBytes(
        pngBytes,
        name: 'van2_omise_qr_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            saved ? L10n.qrSaveSuccess : L10n.qrSaveFailed,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(L10n.qrSaveFailed)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    final payload = _payload;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        RepaintBoundary(
          key: _boundaryKey,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: payload == null
                ? const _QrErrorMessage()
                : _QrImageBody(payload: payload),
          ),
        ),
        if (payload?.isTestMode == true) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            L10n.omiseTestModeHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF9CA3AF),
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (widget.showSaveButton && payload != null) ...<Widget>[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _saveToGallery,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined, size: 18),
              label: Text(_isSaving ? L10n.savingQrToDevice : L10n.saveToDevice),
            ),
          ),
        ],
      ],
    );
      },
    );
  }
}

class _QrImageBody extends StatelessWidget {
  const _QrImageBody({required this.payload});

  final _QrPayload payload;

  @override
  Widget build(BuildContext context) {
    final maxWidth = (MediaQuery.sizeOf(context).width - 96).clamp(240.0, 340.0);
    // Thai PromptPay slip from Omise is slightly taller than wide.
    const aspectRatio = 0.78;
    final height = maxWidth / aspectRatio;

    if (payload.isSvg) {
      return SizedBox(
        width: maxWidth,
        height: height,
        child: SvgPicture.memory(
          payload.bytes,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          allowDrawingOutsideViewBox: true,
          placeholderBuilder: (context) => const _QrLoadingPlaceholder(),
        ),
      );
    }

    final networkUrl = payload.networkUrl;
    if (networkUrl != null && networkUrl.isNotEmpty) {
      return SizedBox(
        width: maxWidth,
        height: height,
        child: Image.network(
          networkUrl,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const _QrErrorMessage();
          },
        ),
      );
    }

    return SizedBox(
      width: maxWidth,
      height: height,
      child: Image.memory(
        payload.bytes,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return const _QrErrorMessage();
        },
      ),
    );
  }
}

class _QrLoadingPlaceholder extends StatelessWidget {
  const _QrLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 220,
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _QrErrorMessage extends StatelessWidget {
  const _QrErrorMessage();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    return SizedBox(
      height: 120,
      child: Center(child: Text(L10n.cannotLoadQr)),
    );
      },
    );
  }
}

class _QrPayload {
  const _QrPayload({
    required this.bytes,
    required this.isSvg,
    this.isTestMode = false,
  })  : networkUrl = null;

  _QrPayload.network(this.networkUrl)
      : bytes = Uint8List(0),
        isSvg = false,
        isTestMode = false;

  final Uint8List bytes;
  final bool isSvg;
  final bool isTestMode;
  final String? networkUrl;
}

_QrPayload? _decodeSession(OmisePaymentSession session) {
  final dataUrl = session.qrImageDataUrl?.trim();
  if (dataUrl != null && dataUrl.startsWith('data:')) {
    final match = RegExp(r'^data:([^;]+);base64,(.+)$').firstMatch(dataUrl);
    if (match != null) {
      try {
        final mimeType = match.group(1)!.toLowerCase();
        final bytes = base64Decode(match.group(2)!);
        final isSvg = mimeType.contains('svg');
        var isTestMode = false;

        if (isSvg) {
          final svgText = utf8.decode(bytes);
          isTestMode = svgText.toUpperCase().contains('TEST MODE');
        }

        return _QrPayload(bytes: bytes, isSvg: isSvg, isTestMode: isTestMode);
      } catch (_) {
        return null;
      }
    }
  }

  final url = session.qrImageUrl?.trim();
  if (url != null && url.isNotEmpty) {
    return _QrPayload.network(url);
  }

  return null;
}
