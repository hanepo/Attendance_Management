import 'package:attendance_app/config/app_secrets.dart';
import 'package:attendance_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    AppSecrets.initSync();
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AttendanceApp());
    expect(find.byType(AttendanceApp), findsOneWidget);
  });
}
