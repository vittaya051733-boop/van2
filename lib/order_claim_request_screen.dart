import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'admin_support_thread_screen.dart';
import 'l10n/l10n.dart';
import 'models/claim_request_models.dart';
import 'services/admin_support_config.dart';
import 'services/admin_support_service.dart';
import 'services/locale_service.dart';
import 'utils/catalog_product_image_url.dart';
import 'widgets/cached_app_image.dart';

class OrderClaimRequestScreen extends StatefulWidget {
  const OrderClaimRequestScreen({
    super.key,
    required this.orderId,
    this.config = kVan2AdminSupportConfig,
  });

  final String orderId;
  final AdminSupportConfig config;

  @override
  State<OrderClaimRequestScreen> createState() => _OrderClaimRequestScreenState();
}

class _OrderLine {
  const _OrderLine({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.imageUrl,
  });

  final String productId;
  final String name;
  final int quantity;
  final double? unitPrice;
  final String? imageUrl;
}

class _OrderClaimRequestScreenState extends State<OrderClaimRequestScreen> {
  static const List<String> _reasonKeys = <String>[
    'mismatch',
    'damaged',
    'wrong_item',
    'other',
  ];

  String _claimReasonLabel(String key) {
    return switch (key) {
      'mismatch' => L10n.claimReasonMismatch,
      'damaged' => L10n.claimReasonDamaged,
      'wrong_item' => L10n.claimReasonWrongItem,
      'other' => L10n.claimReasonOther,
      _ => key,
    };
  }

  final _noteController = TextEditingController();
  final _picker = ImagePicker();
  final Map<String, int> _selectedQty = <String, int>{};
  final List<File> _pendingImages = <File>[];

  String _reason = 'mismatch';
  bool _submitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  List<_OrderLine> _readLines(Map<String, dynamic> data) {
    final rawProducts = data['products'] ?? data['items'];
    if (rawProducts is! List) {
      return const <_OrderLine>[];
    }

    final lines = <_OrderLine>[];
    for (final raw in rawProducts) {
      if (raw is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(raw);
      final productId = _firstString(map, const <String>[
        'productId',
        'product_id',
        'id',
      ]);
      if (productId == null || productId.isEmpty) {
        continue;
      }
      final name = _firstString(map, const <String>[
            'name',
            'productName',
            'title',
          ]) ??
          L10n.productFallback;
      final quantity = _readInt(map['quantity']) ?? 1;
      final unitPrice = _readDouble(map['unitPrice'] ?? map['price']);
      final imageUrl = _firstString(map, const <String>[
            'imageUrl',
            'productImage',
            'photoUrl',
          ]) ??
          readCatalogProductImageUrl(map);
      lines.add(
        _OrderLine(
          productId: productId,
          name: name,
          quantity: quantity <= 0 ? 1 : quantity,
          unitPrice: unitPrice,
          imageUrl: imageUrl,
        ),
      );
    }
    return lines;
  }

  void _ensureDefaults(List<_OrderLine> lines) {
    if (_selectedQty.isNotEmpty) {
      return;
    }
    for (final line in lines) {
      _selectedQty[line.productId] = line.quantity;
    }
  }

  Future<void> _pickImages() async {
    final remaining = AdminSupportService.maxImages - _pendingImages.length;
    if (remaining <= 0) {
      _showSnack(L10n.maxImagesAttached(AdminSupportService.maxImages));
      return;
    }
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 85);
      if (picked.isEmpty) {
        return;
      }
      setState(() {
        _pendingImages.addAll(
          picked.take(remaining).map((file) => File(file.path)),
        );
      });
    } catch (error) {
      _showSnack(L10n.pickImageFailed(error));
    }
  }

  Future<void> _submit(List<_OrderLine> lines) async {
    if (_submitting) {
      return;
    }

    final items = <ClaimRequestItem>[];
    for (final line in lines) {
      final qty = _selectedQty[line.productId] ?? 0;
      if (qty <= 0) {
        continue;
      }
      items.add(
        ClaimRequestItem(
          productId: line.productId,
          name: line.name,
          quantity: qty,
          unitPrice: line.unitPrice,
          imageUrl: line.imageUrl,
        ),
      );
    }

    if (items.isEmpty) {
      _showSnack(L10n.selectClaimProducts);
      return;
    }

    setState(() => _submitting = true);
    try {
      final ticketId = await AdminSupportService.submitProductClaimRequest(
        config: widget.config,
        orderId: widget.orderId,
        claimRequest: ClaimRequestPayload(items: items, reason: _reason),
        extraNote: _noteController.text,
        imageFiles: List<File>.from(_pendingImages),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => AdminSupportThreadScreen(ticketId: ticketId),
        ),
      );
    } catch (error) {
      if (mounted) {
        _showSnack('$error');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return ListenableBuilder(
        listenable: LocaleService.instance,
        builder: (context, _) {
          return Scaffold(
            appBar: AppBar(title: Text(L10n.claimProduct)),
            body: Center(child: Text(L10n.signInBeforeClaim)),
          );
        },
      );
    }

    return ListenableBuilder(
      listenable: LocaleService.instance,
      builder: (context, _) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.claimProduct),
        backgroundColor: const Color(0xFFFF8A1E),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .doc(widget.orderId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(L10n.claimLoadOrderFailed(snapshot.error!)));
          }

          final data = snapshot.data?.data();
          if (data == null) {
            return Center(child: Text(L10n.orderNotFound(widget.orderId)));
          }

          final lines = _readLines(data);
          _ensureDefaults(lines);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                L10n.selectProductsToClaim,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              if (lines.isEmpty)
                Text(L10n.orderHasNoProducts)
              else
                ...lines.map((line) {
                  final qty = _selectedQty[line.productId] ?? 0;
                  final selected = qty > 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: line.imageUrl == null
                                ? const ColoredBox(
                                    color: Color(0xFFF3F4F6),
                                    child: Icon(Icons.image_outlined),
                                  )
                                : CachedAppImage(
                                    imageUrl: line.imageUrl,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                line.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                'x${line.quantity}'
                                '${line.unitPrice != null ? ' • ฿${line.unitPrice!.toStringAsFixed(0)}' : ''}',
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (selected) _QtyStepper(
                          quantity: qty,
                          onDecrement: qty <= 1
                              ? null
                              : () => setState(() {
                                    _selectedQty[line.productId] = qty - 1;
                                  }),
                          onIncrement: () => setState(() {
                            _selectedQty[line.productId] = qty + 1;
                          }),
                        ),
                        Checkbox(
                          value: selected,
                          onChanged: (checked) {
                            setState(() {
                              _selectedQty[line.productId] =
                                  checked == true ? line.quantity : 0;
                            });
                          },
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 12),
              Text(
                L10n.reasonLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _reasonKeys
                    .map(
                      (reasonKey) => ChoiceChip(
                        label: Text(_claimReasonLabel(reasonKey)),
                        selected: _reason == reasonKey,
                        onSelected: (_) => setState(() => _reason = reasonKey),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                maxLines: 3,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: L10n.additionalDetailsOptional,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(L10n.attachImagesCount(
                      _pendingImages.length,
                      AdminSupportService.maxImages,
                    )),
                  ),
                  ..._pendingImages.asMap().entries.map(
                    (entry) => InputChip(
                      label: Text(L10n.imageNumber(entry.key + 1)),
                      onDeleted: () => setState(() => _pendingImages.removeAt(entry.key)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : () => _submit(lines),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8A1E),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.support_agent_outlined),
                  label: Text(L10n.submitClaimToAdmin),
                ),
              ),
            ],
          );
        },
      ),
    );
      },
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  final int quantity;
  final VoidCallback? onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _icon(Icons.remove, onDecrement),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('$quantity', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        _icon(Icons.add, onIncrement),
      ],
    );
  }

  Widget _icon(IconData icon, VoidCallback? onTap) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        icon: Icon(icon, size: 16),
      ),
    );
  }
}

String? _firstString(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
  }
  return null;
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

double? _readDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}
