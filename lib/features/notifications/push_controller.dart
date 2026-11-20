import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/announcement_repository.dart';
import '../../data/repositories/push_notification_repository.dart';
import '../../data/repositories/support_repository.dart' show supportError;
import '../auth/auth_state.dart';

class PushDeviceState {
  final bool available, busy, registered, serverEnabled;
  final String message;
  const PushDeviceState({
    required this.available,
    this.busy = false,
    this.registered = false,
    this.serverEnabled = false,
    required this.message,
  });
}

class PushController extends StateNotifier<PushDeviceState>
    with WidgetsBindingObserver {
  final Ref ref;
  final PushNotificationRepository repository;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _disposed = false;
  int _generation = 0;
  PushController(this.ref, this.repository)
    : super(
        PushDeviceState(
          available: repository.available,
          message: repository.isAndroid
              ? 'Firebase belum dikonfigurasi untuk APK ini.'
              : 'Push HP tersedia pada aplikasi Android.',
        ),
      ) {
    if (!repository.available) return;
    WidgetsBinding.instance.addObserver(this);
    ref.listen(authNotifierProvider, (_, next) {
      if (next.user?.isCustomerLinked == true) {
        unawaited(sync());
      } else {
        _generation++;
        state = const PushDeviceState(
          available: true,
          message: 'Masuk dan hubungkan ID pelanggan untuk mengaktifkan notifikasi HP.',
        );
      }
    }, fireImmediately: true);
    _subscriptions.add(
      repository.tokenChanges.listen((token) {
        unawaited(sync(token: token));
      }, onError: (_) {}),
    );
    _subscriptions.add(
      repository.openedMessages.listen((message) {
        if (message.data['type'] == 'service_announcement') {
          ref.invalidate(announcementsProvider);
          ref.read(pushInboxRequestedProvider.notifier).state = true;
        }
      }),
    );
    _subscriptions.add(
      repository.foregroundMessages.listen((message) {
        if (message.data['type'] == 'service_announcement')
          ref.invalidate(announcementsProvider);
      }),
    );
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value == AppLifecycleState.resumed) unawaited(sync());
  }

  Future<void> sync({bool requestPermission = false, String? token}) async {
    if (_disposed || !repository.available) return;
    final user = ref.read(authNotifierProvider).user;
    if (user == null || !user.isCustomerLinked) return;
    final generation = ++_generation;
    state = const PushDeviceState(
      available: true,
      busy: true,
      message: 'Memeriksa notifikasi HP...',
    );
    try {
      if (requestPermission && !await repository.requestPermission()) {
        if (!_disposed && generation == _generation)
          state = const PushDeviceState(
            available: true,
            message: 'Izin notifikasi belum diberikan. Aktifkan izin SpaceNet di pengaturan Android.',
          );
        return;
      }
      final registered = await repository.registerDevice(
        user.uid,
        refreshedToken: token,
      );
      if (_disposed || generation != _generation) return;
      final server = await repository.serverEnabled();
      if (_disposed || generation != _generation) return;
      state = PushDeviceState(
        available: true,
        registered: registered,
        serverEnabled: server,
        message: !registered
            ? 'Aktifkan izin agar pemberitahuan masuk saat aplikasi tertutup.'
            : server
            ? 'HP ini terdaftar untuk menerima notifikasi layanan.'
            : 'HP sudah terdaftar. Pengiriman dari server belum diaktifkan.',
      );
    } catch (error) {
      if (!_disposed && generation == _generation)
        state = PushDeviceState(available: true, message: supportError(error));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}

final pushControllerProvider =
    StateNotifierProvider<PushController, PushDeviceState>(
      (ref) =>
          PushController(ref, ref.watch(pushNotificationRepositoryProvider)),
    );
