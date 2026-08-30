import '../l10n/l10n.dart';
import '../public_catalog_service.dart';
import '../services/locale_service.dart';
import '../services/product_translation_service.dart';

class LocalizedProductText {
  LocalizedProductText._();

  static String nameForProduct(PublicCatalogProduct product) =>
      name(product.data, productId: product.id);

  static String descriptionForProduct(PublicCatalogProduct product) =>
      description(product.data, productId: product.id);

  static String name(Map<String, dynamic> data, {String? productId}) {
    final id = _productId(data, productId);
    if (LocaleService.instance.isEnglish) {
      final en = _englishName(data, id);
      if (en != null) {
        return en;
      }
      _scheduleTranslationIfNeeded(data, productId: id);
    }
    return (data['name'] ?? L10n.productFallback).toString().trim();
  }

  static String description(Map<String, dynamic> data, {String? productId}) {
    final id = _productId(data, productId);
    if (LocaleService.instance.isEnglish) {
      final en = _englishDescription(data, id);
      if (en != null) {
        return en;
      }
      _scheduleTranslationIfNeeded(data, productId: id);
    }
    return (data['description'] ?? '').toString().trim();
  }

  static String? _englishName(Map<String, dynamic> data, String? id) {
    final runtime = id == null
        ? null
        : ProductTranslationService.instance.runtimeFields(id)?['nameEn'];
    if (runtime != null && runtime.isNotEmpty) {
      return runtime;
    }
    final en = data['nameEn']?.toString().trim();
    if (en != null && en.isNotEmpty) {
      return en;
    }
    return null;
  }

  static String? _englishDescription(Map<String, dynamic> data, String? id) {
    final runtime = id == null
        ? null
        : ProductTranslationService.instance.runtimeFields(id)?['descriptionEn'];
    if (runtime != null && runtime.isNotEmpty) {
      return runtime;
    }
    final en = data['descriptionEn']?.toString().trim();
    if (en != null && en.isNotEmpty) {
      return en;
    }
    return null;
  }

  static void _scheduleTranslationIfNeeded(
    Map<String, dynamic> data, {
    String? productId,
  }) {
    final id = _productId(data, productId);
    if (id == null) {
      return;
    }
    ProductTranslationService.instance.scheduleEnsureEnglish(
      productId: id,
      data: data,
    );
  }

  static String shopName(Map<String, dynamic> data) {
    if (LocaleService.instance.isEnglish) {
      final en = data['shopNameEn']?.toString().trim();
      if (en != null && en.isNotEmpty) return en;
    }
    final th = (data['shopName'] ?? L10n.shopFallback).toString().trim();
    return th.isNotEmpty ? th : L10n.shopFallback;
  }

  static String shopNameForProduct(PublicCatalogProduct product) {
    return shopName(<String, dynamic>{
      'shopName': product.shopName,
      'shopNameEn': product.data['shopNameEn'],
    });
  }

  static String? _productId(Map<String, dynamic> data, String? productId) {
    final explicit = productId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final fromData = data['id']?.toString().trim();
    if (fromData != null && fromData.isNotEmpty) {
      return fromData;
    }
    return null;
  }
}
