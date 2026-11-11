import 'package:estate_app/main.dart';
import 'package:estate_app/models.dart';
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
    expect(find.text('Amani'), findsOneWidget);

    await tester.ensureVisible(find.text('Masuk'));
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();
    expect(find.text('Halo,'), findsOneWidget);
    expect(find.text('Budi Santoso'), findsOneWidget);

    final before = store.unpaidTotal('R1');
    expect(before, greaterThan(0));

    // Buka tab Tagihan, pilih tagihan, lalu dapat kode unik transfer.
    await tester.tap(find.text('Tagihan'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Bayar'));
    await tester.pumpAndSettle();
    expect(find.text('Pilih tagihan yang dibayar'), findsOneWidget);
    await tester.tap(find.text('Buat kode bayar'));
    await tester.pumpAndSettle();
    // Konfirmasi ulang sebelum kode dibuat.
    expect(find.text('Periksa kembali, apakah semua sudah benar?'),
        findsOneWidget);
    await tester.tap(find.text('Ya, buat kode bayar'));
    await tester.pumpAndSettle();

    final p = store.activePaymentOf('R1')!;
    expect(p.total, before + p.uniqueCode);
    expect(find.text('+${p.uniqueCode.toString().padLeft(3, '0')}'),
        findsOneWidget);
    // Belum lunas sebelum diverifikasi pengelola.
    expect(store.unpaidTotal('R1'), before);
  });

  testWidgets('tarik ke bawah untuk refresh & tab ikut berubah', (tester) async {
    await store.logout();
    store.login(Role.warga, residentId: 'R2');
    await tester.pumpWidget(const EstateApp());
    await tester.pumpAndSettle();

    // Tab Keluhan: daftar pendek/kosong tetap bisa ditarik untuk refresh.
    await tester.tap(find.text('Keluhan'));
    await tester.pumpAndSettle();
    await tester.fling(
        find.byType(Scrollable).last, const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(RefreshProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(RefreshProgressIndicator), findsNothing);

    // Fitur keluhan dimatikan: tab Keluhan langsung hilang tanpa login ulang.
    store.complaintsEnabled = false;
    await store.refresh();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(NavigationDestination, 'Keluhan'), findsNothing);
    expect(find.widgetWithText(NavigationDestination, 'Tamu'), findsOneWidget);
    store.complaintsEnabled = true;
    await store.refresh();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(NavigationDestination, 'Keluhan'), findsOneWidget);
  });
}

