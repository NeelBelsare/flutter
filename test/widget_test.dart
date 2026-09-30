import 'package:flutter_test/flutter_test.dart';
import 'package:task_reminder/main.dart';

void main() {
  testWidgets('Task Reminder basic smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TaskReminderApp());

    // Verify that our app bar title and action button are present.
    expect(find.text('Task Reminder'), findsWidgets);
    expect(find.text('Set Reminder'), findsOneWidget);
  });
}
