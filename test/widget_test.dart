import 'package:estate_app/main.dart';
import 'package:estate_app/store.dart';
import 'package:estate_app/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatRupiah', () {
    expect(formatRupiah(250000), 'Rp 250.000');
    expect(formatRupiah(1500000), 'Rp 1.500.000');
    expect(formatRupiah(0), 'Rp 0');
  });

  testWidgets('warga bisa login dan membayar tagihan', (tester) async {
    await tester.pumpWidget(const EstateApp());
    expect(find.text('Griya Kita'), findsOneWidget);

    await tester.ensureVisible(find.text('Masuk'));
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();
    expect(find.text('Halo, Budi Santoso'), findsOneWidget);

    final before = store.unpaidTotal('R1');
    expect(before, greaterThan(0));

    // Buka tab Tagihan dan bayar tagihan yang belum lunas.
    await tester.tap(find.text('Tagihan'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Belum bayar'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Jatuh tempo').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('QRIS'));
    await tester.pumpAndSettle();

    expect(store.unpaidTotal('R1'), before - monthlyFee);
  });
}
