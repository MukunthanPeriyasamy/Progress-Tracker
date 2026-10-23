import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:progress_tracker/main.dart';
import 'package:progress_tracker/app_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var consent = false;
  var failSave = false;
  var saved = <String>[];
  var opened = <String>[];
  setUp(() {
    consent = false;
    failSave = false;
    saved = [];
    opened = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppRepository.channel, (call) async {
          switch (call.method) {
            case 'permissions':
              return {
                'accessibility': true,
                'notifications': false,
                'overlay': false,
              };
            case 'openSettings':
              opened.add((call.arguments as Map)['target'] as String);
              return null;
            case 'preferences':
              return {'consent': consent, 'selected': saved};
            case 'consent':
              consent = true;
              return null;
            case 'apps':
              return [
                {
                  'package': 'com.example.social',
                  'name': 'Social',
                  'system': false,
                },
                {
                  'package': 'com.example.settings',
                  'name': 'Settings',
                  'system': true,
                },
              ];
            case 'save':
              if (failSave) throw PlatformException(code: 'SAVE_FAILED');
              saved = List<String>.from(call.arguments as List);
              return null;
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppRepository.channel, null),
  );

  testWidgets('Consent, selection, search, filter and Home share state', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('App Block').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Show installed apps'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show installed apps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(consent, isFalse);
    await tester.scrollUntilVisible(
      find.text('Show installed apps'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show installed apps'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow access'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Social'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Social'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(saved, ['com.example.social']);
    await tester.scrollUntilVisible(
      find.byType(TextField),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('No apps found'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No apps found'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(TextField),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter apps'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<String> &&
            widget.value == 'Selected',
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Social'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Social'), findsOneWidget);
    expect(find.text('System app'), findsNothing);
    await tester.tap(find.text('Home').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Social'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.text('Social'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Social'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Saved selections restore and failures leave selection intact', (
    tester,
  ) async {
    consent = true;
    saved = ['com.example.social'];
    failSave = true;
    await tester.pumpWidget(MyApp(clock: () => DateTime(2026, 10, 25, 21)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('App Block').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Social'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Social'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    expect(
      find.text('Selection could not be saved. Please retry.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Settings disclosure and native intent dispatch', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('App Block').last);
    await tester.pumpAndSettle();
    final settings = find.widgetWithText(TextButton, 'Settings').first;
    await tester.ensureVisible(settings);
    await tester.pumpAndSettle();
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(find.text('Enable app blocking?'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(opened, ['accessibility']);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Selections stay locked through Sunday and unlock at timer end', (
    tester,
  ) async {
    consent = true;
    saved = ['com.example.social'];
    var time = DateTime(2026, 10, 25, 19, 59, 59);
    await tester.pumpWidget(MyApp(clock: () => time));
    await tester.pumpAndSettle();
    await tester.tap(find.text('App Block').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Social'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch).first).onChanged, isNull);
    expect(find.text('Locked until Sunday 8 PM'), findsOneWidget);
    time = DateTime(2026, 10, 25, 20);
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<Switch>(find.byType(Switch).first).onChanged,
      isNotNull,
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
