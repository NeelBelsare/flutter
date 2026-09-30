import 'package:flutter_test/flutter_test.dart';
import 'package:task_reminder/main.dart';

void main() {
  testWidgets('DevOps Assistant smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DevOpsAssistantApp());
    expect(find.text('DevOps & Manager Dashboard'), findsOneWidget);
  });
}
