import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:progress_tracker/tracker_api.dart';
import 'package:progress_tracker/tracker_page.dart';

class FakeTrackerApi extends TrackerApi {
  Map<String, dynamic>? submitted;
  bool fail = false;
  Map<String, dynamic> data() => {
    'date': '2026-10-23',
    'phase': 'Foundation',
    'planned_hours': 8,
    'schedule_note': '',
    'tasks': [
      {'id': '0', 'label': 'Subject A', 'text': 'Article 15 equality'},
    ],
    'update': submitted,
    'result': submitted == null
        ? null
        : {
            'score': 85,
            'coverage': 100,
            'hours_progress': 50,
            'explanation': 'Local estimate',
            'breakdown': [],
          },
    'summary': {
      'score': submitted == null ? 0 : 1,
      'updated_days': submitted == null ? 0 : 1,
      'total_days': 300,
      'logged_hours': submitted?['hours'] ?? 0,
      'planned_hours': 2000,
    },
  };
  @override
  Future<Map<String, dynamic>> plan() async => {
    'dates': ['2026-10-23'],
  };
  @override
  Future<Map<String, dynamic>> day(String date) async => data();
  @override
  Future<Map<String, dynamic>> save(Map<String, dynamic> update) async {
    if (fail) throw TrackerException('Server unavailable');
    submitted = update;
    return data();
  }
}

void main() {
  testWidgets('Update form validates, posts totals and updates progress', (
    tester,
  ) async {
    final api = FakeTrackerApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TrackerPage(api: api)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0.0%'), findsOneWidget);
    await tester.tap(find.text('Update Tracker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save progress'));
    await tester.pumpAndSettle();
    expect(api.submitted, isNull);
    expect(find.text('Enter a number from 0 to 24.'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '4');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Studied Article 15 equality',
    );
    await tester.tap(find.text('Save progress'));
    await tester.pumpAndSettle();
    expect(api.submitted?['status'], 'Completed');
    expect(api.submitted?['hours'], 4);
    expect(find.text('85.0%'), findsOneWidget);
    await tester.tap(find.text('Update Tracker'));
    await tester.pumpAndSettle();
    expect(find.text('Studied Article 15 equality'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Failed save preserves input and previous score', (tester) async {
    final api = FakeTrackerApi()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TrackerPage(api: api)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update Tracker'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '2');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Reviewed equality',
    );
    await tester.tap(find.text('Save progress'));
    await tester.pumpAndSettle();
    expect(find.text('Server unavailable'), findsOneWidget);
    expect(find.text('Reviewed equality'), findsOneWidget);
    expect(api.submitted, isNull);
    expect(find.text('0.0%'), findsOneWidget);
  });
}
