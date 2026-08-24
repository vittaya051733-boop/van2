import 'package:flutter/material.dart';

class ProductVariantColorOption {
  const ProductVariantColorOption({
    required this.hex,
    required this.labelTh,
  });

  final String hex;
  final String labelTh;

  Color get color => ProductVariantColorSupport.parseHex(hex) ?? Colors.grey;
}

/// Preset + hex storage for product variant colors.
class ProductVariantColorSupport {
  ProductVariantColorSupport._();

  static const List<ProductVariantColorOption> presets = <ProductVariantColorOption>[
    ProductVariantColorOption(hex: '#E53935', labelTh: 'แดง'),
    ProductVariantColorOption(hex: '#D81B60', labelTh: 'ชมพู'),
    ProductVariantColorOption(hex: '#8E24AA', labelTh: 'ม่วง'),
    ProductVariantColorOption(hex: '#3949AB', labelTh: 'น้ำเงินเข้ม'),
    ProductVariantColorOption(hex: '#1E88E5', labelTh: 'น้ำเงิน'),
    ProductVariantColorOption(hex: '#00ACC1', labelTh: 'ฟ้า'),
    ProductVariantColorOption(hex: '#00897B', labelTh: 'เขียวมิ้นท์'),
    ProductVariantColorOption(hex: '#43A047', labelTh: 'เขียว'),
    ProductVariantColorOption(hex: '#7CB342', labelTh: 'เขียวอ่อน'),
    ProductVariantColorOption(hex: '#FDD835', labelTh: 'เหลือง'),
    ProductVariantColorOption(hex: '#FB8C00', labelTh: 'ส้ม'),
    ProductVariantColorOption(hex: '#6D4C41', labelTh: 'น้ำตาล'),
    ProductVariantColorOption(hex: '#FFFFFF', labelTh: 'ขาว'),
    ProductVariantColorOption(hex: '#BDBDBD', labelTh: 'เทา'),
    ProductVariantColorOption(hex: '#212121', labelTh: 'ดำ'),
    ProductVariantColorOption(hex: '#FFD180', labelTh: 'ครีม'),
    ProductVariantColorOption(hex: '#FF7043', labelTh: 'คอรัล'),
    ProductVariantColorOption(hex: '#26C6DA', labelTh: 'เทอร์ควอยซ์'),
  ];

  static bool isHexColor(String? value) {
    final normalized = (value ?? '').trim();
    return RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(normalized);
  }

  static String normalizeHex(String? value) {
    final trimmed = (value ?? '').trim();
    if (!isHexColor(trimmed)) {
      return trimmed;
    }
    return trimmed.toUpperCase();
  }

  static Color? parseHex(String? value) {
    final normalized = normalizeHex(value);
    if (!isHexColor(normalized)) {
      return null;
    }
    final hex = normalized.substring(1);
    final intValue = int.tryParse(hex, radix: 16);
    if (intValue == null) {
      return null;
    }
    return Color(0xFF000000 | intValue);
  }

  /// Hex preset, or legacy Thai color name saved as plain text.
  static Color? colorForStored(String? stored) {
    final parsed = parseHex(stored);
    if (parsed != null) {
      return parsed;
    }
    final value = (stored ?? '').trim();
    if (value.isEmpty) {
      return null;
    }
    for (final preset in presets) {
      if (preset.labelTh == value) {
        return preset.color;
      }
    }
    return null;
  }

  static String displayLabel(String? stored) {
    final value = (stored ?? '').trim();
    if (value.isEmpty) {
      return 'เลือกสี';
    }
    if (!isHexColor(value)) {
      return value;
    }
    final normalized = normalizeHex(value);
    for (final preset in presets) {
      if (preset.hex == normalized) {
        return preset.labelTh;
      }
    }
    return normalized;
  }
}

/// Circle swatch for a stored variant color (hex or legacy label).
class ProductVariantColorSwatch extends StatelessWidget {
  const ProductVariantColorSwatch({
    super.key,
    required this.storedColor,
    this.size = 24,
    this.selected = false,
    this.onTap,
    this.lightBorder = false,
  });

  final String storedColor;
  final double size;
  final bool selected;
  final VoidCallback? onTap;
  final bool lightBorder;

  @override
  Widget build(BuildContext context) {
    final fill = ProductVariantColorSupport.colorForStored(storedColor);
    final borderColor = selected
        ? const Color(0xFF2563EB)
        : (lightBorder ? Colors.white70 : Colors.grey.shade400);

    final swatch = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill ?? Colors.grey.shade300,
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor,
          width: selected ? 2.5 : 1,
        ),
        boxShadow: lightBorder
            ? const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
    );

    if (onTap == null) {
      return swatch;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: swatch,
      ),
    );
  }
}

class ProductVariantColorSwatchRow extends StatelessWidget {
  const ProductVariantColorSwatchRow({
    super.key,
    required this.colors,
    this.size = 20,
    this.spacing = 6,
    this.selectedColor,
    this.onColorSelected,
    this.lightBorder = false,
  });

  final List<String> colors;
  final double size;
  final double spacing;
  final String? selectedColor;
  final ValueChanged<String>? onColorSelected;
  final bool lightBorder;

  @override
  Widget build(BuildContext context) {
    if (colors.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: colors
          .map(
            (color) => ProductVariantColorSwatch(
              storedColor: color,
              size: size,
              selected: selectedColor == color,
              lightBorder: lightBorder,
              onTap: onColorSelected == null
                  ? null
                  : () => onColorSelected!(color),
            ),
          )
          .toList(growable: false),
    );
  }
}
