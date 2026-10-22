import 'package:web/web.dart' as web;

void setDocumentTitle(String title) {
  web.document.title = title;
}

/// Replaces the browser-tab icon. [href] is a path served from `web/`, such as
/// `icons/UnityPillarTransparent.png`.
void setDocumentFavicon(String href, {String type = 'image/png'}) {
  final head = web.document.head;
  if (head == null) return;
  final existing = web.document.querySelectorAll(
    'link[rel="icon"], link[rel="shortcut icon"], link[rel="apple-touch-icon"]',
  );
  for (var i = existing.length - 1; i >= 0; i--) {
    final node = existing.item(i);
    node?.parentNode?.removeChild(node);
  }
  head.appendChild(
    web.HTMLLinkElement()
      ..rel = 'icon'
      ..type = type
      ..href = href,
  );
  head.appendChild(
    web.HTMLLinkElement()
      ..rel = 'apple-touch-icon'
      ..href = href,
  );
}
