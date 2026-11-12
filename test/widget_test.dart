// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spacenet/core/routing/app_router.dart';
import 'package:spacenet/core/supabase/supabase_runtime_config.dart';
import 'package:spacenet/data/repositories/otp_repository.dart';
import 'package:spacenet/features/auth/auth_state.dart';
import 'package:spacenet/features/auth/registration_controller.dart';
import 'package:spacenet/main.dart';

const _offlineSupabaseConfig = SupabaseRuntimeConfig(
  url: '',
  publishableKey: '',
);

ProviderContainer _offlineContainer() => ProviderContainer(
  overrides: [
    supabaseRuntimeConfigProvider.overrideWithValue(_offlineSupabaseConfig),
  ],
);

void main() {
  testWidgets('SpaceNet app loads splash and login flow', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseRuntimeConfigProvider.overrideWithValue(
            _offlineSupabaseConfig,
          ),
        ],
        child: const SpaceNetApp(),
      ),
    );

    expect(find.bySemanticsLabel('SpaceNet'), findsOneWidget);
    expect(find.text('Selamat datang'), findsNothing);

    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();

    expect(find.text('Selamat datang'), findsOneWidget);
  });

  testWidgets('all five main destinations open without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _signInAndLinkDemo(tester);
    expect(find.text('Nabila Sari'), findsOneWidget);

    for (final (label, heading) in [
      ('Tagihan', 'Tagihan'),
      ('Paket', 'Langganan'),
      ('Bantuan', 'Pusat bantuan'),
      ('Profil', 'Profil'),
      ('Beranda', 'Nabila Sari'),
    ]) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(find.text(heading), findsWidgets);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('payment instructions stay pending until server confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _signInAndLinkDemo(tester);

    await tester.tap(find.text('Bayar sekarang'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Virtual Account'));
    await tester.tap(find.text('Buat instruksi pembayaran'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.text('Instruksi demo'), findsOneWidget);
    expect(find.textContaining('8808 0012'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a support ticket can be submitted and opened', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _signInAndLinkDemo(tester);
    await tester.tap(find.text('Bantuan').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Buat laporan'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).last,
      'Koneksi terputus sejak pagi hari.',
    );
    await tester.ensureVisible(find.text('Kirim laporan'));
    await tester.tap(find.text('Kirim laporan'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('SPN-2043'), findsOneWidget);
    expect(find.text('Perkembangan laporan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all feature routes render at a narrow phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = _offlineContainer();
    addTearDown(container.dispose);
    await _signInAndLinkDemo(tester, container: container);

    final paths = [
      '/home',
      '/billing',
      '/subscription',
      '/support',
      '/profile',
      '/invoice/INV-2026-10-001',
      '/payment/INV-2026-10-001',
      '/subscription/upgrade',
      '/tickets/new',
      '/tickets/SPN-2042',
      '/transactions',
      '/transactions/TRX-009182',
      '/notifications',
      '/help',
      '/help/internet',
      '/settings',
      '/legal/privacy',
      '/legal/terms',
      '/about',
    ];
    for (final path in paths) {
      container.read(routerProvider).go(path);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Route $path should not overflow or fail.',
      );
    }
  });

  test(
    'local OTP rejects invalid codes and links only after verification',
    () async {
      final container = _offlineContainer();
      addTearDown(container.dispose);
      await container.read(authNotifierProvider.notifier).signInDemo();
      final registration = container.read(
        registrationControllerProvider.notifier,
      );
      await registration.requestOtp(
        customerId: '0012995',
        phoneNumber: '+6281255671201',
      );
      expect(
        container.read(registrationControllerProvider).debugOtp,
        isNotNull,
      );

      expect(await registration.verifyOtp('000000'), isFalse);
      expect(
        container.read(authNotifierProvider).user?.isCustomerLinked,
        isFalse,
      );

      final code = container.read(registrationControllerProvider).debugOtp!;
      expect(await registration.verifyOtp(code), isTrue);
      expect(
        container.read(authNotifierProvider).user?.isCustomerLinked,
        isTrue,
      );
    },
  );

  testWidgets(
    'testing mode with Supabase config allows OTP submit and navigates to home',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          supabaseRuntimeConfigProvider.overrideWithValue(
            const SupabaseRuntimeConfig(
              url: 'https://project.supabase.co',
              publishableKey: 'public-key',
              isTestingMode: true,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SpaceNetApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 2400));
      await tester.pumpAndSettle();

      // Klik masuk mode demo lokal
      expect(find.text('Masuk mode demo lokal'), findsOneWidget);
      await tester.tap(find.text('Masuk mode demo lokal'));
      await tester.pumpAndSettle();

      // Isi customer ID dan nomor ponsel
      await tester.enterText(find.byType(TextFormField).at(0), '0012995');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '+6281200001201',
      );
      await tester.tap(find.text('Kirim kode verifikasi'));
      await tester.pumpAndSettle();

      // Kode OTP muncul di debug card
      final code = container.read(registrationControllerProvider).debugOtp;
      expect(code, isNotNull);

      // Masukkan kode OTP dan submit
      await tester.enterText(find.byType(TextFormField).first, code!);
      await tester.tap(find.text('Verifikasi & hubungkan akun'));
      await tester.pumpAndSettle();

      for (final widget in find.byType(Text).evaluate()) {
        final text = (widget.widget as Text).data;
        if (text != null && text.isNotEmpty) {
          debugPrint('FOUND TEXT: $text');
        }
      }

      // Tampilan aplikasi (Beranda / HomeScreen) berhasil muncul!
      expect(find.text('Beranda'), findsWidgets);
      expect(find.text('Tagihan'), findsWidgets);
      expect(find.text('LANGGANAN AKTIF'), findsOneWidget);
      expect(find.text('Home Fiber 200 Mbps'), findsOneWidget);
      expect(
        container.read(authNotifierProvider).user?.isCustomerLinked,
        isTrue,
      );
    },
  );

  test('production OTP provider refuses billable SMS', () async {
    final otp = ProductionOtpDisabledRepository();
    await expectLater(
      otp.sendCode('+6281255671201'),
      throwsA(isA<OtpUnavailableException>()),
    );
    expect(otp.debugCode, isNull);
  });

  test('Supabase phone OTP stays disabled unless explicitly enabled', () {
    final container = ProviderContainer(
      overrides: [
        supabaseRuntimeConfigProvider.overrideWithValue(
          const SupabaseRuntimeConfig(
            url: 'https://project.supabase.co',
            publishableKey: 'public-key',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final otp = container.read(otpRepositoryProvider);
    expect(otp, isA<ProductionOtpDisabledRepository>());
    expect(otp.isDemo, isFalse);
    expect(otp.debugCode, isNull);
  });
}

Future<ProviderContainer> _signInAndLinkDemo(
  WidgetTester tester, {
  ProviderContainer? container,
}) async {
  final providers = container ?? _offlineContainer();
  if (container == null) addTearDown(providers.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: providers, child: const SpaceNetApp()),
  );
  await tester.pump(const Duration(milliseconds: 2400));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Masuk mode demo lokal'));
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextFormField).at(0), '0012995');
  await tester.enterText(find.byType(TextFormField).at(1), '+6281255671201');
  await tester.tap(find.text('Kirim kode verifikasi'));
  await tester.pumpAndSettle();
  final code = providers.read(registrationControllerProvider).debugOtp;
  expect(code, isNotNull);
  await tester.enterText(find.byType(TextFormField).first, code!);
  await tester.tap(find.text('Verifikasi & hubungkan akun'));
  await tester.pumpAndSettle();
  return providers;
}
