import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacenet/data/repositories/announcement_repository.dart';
import 'package:spacenet/features/notifications/announcement_screens.dart';

class _Announcements implements AnnouncementRepository {
  int revision = 1;
  int readVersion = 0;
  String status = 'in_progress';
  bool archived = false;
  bool enabled = true;
  @override
  Future<List<ServiceAnnouncement>> load() async => [
    ServiceAnnouncement.fromMap({
      'id': 'notice-one',
      'kind': 'outage',
      'title': 'Gangguan jaringan area uji',
      'message': 'Tim teknisi sedang menangani gangguan jaringan.',
      'area': 'Area uji',
      'status': status,
      'version': revision,
      'archived': archived,
      'updated_at': '2026-11-20T10:00:00Z',
    }, readVersion),
  ];
  @override
  Future<void> markRead(ServiceAnnouncement item) async {
    readVersion = item.version;
  }

  @override
  Future<bool> preference() async => enabled;
  @override
  Future<void> setPreference(bool value) async {
    enabled = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(_Announcements repo) => ProviderContainer(
  overrides: [
    announcementRepositoryProvider.overrideWithValue(repo),
    announcementsProvider.overrideWith((ref) => repo.load()),
    servicePreferenceProvider.overrideWith((ref) => repo.preference()),
  ],
);

void main() {
  testWidgets(
    'read status survives reopening and an updated announcement becomes unread',
    (tester) async {
      final repo = _Announcements();
      final container = _container(repo);
      addTearDown(container.dispose);
      Future<void> show() async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: NotificationsScreen()),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show();
      expect(find.text('1 belum dibaca'), findsOneWidget);
      await tester.tap(find.text('Tandai dibaca').first);
      await tester.pumpAndSettle();
      expect(repo.readVersion, 1);
      expect(find.text('0 belum dibaca'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await show();
      expect(find.text('0 belum dibaca'), findsOneWidget);
      repo.revision = 2;
      repo.status = 'resolved';
      container.invalidate(announcementsProvider);
      await tester.pumpAndSettle();
      expect(find.text('1 belum dibaca'), findsOneWidget);
      expect(find.text('Selesai'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'resolved and archived incidents do not show an active home banner',
    (tester) async {
      final repo = _Announcements();
      final container = _container(repo);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: ServiceAnnouncementBanner()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gangguan jaringan area uji'), findsOneWidget);
      repo.status = 'resolved';
      container.invalidate(announcementsProvider);
      await tester.pumpAndSettle();
      expect(find.text('Gangguan jaringan area uji'), findsNothing);
      repo.status = 'in_progress';
      repo.archived = true;
      container.invalidate(announcementsProvider);
      await tester.pumpAndSettle();
      expect(find.text('Gangguan jaringan area uji'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'service preference disables banners but retains notification history',
    (tester) async {
      final repo = _Announcements()..enabled = false;
      final container = _container(repo);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: ServiceAnnouncementBanner()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gangguan jaringan area uji'), findsNothing);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: NotificationsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Gangguan jaringan area uji'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
