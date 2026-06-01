import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buildercam/main.dart';

void main() {
  testWidgets('BuilderCam app renders its shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BuilderCamApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Scope of Work Transcription'), findsOneWidget);
  });
}
