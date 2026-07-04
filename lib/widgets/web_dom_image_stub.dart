import 'package:flutter/widgets.dart';

Widget buildWebDomImage({
  required String url,
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  BorderRadius? borderRadius,
  Widget Function(BuildContext context)? errorBuilder,
}) {
  throw UnsupportedError('buildWebDomImage is web-only');
}
