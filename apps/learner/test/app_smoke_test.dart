import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_store/local_store.dart';
import 'package:verbaseed_learner/src/app.dart';
import 'package:verbaseed_learner/src/data/providers.dart';

void main() {
  testWidgets('renders learner home', (tester) async {
    final database = VerbaSeedDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWith((ref) => database)],
        child: const VerbaSeedApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('首页'), findsWidgets);
    expect(find.text('今天的学习路径'), findsOneWidget);
  });
}
