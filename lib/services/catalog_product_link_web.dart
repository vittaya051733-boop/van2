import 'dart:html' as html;

import 'catalog_product_link.dart';

void replaceWebUrl(String path) {
  html.window.history.replaceState(null, '', path);
}

CatalogProductLinkTarget? readCurrentWebTarget() {
  return CatalogProductLink.parse(Uri.base);
}
