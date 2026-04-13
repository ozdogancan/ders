/// Web-only drag-and-drop handler.
/// Uses raw JS injection + dart:js callback bridge because
/// dart:html body listeners don't fire under CanvasKit's glasspane.
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:typed_data';

void Function(Uint8List bytes)? _onDropCallback;
void Function(bool hovering)? _onHoverCallback;

void registerWebDrop({
  required void Function(Uint8List bytes) onDrop,
  required void Function(bool hovering) onHover,
}) {
  unregisterWebDrop();
  _onDropCallback = onDrop;
  _onHoverCallback = onHover;

  // Expose Dart callbacks to JS global scope
  js.context['__koalaDartOnDrop'] = js.JsFunction.withThis((_, dynamic buf) {
    final bytes = (buf as ByteBuffer).asUint8List();
    _onDropCallback?.call(bytes);
  });

  js.context['__koalaDartOnHover'] = js.JsFunction.withThis((_, dynamic h) {
    _onHoverCallback?.call(h == true || h.toString() == 'true');
  });

  // Inject JS script that listens in capture phase on glasspane + body + document
  final script = html.ScriptElement()
    ..id = 'koala-drop-bridge'
    ..text = r'''
(function() {
  if (window.__koalaDropCleanup) window.__koalaDropCleanup();

  var gp = document.querySelector('flt-glass-pane');
  var shadow = gp ? gp.shadowRoot : null;
  var targets = [document.body, document];
  if (gp) targets.push(gp);
  if (shadow) targets.push(shadow);

  function onDragOver(e) {
    e.preventDefault();
    e.stopPropagation();
    if (window.__koalaDartOnHover) window.__koalaDartOnHover(null, true);
  }
  function onDragEnter(e) {
    e.preventDefault();
    if (window.__koalaDartOnHover) window.__koalaDartOnHover(null, true);
  }
  function onDragLeave(e) {
    e.preventDefault();
    if (window.__koalaDartOnHover) window.__koalaDartOnHover(null, false);
  }
  function onDrop(e) {
    e.preventDefault();
    e.stopPropagation();
    if (window.__koalaDartOnHover) window.__koalaDartOnHover(null, false);

    var files = e.dataTransfer ? e.dataTransfer.files : null;
    if (!files || files.length === 0) return;
    var file = files[0];
    if (!file.type.startsWith('image/')) return;

    var reader = new FileReader();
    reader.onload = function() {
      if (window.__koalaDartOnDrop) window.__koalaDartOnDrop(null, reader.result);
    };
    reader.readAsArrayBuffer(file);
  }

  targets.forEach(function(t) {
    t.addEventListener('dragover', onDragOver, true);
    t.addEventListener('dragenter', onDragEnter, true);
    t.addEventListener('dragleave', onDragLeave, true);
    t.addEventListener('drop', onDrop, true);
  });

  window.__koalaDropCleanup = function() {
    targets.forEach(function(t) {
      t.removeEventListener('dragover', onDragOver, true);
      t.removeEventListener('dragenter', onDragEnter, true);
      t.removeEventListener('dragleave', onDragLeave, true);
      t.removeEventListener('drop', onDrop, true);
    });
    delete window.__koalaDartOnDrop;
    delete window.__koalaDartOnHover;
    delete window.__koalaDropCleanup;
  };

  console.log('[KoalaDrop] Listeners registered, glasspane:', !!gp, 'shadow:', !!shadow);
})();
''';
  html.document.body?.append(script);
}

void unregisterWebDrop() {
  _onDropCallback = null;
  _onHoverCallback = null;
  try {
    if (js.context.hasProperty('__koalaDropCleanup')) {
      js.context.callMethod('__koalaDropCleanup', []);
    }
  } catch (_) {}
  html.document.getElementById('koala-drop-bridge')?.remove();
}
