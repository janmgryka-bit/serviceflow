import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:service_flow_ai/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('Home shows recent repairs and start button', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ServiceFlowApp());
    await tester.pump();
    // loadRepairs uses async SQLite; avoid pumpAndSettle (spinner never "settles").
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Start New Repair').evaluate().isNotEmpty) break;
    }

    expect(find.text('Start New Repair'), findsOneWidget);
    expect(find.text('Recent repairs'), findsOneWidget);
  });
}
