import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_components.dart';
import '../../data/models/support_ticket.dart';
import '../../data/repositories/support_repository.dart';
import '../auth/auth_state.dart';

class CustomerSupportList extends ConsumerWidget {
  const CustomerSupportList({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(supportTicketsProvider)
      .when(
        loading: () =>
            const Padding(padding: EdgeInsets.all(24), child: LoadingState()),
        error: (_, _) =>
            ErrorState(onRetry: () => ref.invalidate(supportTicketsProvider)),
        data: (tickets) => Column(
          children: [
            if (tickets.isEmpty)
              EmptyState(
                title: 'Belum ada laporan',
                message: 'Buat laporan jika Anda mengalami gangguan.',
                actionLabel: 'Buat laporan',
                onAction: () => context.push('/tickets/new'),
              ),
            ...tickets.map(
              (ticket) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _TicketCard(
                  ticket: ticket,
                  onTap: () => context.push('/tickets/${ticket.id}'),
                ),
              ),
            ),
            if (tickets.isNotEmpty)
              const Text(
                'Status diperbarui otomatis setiap 10 detik.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
          ],
        ),
      );
}

class _TicketCard extends StatelessWidget {
  final SupportTicket ticket;
  final VoidCallback onTap;
  final bool admin;
  const _TicketCard({
    required this.ticket,
    required this.onTap,
    this.admin = false,
  });
  @override
  Widget build(BuildContext context) => SurfaceCard(
    onTap: onTap,
    child: Row(
      children: [
        const CircleAvatar(child: Icon(Icons.support_agent)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ticket.category,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${ticket.code} • ${ticket.date}',
                style: const TextStyle(fontSize: 12),
              ),
              if (admin)
                Text(
                  '${ticket.customerName} • ${ticket.customerId}',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              const SizedBox(height: 8),
              _SupportStatus(ticket: ticket),
            ],
          ),
        ),
        const Icon(Icons.chevron_right),
      ],
    ),
  );
}

class _SupportStatus extends StatelessWidget {
  final SupportTicket ticket;
  const _SupportStatus({required this.ticket});
  @override
  Widget build(BuildContext context) => StatusPill(
    label: ticket.statusLabel,
    color: ticket.status == 'resolved'
        ? AppTheme.success
        : ticket.status == 'cancelled'
        ? AppTheme.textSecondary
        : AppTheme.primaryBlue,
  );
}

class TicketDetailScreen extends ConsumerWidget {
  final String ticketId;
  final bool admin;
  const TicketDetailScreen({
    super.key,
    required this.ticketId,
    this.admin = false,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: Text(admin ? 'Penanganan laporan' : 'Detail laporan'),
      leading: IconButton(
        tooltip: 'Kembali',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go(admin ? '/admin/reports' : '/support'),
      ),
      actions: [
        IconButton(
          tooltip: 'Muat ulang',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(supportDetailProvider(ticketId)),
        ),
      ],
    ),
    body: admin
        ? SupportAdminGate(child: _ReportBody(ticketId: ticketId, admin: true))
        : _ReportBody(ticketId: ticketId, admin: false),
  );
}

class _ReportBody extends ConsumerWidget {
  final String ticketId;
  final bool admin;
  const _ReportBody({required this.ticketId, required this.admin});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(supportDetailProvider(ticketId))
      .when(
        loading: () => const LoadingState(),
        error: (_, _) => ErrorState(
          onRetry: () => ref.invalidate(supportDetailProvider(ticketId)),
        ),
        data: (detail) {
          if (detail == null) {
            return const EmptyState(
              title: 'Laporan tidak ditemukan',
              message:
                  'Laporan tidak tersedia atau akun Anda tidak memiliki akses.',
            );
          }
          final ticket = detail.ticket;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(supportDetailProvider(ticketId));
              await ref.read(supportDetailProvider(ticketId).future);
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SurfaceCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                ticket.code,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 12),
                              _SupportStatus(ticket: ticket),
                              const SizedBox(height: 16),
                              Text(
                                ticket.category,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${ticket.customerName} • ID ${ticket.customerId}',
                              ),
                              Text('Dibuat ${ticket.date}'),
                              Text(
                                'Diperbarui ${supportDate(ticket.updatedAt)}',
                              ),
                              const Divider(height: 28),
                              SelectableText(ticket.description),
                              if (detail.photoUrl != null) ...[
                                const SizedBox(height: 16),
                                Image.network(
                                  detail.photoUrl!,
                                  height: 240,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Text(
                                    'Foto belum dapat dimuat. Coba muat ulang.',
                                  ),
                                ),
                              ] else if (ticket.photoPath != null)
                                const Padding(
                                  padding: EdgeInsets.only(top: 16),
                                  child: Text(
                                    'Lampiran belum dapat dimuat. Coba muat ulang.',
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (admin) ...[
                          _UpdateReportForm(
                            key: ValueKey(ticket.id),
                            ticket: ticket,
                          ),
                          const SizedBox(height: 24),
                        ],
                        const SectionHeading(title: 'Perkembangan laporan'),
                        ...detail.events.map(
                          (event) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SurfaceCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${event.actorRole == 'admin' ? 'Tim SpaceNet' : 'Pelanggan'} • ${supportDate(event.createdAt)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    supportStatuses[event.status] ??
                                        event.status,
                                    style: const TextStyle(
                                      color: AppTheme.primaryBlue,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SelectableText(event.message),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (!admin && !ticket.isClosed) ...[
                          OutlinedButton.icon(
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: const Text('Tambah komentar'),
                            onPressed: () =>
                                _customerUpdate(context, ref, ticket, false),
                          ),
                          TextButton(
                            onPressed: () =>
                                _customerUpdate(context, ref, ticket, true),
                            child: const Text('Batalkan laporan'),
                          ),
                        ],
                        const Text(
                          'Status dan catatan diperbarui otomatis setiap 10 detik.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

Future<void> _customerUpdate(
  BuildContext context,
  WidgetRef ref,
  SupportTicket ticket,
  bool cancel,
) async {
  final message = await showDialog<String>(
    context: context,
    builder: (_) => _CustomerNoteDialog(cancel: cancel),
  );
  if (message == null || !context.mounted) return;
  try {
    await ref
        .read(supportRepositoryProvider)
        .update(ticket, cancel ? 'cancelled' : ticket.status, message);
    ref.invalidate(supportDetailProvider(ticket.id));
    ref.invalidate(supportTicketsProvider);
    if (context.mounted) {
      showAppMessage(
        context,
        cancel ? 'Laporan dibatalkan.' : 'Komentar tersimpan.',
      );
    }
  } catch (error) {
    ref.invalidate(supportDetailProvider(ticket.id));
    if (context.mounted) showAppMessage(context, supportError(error));
  }
}

class _CustomerNoteDialog extends StatefulWidget {
  final bool cancel;
  const _CustomerNoteDialog({required this.cancel});
  @override
  State<_CustomerNoteDialog> createState() => _CustomerNoteDialogState();
}

class _CustomerNoteDialogState extends State<_CustomerNoteDialog> {
  final _controller = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.cancel ? 'Batalkan laporan?' : 'Tambah komentar'),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _controller,
        maxLength: 1000,
        maxLines: 3,
        decoration: InputDecoration(
          labelText: widget.cancel ? 'Alasan pembatalan' : 'Informasi tambahan',
        ),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'Catatan wajib diisi.'
            : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Kembali'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _controller.text.trim());
          }
        },
        child: Text(widget.cancel ? 'Batalkan laporan' : 'Kirim'),
      ),
    ],
  );
}

class _UpdateReportForm extends ConsumerStatefulWidget {
  final SupportTicket ticket;
  const _UpdateReportForm({super.key, required this.ticket});
  @override
  ConsumerState<_UpdateReportForm> createState() => _UpdateReportFormState();
}

class _UpdateReportFormState extends ConsumerState<_UpdateReportForm> {
  final _note = TextEditingController();
  final _form = GlobalKey<FormState>();
  late String _status = widget.ticket.status;
  late SupportTicket _base = widget.ticket;
  bool _saving = false;
  bool _dirty = false;
  @override
  void didUpdateWidget(covariant _UpdateReportForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && !_saving) {
      _base = widget.ticket;
      _status = widget.ticket.status;
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(supportRepositoryProvider)
          .update(_base, _status, _note.text.trim());
      ref.invalidate(supportTicketsProvider);
      final updated = await ref.refresh(supportDetailProvider(_base.id).future);
      if (mounted) {
        setState(() {
          _note.clear();
          _dirty = false;
          if (updated != null) {
            _base = updated.ticket;
            _status = updated.ticket.status;
          }
        });
        showAppMessage(context, 'Status dan catatan penanganan tersimpan.');
      }
    } catch (error) {
      ref.invalidate(supportDetailProvider(_base.id));
      if (mounted) showAppMessage(context, supportError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SurfaceCard(
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Perbarui penanganan',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          if (_dirty && _base.version != widget.ticket.version) ...[
            const Text(
              'Ada pembaruan baru. Tinjau riwayat terbaru sebelum menyimpan catatan Anda.',
            ),
            TextButton(
              onPressed: _saving
                  ? null
                  : () => setState(() {
                      _base = widget.ticket;
                    }),
              child: const Text('Gunakan versi terbaru'),
            ),
          ],
          DropdownButtonFormField<String>(
            key: ValueKey('${_base.version}:$_status'),
            initialValue: _status,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Status laporan'),
            items: supportStatuses.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() {
                    _status = value!;
                    _dirty = true;
                  }),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _note,
            enabled: !_saving,
            maxLength: 1000,
            minLines: 3,
            maxLines: 6,
            onChanged: (_) => setState(() => _dirty = true),
            decoration: const InputDecoration(
              labelText: 'Catatan penanganan',
              helperText: 'Catatan ini terlihat oleh pelanggan.',
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Isi catatan penanganan.'
                : null,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed:
                _saving || (_dirty && _base.version != widget.ticket.version)
                ? null
                : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Menyimpan...' : 'Simpan pembaruan'),
          ),
        ],
      ),
    ),
  );
}

class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});
  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  String _filter = 'all';
  String _search = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('SpaceNet • Laporan pelanggan'),
      actions: [
        IconButton(
          tooltip: 'Pengumuman layanan',
          icon: const Icon(Icons.campaign_outlined),
          onPressed: () => context.go('/admin/announcements'),
        ),
        IconButton(
          tooltip: 'Muat ulang',
          icon: const Icon(Icons.refresh),
          onPressed: () {
            ref.invalidate(supportAdminProvider);
            ref.invalidate(supportTicketsProvider);
          },
        ),
        if (ref.watch(authNotifierProvider).isAuthenticated)
          IconButton(
            tooltip: 'Keluar akun',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
          ),
      ],
    ),
    body: SupportAdminGate(
      child: Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(supportTicketsProvider);
          return state.when(
            loading: () => const LoadingState(),
            error: (_, _) => ErrorState(
              onRetry: () => ref.invalidate(supportTicketsProvider),
            ),
            data: (tickets) {
              final filtered = tickets
                  .where(
                    (t) =>
                        (_filter == 'all' || t.status == _filter) &&
                        '${t.code} ${t.customerId} ${t.customerName} ${t.category}'
                            .toLowerCase()
                            .contains(_search),
                  )
                  .toList();
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(supportTicketsProvider);
                  await ref.read(supportTicketsProvider.future);
                },
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Pusat penanganan laporan',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Laporan baru dan perubahan status diperbarui otomatis setiap 10 detik.',
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                _CountCard('Semua laporan', tickets.length),
                                _CountCard(
                                  'Perlu ditinjau',
                                  tickets
                                      .where((t) => t.status == 'open')
                                      .length,
                                ),
                                _CountCard(
                                  'Dalam proses',
                                  tickets
                                      .where(
                                        (t) =>
                                            t.status == 'review' ||
                                            t.status == 'in_progress',
                                      )
                                      .length,
                                ),
                                _CountCard(
                                  'Selesai',
                                  tickets
                                      .where((t) => t.status == 'resolved')
                                      .length,
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.search),
                                labelText: 'Cari nomor laporan, ID, atau nama pelanggan',
                              ),
                              onChanged: (value) => setState(
                                () => _search = value.trim().toLowerCase(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: {'all': 'Semua', ...supportStatuses}
                                  .entries
                                  .map(
                                    (entry) => ChoiceChip(
                                      label: Text(entry.value),
                                      selected: _filter == entry.key,
                                      onSelected: (_) =>
                                          setState(() => _filter = entry.key),
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 20),
                            if (filtered.isEmpty)
                              const EmptyState(
                                title: 'Tidak ada laporan',
                                message: 'Laporan pelanggan akan muncul di sini. Periksa juga filter pencarian.',
                              ),
                            ...filtered.map(
                              (ticket) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _TicketCard(
                                  ticket: ticket,
                                  admin: true,
                                  onTap: () =>
                                      context.go('/admin/reports/${ticket.id}'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
  );
}

class _CountCard extends StatelessWidget {
  final String label;
  final int count;
  const _CountCard(this.label, this.count);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 225,
    child: SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryBlue,
            ),
          ),
        ],
      ),
    ),
  );
}

class SupportAdminGate extends ConsumerWidget {
  final Widget child;
  const SupportAdminGate({super.key, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);
    if (auth.status == AuthStatus.loading) return const LoadingState();
    if (!auth.isAuthenticated) {
      return EmptyState(
        title: 'Masuk sebagai admin',
        icon: Icons.admin_panel_settings_outlined,
        message:
            auth.errorMessage ??
            'Gunakan akun Google yang terdaftar sebagai admin SpaceNet.',
        actionLabel: 'Masuk dengan Google',
        onAction: () =>
            ref.read(authNotifierProvider.notifier).signInWithGoogle(),
      );
    }
    return ref
        .watch(supportAdminProvider)
        .when(
          loading: () => const LoadingState(),
          error: (_, _) =>
              ErrorState(onRetry: () => ref.invalidate(supportAdminProvider)),
          data: (allowed) => allowed
              ? child
              : EmptyState(
                  title: 'Akses admin diperlukan',
                  icon: Icons.lock_outline,
                  message: 'Akun ini tidak terdaftar sebagai admin. Masuk dengan akun admin Anda.',
                  actionLabel: 'Ganti akun',
                  onAction: () =>
                      ref.read(authNotifierProvider.notifier).signOut(),
                ),
        );
  }
}
