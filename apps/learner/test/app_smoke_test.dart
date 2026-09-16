import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verbaseed_learner/src/app.dart';

void main() {
  testWidgets('renders learner home', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: VerbaSeedApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsWidgets);
    expect(find.text('今天的学习路径'), findsOneWidget);
  });
}
