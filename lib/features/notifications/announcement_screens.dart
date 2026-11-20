import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_components.dart';
import '../../data/models/support_ticket.dart' show supportDate;
import '../../data/repositories/announcement_repository.dart';
import '../../data/repositories/support_repository.dart';
import '../support/support_screens.dart' show SupportAdminGate;
import 'push_controller.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(servicePreferenceProvider).valueOrNull ?? false;
    final unread = (ref.watch(announcementsProvider).valueOrNull ?? [])
        .where((item) => item.unread && !item.archived)
        .length;
    return IconButton.filledTonal(
      tooltip: 'Notifikasi',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: enabled && unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    );
  }
}

class ServiceAnnouncementBanner extends ConsumerWidget {
  const ServiceAnnouncementBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(servicePreferenceProvider).valueOrNull ?? false)) {
      return const SizedBox.shrink();
    }
    final active = (ref.watch(announcementsProvider).valueOrNull ?? [])
        .where((item) => !item.archived && item.status != 'resolved')
        .toList();
    if (active.isEmpty) return const SizedBox.shrink();
    final item = active.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: SurfaceCard(
        onTap: () => context.push('/notifications'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              item.kind == 'outage'
                  ? Icons.wifi_off
                  : Icons.engineering_outlined,
              color: AppTheme.warning,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('Area: ${item.area}'),
                  Text(announcementStatuses[item.status] ?? item.status),
                  Text(
                    active.length > 1
                        ? '${active.length} informasi layanan aktif. Lihat selengkapnya.'
                        : 'Ketuk untuk melihat informasi lengkap.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _saving = false;
  Future<void> _read(List<ServiceAnnouncement> items) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final repository = ref.read(announcementRepositoryProvider);
      for (final item in items.where((item) => item.unread && !item.archived)) {
        await repository.markRead(item);
      }
    } catch (error) {
      if (mounted) showAppMessage(context, supportError(error));
    } finally {
      if (mounted) {
        ref.invalidate(announcementsProvider);
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(announcementsProvider);
    final items = (state.valueOrNull ?? [])
        .where((item) => !item.archived)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
        actions: [
          TextButton(
            onPressed: _saving || !items.any((item) => item.unread)
                ? null
                : () => _read(items),
            child: const Text('Tandai dibaca'),
          ),
        ],
      ),
      body: state.when(
        loading: () => const LoadingState(),
        error: (_, _) =>
            ErrorState(onRetry: () => ref.invalidate(announcementsProvider)),
        data: (_) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(announcementsProvider);
            await ref.read(announcementsProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '${items.where((item) => item.unread).length} belum dibaca',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const EmptyState(
                  title: 'Belum ada notifikasi',
                  message: 'Informasi perbaikan dan gangguan massal akan muncul di sini.',
                ),
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AnnouncementCard(
                    item: item,
                    action: item.unread
                        ? TextButton(
                            onPressed: _saving ? null : () => _read([item]),
                            child: const Text('Tandai dibaca'),
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final ServiceAnnouncement item;
  final Widget? action;
  const _AnnouncementCard({required this.item, this.action});
  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusPill(
              label: announcementKinds[item.kind] ?? item.kind,
              color: item.kind == 'outage'
                  ? AppTheme.warning
                  : AppTheme.primaryBlue,
            ),
            StatusPill(
              label: item.archived
                  ? 'Diarsipkan'
                  : announcementStatuses[item.status] ?? item.status,
              color: item.status == 'resolved'
                  ? AppTheme.success
                  : AppTheme.primaryBlue,
            ),
            if (item.unread && !item.archived)
              const Text(
                'Baru',
                style: TextStyle(
                  color: AppTheme.primaryBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(item.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Area terdampak: ${item.area}'),
        const SizedBox(height: 8),
        SelectableText(item.message),
        const SizedBox(height: 12),
        Text(
          'Diperbarui ${supportDate(item.updatedAt)}',
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        ?action,
      ],
    ),
  );
}

class AdminAnnouncementsScreen extends ConsumerWidget {
  const AdminAnnouncementsScreen({super.key});
  Future<void> _edit(BuildContext context, ServiceAnnouncement? item) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AnnouncementEditor(item: item),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('Pengumuman layanan'),
      leading: IconButton(
        tooltip: 'Laporan pelanggan',
        onPressed: () => context.go('/admin/reports'),
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: SupportAdminGate(
      child: Consumer(
        builder: (context, ref, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: () => _edit(context, null),
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Buat pengumuman'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Pengumuman ditampilkan kepada seluruh pelanggan. Isi area terdampak agar informasinya jelas.',
              ),
            ),
            Expanded(
              child: ref
                  .watch(announcementsProvider)
                  .when(
                    loading: () => const LoadingState(),
                    error: (_, _) => ErrorState(
                      onRetry: () => ref.invalidate(announcementsProvider),
                    ),
                    data: (items) => RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(announcementsProvider);
                        await ref.read(announcementsProvider.future);
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(20),
                        children: [
                          if (items.isEmpty)
                            const EmptyState(
                              title: 'Belum ada pengumuman',
                              message: 'Buat informasi perbaikan atau gangguan massal untuk pelanggan.',
                            ),
                          ...items.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _AnnouncementCard(
                                item: item,
                                action: TextButton.icon(
                                  onPressed: () => _edit(context, item),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Perbarui pengumuman'),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AnnouncementEditor extends ConsumerStatefulWidget {
  final ServiceAnnouncement? item;
  const _AnnouncementEditor({this.item});
  @override
  ConsumerState<_AnnouncementEditor> createState() =>
      _AnnouncementEditorState();
}

class _AnnouncementEditorState extends ConsumerState<_AnnouncementEditor> {
  final _form = GlobalKey<FormState>();
  late final _id = widget.item?.id ?? newSupportId();
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _message = TextEditingController(text: widget.item?.message ?? '');
  late final _area = TextEditingController(
    text: widget.item?.area ?? 'Seluruh area layanan',
  );
  late String _kind = widget.item?.kind ?? 'maintenance';
  late String _status = widget.item?.status ?? 'in_progress';
  late bool _archived = widget.item?.archived ?? false;
  bool _saving = false;
  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    _area.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(announcementRepositoryProvider)
          .save(
            id: _id,
            version: widget.item?.version ?? 0,
            kind: _kind,
            title: _title.text.trim(),
            message: _message.text.trim(),
            area: _area.text.trim(),
            status: _status,
            archived: _archived,
          );
      if (mounted) {
        ref.invalidate(announcementsProvider);
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) showAppMessage(context, supportError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(
        widget.item == null ? 'Buat pengumuman' : 'Perbarui pengumuman',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _kind,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Jenis informasi',
                  ),
                  items: announcementKinds.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _kind = value!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  enabled: !_saving,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Judul'),
                  validator: (value) => value == null || value.trim().length < 5
                      ? 'Judul minimal 5 karakter.'
                      : null,
                ),
                TextFormField(
                  controller: _area,
                  enabled: !_saving,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Area terdampak',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Isi area terdampak.'
                      : null,
                ),
                TextFormField(
                  controller: _message,
                  enabled: !_saving,
                  maxLength: 2000,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan',
                    hintText: 'Jelaskan dampak, jadwal/estimasi perbaikan, dan langkah untuk pelanggan.',
                  ),
                  validator: (value) =>
                      value == null || value.trim().length < 10
                      ? 'Keterangan minimal 10 karakter.'
                      : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Status penanganan',
                  ),
                  items: announcementStatuses.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _status = value!),
                ),
                if (widget.item != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Arsipkan pengumuman'),
                    subtitle: const Text('Sembunyikan dari pelanggan.'),
                    value: _archived,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _archived = value),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Pengumuman dan pembaruannya akan terlihat oleh seluruh pelanggan.',
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? 'Menyimpan...'
                : widget.item == null
                ? 'Terbitkan'
                : 'Simpan pembaruan',
          ),
        ),
      ],
    ),
  );
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _saving = false;
  Future<void> _save(bool enabled) async {
    setState(() => _saving = true);
    try {
      await ref.read(saveServicePreferenceProvider)(enabled);
    } catch (error) {
      if (mounted) showAppMessage(context, supportError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Preferensi notifikasi')),
    body: ref
        .watch(servicePreferenceProvider)
        .when(
          loading: () => const LoadingState(),
          error: (_, _) => ErrorState(
            onRetry: () => ref.invalidate(servicePreferenceProvider),
          ),
          data: (enabled) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SwitchListTile(
                title: const Text('Informasi layanan'),
                subtitle: const Text(
                  'Banner, tanda belum dibaca, dan push ke HP yang sudah didaftarkan.',
                ),
                value: enabled,
                onChanged: _saving ? null : _save,
              ),
              const SizedBox(height: 16),
              const Text(
                'Riwayat pengumuman tetap tersedia meskipun Informasi layanan dimatikan.',
              ),
              const SizedBox(height:20),
              const PushDeviceCard(),
            ],
          ),
        ),
  );
}

class PushDeviceCard extends ConsumerWidget {
  const PushDeviceCard({super.key});
  @override
  Widget build(BuildContext context,WidgetRef ref) {
    final state=ref.watch(pushControllerProvider);
    return SurfaceCard(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('Notifikasi di HP',style:TextStyle(fontWeight:FontWeight.bold)),
      const SizedBox(height:8),Text(state.message),const SizedBox(height:12),
      FilledButton.icon(onPressed:!state.available||state.busy?null:()=>ref.read(pushControllerProvider.notifier).sync(requestPermission:true),
        icon:const Icon(Icons.notifications_active_outlined),label:Text(state.busy?'Memeriksa...':state.registered?'Periksa notifikasi HP':'Aktifkan notifikasi HP')),
      const SizedBox(height:8),const Text('Aktifkan Informasi layanan dan izinkan notifikasi Android. Setelah itu, aplikasi tidak perlu tetap terbuka.',style:TextStyle(fontSize:12)),
    ]));
  }
}
