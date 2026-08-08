import 'dart:async';

import 'package:web/web.dart' as web;

void triggerGoogleMapsWebResize() {
  web.window.dispatchEvent(web.Event('resize'));
}

void scheduleGoogleMapsWebResize({Duration delay = Duration.zero}) {
  if (delay == Duration.zero) {
    triggerGoogleMapsWebResize();
    return;
  }
  unawaited(
    Future<void>.delayed(delay, triggerGoogleMapsWebResize),
  );
}
