import '../category_catalog_screen.dart';
import '../public_catalog_service.dart';

class NationwideProductCategory {
  const NationwideProductCategory({
    required this.key,
    required this.label,
    required this.productCount,
  });

  final String key;
  final String label;
  final int productCount;
}

class NationwideCatalogService {
  NationwideCatalogService._();

  static final NationwideCatalogService instance = NationwideCatalogService._();

  static String categoryKeyForProduct(PublicCatalogProduct product) {
    return categoryLabelForProduct(product);
  }

  static String categoryLabelForProduct(PublicCatalogProduct product) {
    return catalogTypeForProductDataForRegressionTest(product.data);
  }

  Stream<List<NationwideProductCategory>> streamNationwideCategories() {
    return PublicCatalogService.streamNationwideShippingSections().map(
      buildCategoriesFromSections,
    );
  }

  Stream<List<PublicCatalogProduct>> streamAllNationwideProducts() {
    return PublicCatalogService.streamNationwideShippingSections().map(
      flattenNationwideProducts,
    );
  }

  Stream<List<PublicCatalogProduct>> streamNationwideProductsByCategory(
    String categoryKey,
  ) {
    final normalizedKey = categoryKey.trim();
    return PublicCatalogService.streamNationwideShippingSections().map(
      (sections) => productsInCategoryFromSections(sections, normalizedKey),
    );
  }

  static List<NationwideProductCategory> buildCategoriesFromSections(
    List<PublicCatalogSection> sections,
  ) {
    final counts = <String, int>{};
    final labels = <String, String>{};

    for (final section in sections) {
      for (final product in section.products) {
        final label = categoryLabelForProduct(product);
        final key = categoryKeyForProduct(product);
        counts[key] = (counts[key] ?? 0) + 1;
        labels[key] = label;
      }
    }

    final categories = counts.entries
        .map(
          (entry) => NationwideProductCategory(
            key: entry.key,
            label: labels[entry.key] ?? entry.key,
            productCount: entry.value,
          ),
        )
        .toList(growable: false);

    categories.sort((left, right) {
      final byCount = right.productCount.compareTo(left.productCount);
      if (byCount != 0) {
        return byCount;
      }
      return left.label.compareTo(right.label);
    });

    return categories;
  }

  static List<PublicCatalogProduct> flattenNationwideProducts(
    List<PublicCatalogSection> sections,
  ) {
    return sections
        .expand((section) => section.products)
        .toList(growable: false);
  }

  static List<PublicCatalogProduct> productsInCategoryFromSections(
    List<PublicCatalogSection> sections,
    String categoryKey,
  ) {
    if (categoryKey.trim().isEmpty) {
      return const <PublicCatalogProduct>[];
    }

    return flattenNationwideProducts(sections)
        .where((product) => categoryKeyForProduct(product) == categoryKey)
        .toList(growable: false);
  }
}
