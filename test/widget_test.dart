// Smoke test for a self-contained widget.
//
// The whole app is deliberately *not* pumped here: LabCompilerApp reads global
// providers, and NetworkDiagnostics starts real HTTP probes as soon as it is
// constructed, which would make a widget test slow and network-dependent.
// The pure threshold / loss / lag logic is covered by
// test/diagnostic_report_test.dart instead.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lab_compiler_app/widgets/trial_counter.dart';

void main() {
  testWidgets('TrialCounter increments and resets its local count',
      (WidgetTester tester) async {
    // Build the widget inside a MaterialApp (Theme/Scaffold needed by Card).
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TrialCounter())),
    );

    // Local state starts at zero and the label is rendered.
    expect(find.text('Trial Count'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.text('Record Trial'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
  });
}

