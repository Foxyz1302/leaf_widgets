import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

class _DemoImage {
  const _DemoImage(this.url, this.size);
  final String url;
  final Size size;
}

const _demoImages = [
  _DemoImage(
    'https://file.pawchive.pw/data/82/91/829126892beebd0a7ff5b5a398e63a760b53162b15323ce900d944d126aa69ec.png?f=829126892beebd0a7ff5b5a398e63a760b53162b15323ce900d944d126aa69ec.png',
    Size(1457, 2048),
  ),
  _DemoImage(
    'https://file.pawchive.pw/data/09/f4/09f4e606de27786cf633282b8d3e194b62a0b6859368f8ac38d28300972f763c.jpeg?f=09f4e606de27786cf633282b8d3e194b62a0b6859368f8ac38d28300972f763c.jpeg',
    Size(8500, 6000),
  ),
  _DemoImage(
    'https://file.pawchive.pw/data/79/e9/79e996f02a2700dbc38c590057d027b7566608be8e87e49950cec165d6f8b525.png?f=79e996f02a2700dbc38c590057d027b7566608be8e87e49950cec165d6f8b525.png',
    Size(3267, 1634),
  ),
];

Size _containSize(Size viewport, Size image) {
  final scale = viewport.width / image.width < viewport.height / image.height
      ? viewport.width / image.width
      : viewport.height / image.height;
  return Size(image.width * scale, image.height * scale);
}

void openLeafViewerDemo(BuildContext context, {bool enableSwipeGestures = false}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      // Transparent route so the scrim fade reveals the gallery behind it,
      // like the real app's fullscreen viewer.
      opaque: false,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
      pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            LeafViewer(
              pageCount: _demoImages.length,
              enableSwipeGestures: enableSwipeGestures,
              backgroundBuilder: (context, progress) =>
                  Container(color: Colors.black.withValues(alpha: 0.87 * (1 - progress))),
              pageBuilder: (context, index) {
                final demo = _demoImages[index];
                return LayoutBuilder(
                  builder: (context, constraints) {
                    return LeafZoomable(
                      childSize: _containSize(constraints.biggest, demo.size),
                      originalSize: demo.size,
                      child: Image(
                        image: _HeaderImageProvider(demo.url),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) => const ColoredBox(
                          color: Color(0xFF1A1A1A),
                          child: Center(child: Icon(Icons.broken_image, color: Colors.white38)),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close),
                color: Colors.white70,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// ImageProvider for `file.pawchive.pw` (requires Referer + browser UA).
class _HeaderImageProvider extends ImageProvider<_HeaderImageProvider> {
  const _HeaderImageProvider(this.url);

  final String url;

  @override
  bool operator ==(Object other) => other is _HeaderImageProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  Future<_HeaderImageProvider> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_HeaderImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(codec: _loadAsync(decode), scale: 1.0);
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('Referer', 'https://pawchive.pw/');
      request.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('GET $url -> ${response.statusCode}', uri: Uri.parse(url));
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } finally {
      client.close();
    }
  }
}
