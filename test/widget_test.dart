import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bruges_finanzas_360/data/movement_repository.dart';
import 'package:bruges_finanzas_360/main.dart';

void main() {
  testWidgets('shows the Bruges finance identity and mobile navigation', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repository = MovementRepository.inMemory();
    await tester.pumpWidget(MyApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.text('BRUGES FINANZAS 360'), findsOneWidget);
    expect(find.text('Tus finanzas, bajo tu control.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Resumen'), findsOneWidget);
    expect(find.text('Movimientos'), findsOneWidget);
  });

  testWidgets('creates a manual movement and shows its pending state', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repository = MovementRepository.inMemory();
    await tester.pumpWidget(MyApp(repository: repository));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byTooltip('Agregar movimiento'), findsOneWidget);
    await tester.tap(find.byTooltip('Agregar movimiento'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Nuevo movimiento'),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('movement-amount')), '25000');
    await tester.enterText(
      find.byKey(const Key('movement-category')),
      'Mercado',
    );
    await tester.tap(find.text('Guardar movimiento'));
    await tester.pumpAndSettle();

    expect(find.text('Mercado'), findsOneWidget);
    expect(
      find.textContaining('Guardado local, sin sincronización en nube'),
      findsOneWidget,
    );
  });
}
