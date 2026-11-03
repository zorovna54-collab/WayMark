import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waymark/features/auth/login/login_page.dart';
import 'package:waymark/features/scanner/public_map_entry_page.dart';

void main() {
  for (final keyboard in [false, true]) {
    testWidgets(
      'Login remains usable at 320px and text scale 2 with keyboard=$keyboard',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
                viewInsets: EdgeInsets.only(bottom: keyboard ? 240 : 0),
              ),
              child: child!,
            ),
            home: const LoginPage(),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        // Guest/Public entry remains reachable without attempting authentication.
        await t.ensureVisible(find.byKey(const Key('guest-public-map')));
        await t.tap(find.byKey(const Key('guest-public-map')));
        await t.pumpAndSettle();
        expect(find.byType(PublicMapEntryPage), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
