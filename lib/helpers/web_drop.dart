/// Conditional import: uses real dart:html on web, no-op stub elsewhere.
export 'web_drop_stub.dart'
    if (dart.library.html) 'web_drop_real.dart';
