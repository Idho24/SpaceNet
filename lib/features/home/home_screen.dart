import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_components.dart';
import '../../core/widgets/brand_logo.dart';
import '../../data/mock/mock_repository.dart';
import '../../data/models/customer_model.dart';
import '../../data/repositories/customer_repository.dart';
import '../auth/auth_state.dart';

class HomeScreen extends StatefulWidget {
  final int initialTab;

  const HomeScreen({super.key, this.initialTab = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late int _selectedIndex;

  static const _routes = [
    '/home',
    '/billing',
    '/subscription',
    '/support',
    '/profile',
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const DashboardTab(),
      const BillingTab(),
      const SubscriptionTab(),
      const SupportTab(),
      const ProfileTab(),
    ];
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        child: KeyedSubtree(
          key: ValueKey(_selectedIndex),
          child: pages[_selectedIndex],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
          context.go(_routes[index]);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Tagihan',
          ),
          NavigationDestination(
            icon: Icon(Icons.wifi_outlined),
            selectedIcon: Icon(Icons.wifi_rounded),
            label: 'Paket',
          ),
          NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent_rounded),
            label: 'Bantuan',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

class DashboardTab extends ConsumerWidget {
  const DashboardTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoice = ref.watch(mockRepositoryProvider).currentInvoice!;
    final sessionUser = ref.watch(authNotifierProvider).user;
    final greeting = switch (DateTime.now().hour) {
      < 12 => 'Selamat pagi,',
      < 15 => 'Selamat siang,',
      < 18 => 'Selamat sore,',
      _ => 'Selamat malam,',
    };
    return _ScrollablePage(
      onRefresh: () async {
        await ref.read(mockRepositoryProvider).loadInvoices();
        if (context.mounted) showAppMessage(context, 'Informasi berhasil diperbarui.');
      },
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greeting, style: const TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  Text(
                    sessionUser?.displayName ?? 'Pelanggan',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Notifikasi',
              onPressed: () => context.push('/notifications'),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SubscriptionCard(
          onTap: () => context.go('/subscription'),
        ),
        const SizedBox(height: 18),
        _BillingSummary(invoice: invoice),
        const SizedBox(height: 22),
        const SectionHeading(title: 'Akses cepat'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _QuickAction(
              icon: Icons.payment_rounded,
              title: 'Bayar WiFi',
              onTap: () => context.push('/payment/${invoice.id}'),
            ),
            _QuickAction(
              icon: Icons.autorenew_rounded,
              title: 'Perpanjang',
              onTap: () => context.push('/payment/${invoice.id}'),
            ),
            _QuickAction(
              icon: Icons.report_problem_outlined,
              title: 'Lapor gangguan',
              onTap: () => context.push('/tickets/new'),
            ),
            _QuickAction(
              icon: Icons.history_rounded,
              title: 'Riwayat',
              onTap: () => context.push('/transactions'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SectionHeading(
          title: 'Info SpaceNet',
          actionLabel: 'Pusat bantuan',
          onAction: () => context.push('/help'),
        ),
        const _AnnouncementCard(),
        const SizedBox(height: 12),
        SurfaceCard(
          child: Row(
            children: [
              const Icon(Icons.campaign_outlined, color: AppTheme.primaryBlue),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Nikmati koneksi tanpa batas. Lihat pilihan paket terbaru kami.',
                  style: TextStyle(height: 1.4),
                ),
              ),
              IconButton(
                tooltip: 'Lihat paket',
                onPressed: () => context.push('/subscription/upgrade'),
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class BillingTab extends ConsumerStatefulWidget {
  const BillingTab({super.key});

  @override
  ConsumerState<BillingTab> createState() => _BillingTabState();
}

class _BillingTabState extends ConsumerState<BillingTab> {
  String _filter = 'Semua';
  bool _loading = false;
  String? _error;

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(mockRepositoryProvider).loadInvoices();
    } catch (_) {
      setState(() => _error = 'Data tagihan gagal dimuat.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(mockRepositoryProvider).invoices.where((invoice) {
      return _filter == 'Semua' ||
          (_filter == 'Belum dibayar' && invoice.status == InvoiceStatus.unpaid) ||
          (_filter == 'Lunas' && invoice.status == InvoiceStatus.paid) ||
          (_filter == 'Kedaluwarsa' && invoice.status == InvoiceStatus.expired);
    }).toList();
    return _ScrollablePage(
      onRefresh: _refresh,
      children: [
        PageHeading(
          title: 'Tagihan',
          subtitle: 'Kelola tagihan internet Anda',
          trailing: IconButton(
            tooltip: 'Muat ulang',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ),
        const SizedBox(height: 18),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          ErrorState(onRetry: _refresh)
        else ...[
          _OutstandingBalance(invoice: ref.watch(mockRepositoryProvider).currentInvoice),
          const SizedBox(height: 18),
          const SectionHeading(title: 'Daftar invoice'),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['Semua', 'Belum dibayar', 'Lunas', 'Kedaluwarsa']
                  .map(
                    (filter) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(filter),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          if (invoices.isEmpty)
            const EmptyState(
              title: 'Tidak ada invoice',
              message: 'Invoice dengan status ini akan muncul di sini.',
            )
          else
            ...invoices.map(
              (invoice) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _InvoiceTile(invoice: invoice),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.push('/transactions'),
            icon: const Icon(Icons.history),
            label: const Text('Lihat riwayat transaksi'),
          ),
        ],
      ],
    );
  }
}

class SubscriptionTab extends ConsumerWidget {
  const SubscriptionTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoice = ref.watch(mockRepositoryProvider).currentInvoice!;
    return _ScrollablePage(
      children: [
        const PageHeading(
          title: 'Langganan',
          subtitle: 'Detail paket dan masa aktif',
        ),
        const SizedBox(height: 18),
        const _SubscriptionCard(onTap: null, expanded: true),
        const SizedBox(height: 18),
        const SectionHeading(title: 'Paket aktif'),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _InfoRow(label: 'Nama paket', value: 'Home Fiber 200 Mbps'),
              const _InfoRow(label: 'Kecepatan', value: '200 Mbps'),
              const _InfoRow(label: 'Biaya bulanan', value: 'Rp 249.000'),
              const _InfoRow(label: 'Mulai berlangganan', value: '15 Jun 2025'),
              const _InfoRow(label: 'Berakhir', value: '30 Nov 2026'),
              const _InfoRow(label: 'Status', value: 'Aktif'),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: () => context.push('/payment/${invoice.id}'),
          icon: const Icon(Icons.autorenew),
          label: const Text('Perpanjang masa aktif'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => context.push('/subscription/upgrade'),
          icon: const Icon(Icons.upgrade_rounded),
          label: const Text('Pilih paket atau upgrade'),
        ),
        const SizedBox(height: 14),
        const _InlineNotice(
          icon: Icons.info_outline,
          text: 'Perpanjangan dan perubahan paket ditampilkan sebagai pratinjau. '
              'Konfirmasi tagihan akan tersedia setelah backend disiapkan.',
        ),
      ],
    );
  }
}

class SupportTab extends ConsumerWidget {
  const SupportTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(mockRepositoryProvider).tickets;
    return _ScrollablePage(
      children: [
        PageHeading(
          title: 'Pusat bantuan',
          subtitle: 'Kami siap membantu koneksi Anda',
          trailing: IconButton(
            tooltip: 'Panduan bantuan',
            onPressed: () => context.push('/help'),
            icon: const Icon(Icons.menu_book_outlined),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryBlue, AppTheme.secondaryBlue],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ada kendala internet?',
                      style: TextStyle(
                        color: AppTheme.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Buat laporan dan pantau tindak lanjutnya.',
                      style: TextStyle(color: AppTheme.white),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                tooltip: 'Buat laporan',
                onPressed: () => context.push('/tickets/new'),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.white,
                  foregroundColor: AppTheme.primaryBlue,
                ),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionHeading(
          title: 'Laporan saya',
          actionLabel: 'Lihat panduan',
          onAction: () => context.push('/help'),
        ),
        if (tickets.isEmpty)
          EmptyState(
            title: 'Belum ada laporan',
            message: 'Buat tiket jika Anda mengalami gangguan.',
            actionLabel: 'Buat laporan',
            onAction: () => context.push('/tickets/new'),
          )
        else
          ...tickets.map(
            (ticket) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SurfaceCard(
                onTap: () => context.push('/tickets/${ticket.id}'),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFE7F5FB),
                      child: Icon(Icons.support_agent, color: AppTheme.primaryBlue),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ticket.category, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('${ticket.id} • ${ticket.date}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                          const SizedBox(height: 8),
                          StatusPill(label: ticket.status, color: AppTheme.warning),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        const SectionHeading(title: 'Panduan cepat'),
        _HelpLink(
          icon: Icons.wifi_off_outlined,
          title: 'Internet mati atau lambat',
          onTap: () => context.push('/help/internet'),
        ),
        _HelpLink(
          icon: Icons.router_outlined,
          title: 'Lampu LOS merah',
          onTap: () => context.push('/help/los'),
        ),
        _HelpLink(
          icon: Icons.restart_alt_rounded,
          title: 'Restart router dengan aman',
          onTap: () => context.push('/help/router'),
        ),
      ],
    );
  }
}

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionUser = ref.watch(authNotifierProvider).user;
    final customerId = sessionUser?.customerId;
    final customerProfile = customerId == null
        ? const AsyncValue<CustomerModel?>.data(null)
        : ref.watch(customerProfileProvider(customerId));
    final customer = customerProfile.valueOrNull;

    ref.listen(authNotifierProvider, (previous, next) {
      if (next.status == AuthStatus.error && next.errorMessage != null) {
        showAppMessage(context, next.errorMessage!);
      }
    });

    return _ScrollablePage(
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Profil', style: Theme.of(context).textTheme.headlineMedium),
            ),
            const BrandLogo(width: 110),
          ],
        ),
        const SizedBox(height: 18),
        SurfaceCard(
          child: Row(
            children: [
              const CircleAvatar(
                radius: 30,
                backgroundColor: Color(0xFFE7F5FB),
                child: Text(
                  'NS',
                  style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sessionUser?.displayName ?? 'Pengguna SpaceNet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sessionUser?.email ?? '',
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit profil',
                onPressed: () => showAppMessage(context, 'Perubahan profil akan tersedia setelah akun terhubung.'),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (customer == null && customerProfile.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: LoadingState(),
          )
        else if (customerProfile.hasError)
          ErrorState(
            onRetry: () {
              if (customerId != null) {
                ref.invalidate(customerProfileProvider(customerId));
              }
            },
          )
        else if (customer != null) ...[
          _InfoRow(label: 'ID pelanggan', value: customer.customerId),
          _InfoRow(label: 'Nomor ponsel', value: customer.phone),
          _InfoRow(label: 'Alamat pemasangan', value: customer.address),
          _InfoRow(label: 'Paket aktif', value: customer.activePackage),
        ],
        if (customer == null && !customerProfile.isLoading)
          const EmptyState(
            title: 'Profil pelanggan belum tersedia',
            message: 'Data pelanggan akan tampil setelah verifikasi akun selesai.',
            icon: Icons.person_outline,
          ),
        const SizedBox(height: 16),
        const SectionHeading(title: 'Pengaturan'),
        _MenuRow(
          icon: Icons.notifications_outlined,
          title: 'Notifikasi',
          onTap: () => context.push('/notifications'),
        ),
        _MenuRow(
          icon: Icons.tune_rounded,
          title: 'Preferensi notifikasi',
          onTap: () => context.push('/settings'),
        ),
        _MenuRow(
          icon: Icons.privacy_tip_outlined,
          title: 'Kebijakan privasi',
          onTap: () => context.push('/legal/privacy'),
        ),
        _MenuRow(
          icon: Icons.description_outlined,
          title: 'Syarat dan ketentuan',
          onTap: () => context.push('/legal/terms'),
        ),
        _MenuRow(
          icon: Icons.info_outline,
          title: 'Tentang SpaceNet',
          onTap: () => context.push('/about'),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => ref.read(authNotifierProvider.notifier).signOut(),
          icon: const Icon(Icons.logout),
          label: const Text('Keluar dari akun'),
          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error),
        ),
      ],
    );
  }
}

class _ScrollablePage extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  const _ScrollablePage({required this.children, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        for (final child in children) ...[
          child,
          const SizedBox(height: 12),
        ],
      ],
    );
    return SafeArea(
      child: onRefresh == null
          ? content
          : RefreshIndicator(onRefresh: onRefresh!, child: content),
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final VoidCallback? onTap;
  final bool expanded;

  const _SubscriptionCard({required this.onTap, this.expanded = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [AppTheme.primaryBlue, AppTheme.secondaryBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'LANGGANAN AKTIF',
                      style: TextStyle(color: AppTheme.white, fontWeight: FontWeight.w600, fontSize: 12, letterSpacing: 0.6),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 8, color: Color(0xFF8BF0BD)),
                        SizedBox(width: 6),
                        Text(
                          'Online',
                          style: TextStyle(
                            color: AppTheme.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Home Fiber 200 Mbps',
                style: TextStyle(color: AppTheme.white, fontSize: 23, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text('ID 0012995 • Bandung', style: TextStyle(color: AppTheme.white)),
              const SizedBox(height: 18),
              Row(
                children: const [
                  Expanded(child: _SpeedSummary(label: 'Unduh', value: '190 Mbps')),
                  SizedBox(width: 12),
                  Expanded(child: _SpeedSummary(label: 'Unggah', value: '98 Mbps')),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 18),
                const Divider(color: Color(0x66FFFFFF)),
                const SizedBox(height: 8),
                const Text('Masa aktif hingga 30 November 2026', style: TextStyle(color: AppTheme.white)),
              ],
              if (onTap != null) ...[
                const SizedBox(height: 14),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('Detail paket', style: TextStyle(color: AppTheme.white)),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward, color: AppTheme.white, size: 16),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedSummary extends StatelessWidget {
  final String label;
  final String value;

  const _SpeedSummary({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.white, fontSize: 12)),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(color: AppTheme.white, fontSize: 17, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _BillingSummary extends StatelessWidget {
  final MockInvoice invoice;

  const _BillingSummary({required this.invoice});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(child: Text('Tagihan bulan ini', style: TextStyle(color: AppTheme.textSecondary))),
              StatusPill(label: 'Belum dibayar', color: AppTheme.warning),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            formatRupiah(invoice.amount),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.darkNavy),
          ),
          const SizedBox(height: 5),
          Text('Jatuh tempo 14 November 2026 • ${invoice.id}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.push('/payment/${invoice.id}'),
              child: const Text('Bayar sekarang'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutstandingBalance extends StatelessWidget {
  final MockInvoice? invoice;

  const _OutstandingBalance({required this.invoice});

  @override
  Widget build(BuildContext context) {
    if (invoice == null) {
      return const SurfaceCard(
        child: Row(
          children: [
            Icon(Icons.check_circle, color: AppTheme.success),
            SizedBox(width: 12),
            Expanded(child: Text('Semua tagihan Anda sudah lunas.')),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [AppTheme.darkNavy, AppTheme.secondaryBlue]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total yang perlu dibayar', style: TextStyle(color: Color(0xFFD8EAF4))),
          const SizedBox(height: 6),
          Text(formatRupiah(invoice!.amount), style: const TextStyle(color: AppTheme.white, fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Jatuh tempo 14 November 2026', style: const TextStyle(color: AppTheme.white)),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: () => context.push('/payment/${invoice!.id}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.white,
              side: const BorderSide(color: Color(0xAAFFFFFF)),
            ),
            child: const Text('Bayar tagihan'),
          ),
        ],
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  final MockInvoice invoice;

  const _InvoiceTile({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (invoice.status) {
      InvoiceStatus.unpaid => ('Belum dibayar', AppTheme.warning),
      InvoiceStatus.paid => ('Lunas', AppTheme.success),
      InvoiceStatus.expired => ('Kedaluwarsa', AppTheme.error),
    };
    return SurfaceCard(
      onTap: () => context.push('/invoice/${invoice.id}'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppTheme.primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.receipt_long_outlined, color: AppTheme.primaryBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invoice.period, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(invoice.id, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 6),
                Text(formatRupiah(invoice.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusPill(label: label, color: color),
              const SizedBox(height: 8),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _QuickAction({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 50) / 2,
      child: SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryBlue, size: 22),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(color: AppTheme.primaryBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.network_check_rounded, color: AppTheme.primaryBlue),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pemeliharaan jaringan', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 5),
                Text(
                  'Peningkatan jaringan area Bandung pada 8 November, pukul 01.00–03.00 WIB.',
                  style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppTheme.textSecondary))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InlineNotice({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.primaryBlue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppTheme.secondaryBlue),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(height: 1.45, fontSize: 13))),
        ],
      ),
    );
  }
}

class _HelpLink extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _HelpLink({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryBlue),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _MenuRow({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _HelpLink(icon: icon, title: title, onTap: onTap);
  }
}
