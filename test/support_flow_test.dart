import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:spacenet/core/supabase/supabase_runtime_config.dart';
import 'package:spacenet/data/repositories/auth_repository.dart';
import 'package:spacenet/data/repositories/support_repository.dart';
import 'package:spacenet/features/support/support_screens.dart';
import 'package:spacenet/features/screens/detail_screens.dart'
    show NewTicketScreen;

import 'helpers/fake_support_repository.dart';

class _TestAuth implements AuthRepository {
  @override
  bool get isDemo => false;
  @override
  AuthSessionUser get currentSession => const AuthSessionUser(
    uid: 'test-customer',
    email: 'test@example.invalid',
    displayName: 'Pelanggan pengujian',
    photoUrl: null,
    customerId: '0012995',
  );
  @override
  Stream<AuthSessionUser?> get authStateChanges => Stream.value(currentSession);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  FakeSupportRepository repository,
  Widget screen, {
  bool admin = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_TestAuth()),
      supabaseRuntimeConfigProvider.overrideWithValue(
        const SupabaseRuntimeConfig(url: '', publishableKey: ''),
      ),
      supportRepositoryProvider.overrideWithValue(repository),
      supportAdminProvider.overrideWith((ref) async => admin),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  test(
    'photo validation accepts supported signatures and rejects other files',
    () {
      expect(
        supportPhotoType(Uint8List.fromList([255, 216, 255, 0])).$2,
        'image/jpeg',
      );
      expect(
        () => supportPhotoType(Uint8List.fromList([60, 104, 116, 109, 108])),
        throwsStateError,
      );
      expect(
        newSupportId(),
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    },
  );

  testWidgets('failed submit retains the report and succeeds when retried', (
    tester,
  ) async {
    final repo = FakeSupportRepository()..failCreate = true;
    final router = GoRouter(
      initialLocation: '/new',
      routes: [
        GoRoute(path: '/new', builder: (_, _) => const NewTicketScreen()),
        GoRoute(
          path: '/tickets/:id',
          builder: (_, state) =>
              TicketDetailScreen(ticketId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_TestAuth()),
        supportRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      'Internet terputus sejak pagi.',
    );
    await tester.ensureVisible(find.text('Kirim laporan'));
    await tester.tap(find.text('Kirim laporan'));
    await tester.pumpAndSettle();
    expect(repo.reports, isEmpty);
    expect(find.text('Internet terputus sejak pagi.'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/new');
    repo.failCreate = false;
    await tester.tap(find.text('Kirim laporan'));
    await tester.pumpAndSettle();
    expect(repo.reports.length, 1);
    expect(find.text('SPN-002043'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('non-admin cannot load the admin report list', (tester) async {
    final repo = FakeSupportRepository();
    await _mount(tester, repo, const AdminReportsScreen());
    expect(find.text('Akses admin diperlukan'), findsOneWidget);
    expect(repo.reads, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'admin saves status and customer sees the persisted handling note',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeSupportRepository()..admin = true;
      await repo.create(
        id: 'report-one',
        category: 'Internet mati',
        description: 'Koneksi terputus sejak pagi.',
      );
      final container = await _mount(
        tester,
        repo,
        const TicketDetailScreen(ticketId: 'report-one', admin: true),
        admin: true,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dalam penanganan').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'Teknisi sedang memeriksa kabel.',
      );
      await tester.tap(find.text('Simpan pembaruan'));
      await tester.pumpAndSettle();
      expect(repo.reports['report-one']!.ticket.status, 'in_progress');
      expect(repo.reports['report-one']!.ticket.version, 2);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: TicketDetailScreen(ticketId: 'report-one'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Teknisi sedang memeriksa kabel.'), findsOneWidget);
      expect(find.text('Dalam penanganan'), findsWidgets);
      expect(find.text('Simpan pembaruan'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('customer detail automatically reloads changes from admin', (
    tester,
  ) async {
    final repo = FakeSupportRepository()..admin = true;
    await repo.create(
      id: 'report-two',
      category: 'Internet mati',
      description: 'Koneksi terputus sejak pagi.',
    );
    await _mount(
      tester,
      repo,
      const TicketDetailScreen(ticketId: 'report-two'),
    );
    await repo.update(
      repo.reports['report-two']!.ticket,
      'resolved',
      'Jaringan sudah kembali normal.',
    );
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('Selesai'), findsWidgets);
    expect(find.text('Batalkan laporan'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
