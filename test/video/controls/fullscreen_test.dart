import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

import 'kit_fakes.dart';

class _Delegate extends LeafFullscreenDelegate {
  int enters = 0, exits = 0;

  @override
  Future<void> enter(LeafFullscreenRequest request) async => enters++;

  @override
  Future<void> exit(LeafFullscreenRequest request) async => exits++;
}

class _LoggingAdapter extends KitAdapter {
  _LoggingAdapter(this.log) : super(surface: const _LoggingSurface());

  final List<String> log;

  @override
  void dispose() {
    log.add('adapter');
    super.dispose();
  }
}

class _LoggingSurface extends StatefulWidget {
  const _LoggingSurface();

  static List<String>? log;

  @override
  State<_LoggingSurface> createState() => _LoggingSurfaceState();
}

class _LoggingSurfaceState extends State<_LoggingSurface> {
  @override
  void dispose() {
    _LoggingSurface.log?.add('surface');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const CountingSurface();
}

class _Routes extends NavigatorObserver {
  int count = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => count++;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => count--;
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => count--;
}

final _routeLog = Expando<_Routes>();

Widget _app(Widget page, {GlobalKey<NavigatorState>? navigator}) => MaterialApp(
  navigatorKey: navigator,
  navigatorObservers: [if (navigator != null) _routeLog[navigator] = _Routes()],
  home: Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: SizedBox(width: 480, height: 270, child: page)),
  ),
);

int _routes(GlobalKey<NavigatorState> nav) => _routeLog[nav]!.count;

void main() {
  setUp(CountingSurface.reset);

  testWidgets('route mode: the same surface State across 5 cycles, no reload, no pause; F and Esc', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final adapter = KitAdapter(surface: const CountingSurface());
    var creates = 0;
    final delegate = _Delegate();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(
        LeafVideoPage(
          createAdapter: () {
            creates++;
            return adapter;
          },
          url: 'u',
          controls: LeafControlsSpec.desktop,
          fullscreenDelegate: delegate,
        ),
        navigator: nav,
      ),
    );
    await tester.pump();
    expect(adapter.plays, 1);
    expect(CountingSurface.inits, 1);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const ValueKey('leaf-control-fullscreen')));
      await tester.pump();
      await tester.pump();
      expect(_routes(nav), 2, reason: 'cycle $i: the fullscreen route is up');
      expect(find.byType(CountingSurface), findsOneWidget);
      expect(tester.getSize(find.byType(CountingSurface)).width, greaterThan(480), reason: 'it fills the screen now');
      if (i.isEven) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      }
      await tester.pump();
      await tester.pump();
      expect(_routes(nav), 1, reason: 'cycle $i: back inline');
      expect(tester.getSize(find.byType(CountingSurface)).width, 480);
    }
    expect(CountingSurface.inits, 1);
    expect(CountingSurface.disposes, 0);
    expect(creates, 1);
    expect(adapter.loads, 1);
    expect(adapter.pauses, 0, reason: 'its own fullscreen route never pauses the page');
    expect((delegate.enters, delegate.exits), (5, 5));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('system back exits fullscreen instead of popping', (tester) async {
    final adapter = KitAdapter(surface: const CountingSurface());
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(LeafVideoPage(createAdapter: () => adapter, url: 'u', controls: LeafControlsSpec.mobile), navigator: nav));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('leaf-control-fullscreen')));
    await tester.pump();
    await tester.pump();
    expect(_routes(nav), 2);
    expect(find.byKey(const ValueKey('leaf-control-back')), findsOneWidget, reason: 'the mobile fullscreen variant has back');
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump();
    expect(_routes(nav), 1);
    expect(CountingSurface.disposes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a dialog over fullscreen pauses, and closing it resumes', (tester) async {
    final adapter = KitAdapter(surface: const CountingSurface());
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(LeafVideoPage(createAdapter: () => adapter, url: 'u', controls: LeafControlsSpec.mobile), navigator: nav));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('leaf-control-fullscreen')));
    await tester.pump();
    await tester.pump();
    expect(adapter.pauses, 0);
    showDialog<void>(context: nav.currentContext!, builder: (_) => const AlertDialog(content: Text('hi')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(adapter.pauses, 1);
    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(adapter.plays, 2);
    expect(_routes(nav), 2, reason: 'still fullscreen');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('disposing the page while fullscreen removes the route, then disposes the adapter', (tester) async {
    final log = <String>[];
    _LoggingSurface.log = log;
    final adapter = _LoggingAdapter(log);
    final show = ValueNotifier(true);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(
        ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (context, on, _) =>
              on ? LeafVideoPage(createAdapter: () => adapter, url: 'u', controls: LeafControlsSpec.mobile) : const SizedBox.shrink(),
        ),
        navigator: nav,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('leaf-control-fullscreen')));
    await tester.pump();
    await tester.pump();
    show.value = false;
    await tester.pump();
    expect(log, isEmpty, reason: 'the route still holds the surface');
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(_routes(nav), 1);
    expect(log, ['surface', 'adapter']);
    _LoggingSurface.log = null;
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('in place inside a LeafViewer: no route, the delegate and the fullscreen variant', (tester) async {
    final adapter = KitAdapter(surface: const CountingSurface());
    final delegate = _Delegate();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        navigatorObservers: [_routeLog[nav] = _Routes()],
        home: LeafViewer(
          pageCount: 1,
          enableSwipeGestures: true,
          enableChrome: true,
          pageBuilder: (context, i) => LeafVideoPage(
            createAdapter: () => adapter,
            url: 'u',
            aspectRatio: 16 / 9,
            controls: LeafControlsSpec.mobile,
            fullscreenDelegate: delegate,
            actions: const LeafPlayerActions(title: 'Clip'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Clip'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('leaf-control-fullscreen')));
    await tester.pump();
    expect(_routes(nav), 1);
    expect(delegate.enters, 1);
    expect(find.text('Clip'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('leaf-control-back')));
    await tester.pump();
    expect(delegate.exits, 1);
    expect(CountingSurface.inits, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('availability: in place needs a delegate and (on touch) landscape video; disabled hides it', (tester) async {
    Future<bool> shows(LeafVideoPage page) async {
      await tester.pumpWidget(_app(page));
      await tester.pump();
      final found = find.byKey(const ValueKey('leaf-control-fullscreen')).evaluate().isNotEmpty;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
      return found;
    }

    LeafVideoPage page({LeafFullscreenMode? mode, LeafFullscreenDelegate? delegate, double? ratio}) => LeafVideoPage(
      createAdapter: KitAdapter.new,
      url: 'u',
      aspectRatio: ratio,
      controls: LeafControlsSpec.mobile,
      fullscreenMode: mode,
      fullscreenDelegate: delegate,
    );

    expect(await shows(page()), isTrue, reason: 'route mode outside a viewer');
    expect(await shows(page(mode: LeafFullscreenMode.inPlace, delegate: LeafFullscreenDelegate.none)), isFalse);
    expect(await shows(page(mode: LeafFullscreenMode.inPlace, delegate: _Delegate(), ratio: 16 / 9)), isTrue);
    expect(await shows(page(mode: LeafFullscreenMode.inPlace, delegate: _Delegate(), ratio: 9 / 16)), isFalse);
    expect(await shows(page(mode: LeafFullscreenMode.disabled)), isFalse);
  });

  testWidgets('legacy onFullscreenToggle becomes the in-place delegate', (tester) async {
    var toggles = 0;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _app(
        LeafVideoPage(
          createAdapter: KitAdapter.new,
          url: 'u',
          aspectRatio: 16 / 9,
          controls: LeafControlsSpec.mobile,
          onFullscreenToggle: () => toggles++,
        ),
        navigator: nav,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('leaf-control-fullscreen')));
    await tester.pump();
    expect(toggles, 1);
    expect(_routes(nav), 1);
    await tester.tap(find.byKey(const ValueKey('leaf-control-fullscreen')));
    await tester.pump();
    expect(toggles, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
  });
}
