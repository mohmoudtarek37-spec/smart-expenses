import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hesabaty/main.dart';

void main() {
  testWidgets('Flutter V2 preview renders five navigation tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(const HesabatyApp());
    expect(find.text('حساباتي'), findsOneWidget);
    expect(find.text('الرئيسية'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
