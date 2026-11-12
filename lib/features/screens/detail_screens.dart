import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_components.dart';
import '../../core/widgets/brand_logo.dart';
import '../../data/mock/mock_repository.dart';
import '../../data/repositories/push_notification_repository.dart';

Future<void> _copyToClipboard(
  BuildContext context,
  String text,
  String itemName,
) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showAppMessage(context, '$itemName disalin.');
  } on PlatformException catch (error) {
    if (context.mounted) {
      showAppMessage(context, '$itemName gagal disalin. ${error.message ?? ''}');
    }
  } on MissingPluginException {
    if (context.mounted) {
      showAppMessage(context, 'Fitur salin tidak tersedia di perangkat ini.');
    }
  }
}

class InvoiceDetailScreen extends ConsumerWidget {
  final String invoiceId;

  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoice = ref.watch(mockRepositoryProvider).invoiceById(invoiceId);
    return Scaffold(
      appBar: AppBar(title: const Text('Detail invoice')),
      body: invoice == null
          ? const EmptyState(
              title: 'Invoice tidak ditemukan',
              message: 'Data invoice ini tidak tersedia pada pratinjau.',
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _InvoiceStatusCard(invoice: invoice),
                const SizedBox(height: 18),
                const SectionHeading(title: 'Rincian tagihan'),
                SurfaceCard(
                  child: Column(
                    children: [
                      _DetailRow(label: 'Nomor invoice', value: invoice.id),
                      _DetailRow(label: 'Periode', value: invoice.period),
                      const _DetailRow(
                        label: 'Paket internet',
                        value: 'Home Fiber 200 Mbps',
                      ),
                      const _DetailRow(
                        label: 'Biaya langganan',
                        value: 'Rp 249.000',
                      ),
                      const _DetailRow(label: 'Pajak', value: 'Termasuk'),
                      _DetailRow(
                        label: 'Jatuh tempo',
                        value: '${invoice.dueDate.day} November 2026',
                      ),
                      const Divider(height: 24),
                      _DetailRow(
                        label: 'Total pembayaran',
                        value: formatRupiah(invoice.amount),
                        emphasized: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (invoice.status == InvoiceStatus.unpaid)
                  ElevatedButton.icon(
                    onPressed: () => context.push('/payment/${invoice.id}'),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Pilih metode pembayaran'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _copyToClipboard(
                      context,
                      'Invoice: ${invoice.id}\n'
                      'Periode: ${invoice.period}\n'
                      'Total: ${formatRupiah(invoice.amount)}\n'
                      'Status: Lunas',
                      'Rincian invoice',
                    ),
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Salin rincian invoice'),
                  ),
              ],
            ),
    );
  }
}

class _InvoiceStatusCard extends StatelessWidget {
  final MockInvoice invoice;

  const _InvoiceStatusCard({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (invoice.status) {
      InvoiceStatus.unpaid => (
        'Menunggu pembayaran',
        AppTheme.warning,
        Icons.schedule,
      ),
      InvoiceStatus.paid => (
        'Lunas',
        AppTheme.success,
        Icons.check_circle_outline,
      ),
      InvoiceStatus.expired => (
        'Kedaluwarsa',
        AppTheme.error,
        Icons.error_outline,
      ),
    };
    return SurfaceCard(
      child: Row(
        children: [
          Icon(icon, size: 32, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  invoice.period,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: StatusPill(label: label, color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PaymentScreen extends ConsumerStatefulWidget {
  final String invoiceId;

  const PaymentScreen({super.key, required this.invoiceId});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  String _method = 'QRIS';
  bool _instructionsVisible = false;
  bool _loading = false;

  Future<void> _createPayment() async {
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _instructionsVisible = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final invoice = ref
        .watch(mockRepositoryProvider)
        .invoiceById(widget.invoiceId);
    return Scaffold(
      appBar: AppBar(title: const Text('Pembayaran')),
      body: invoice == null
          ? const EmptyState(
              title: 'Invoice tidak ditemukan',
              message: 'Kembali ke daftar tagihan untuk memilih invoice lain.',
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const PageHeading(
                  title: 'Selesaikan pembayaran',
                  subtitle: 'Pilih cara pembayaran yang Anda inginkan',
                ),
                const SizedBox(height: 18),
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total tagihan',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        formatRupiah(invoice.amount),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        invoice.id,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeading(title: 'Metode pembayaran'),
                _PaymentChoice(
                  icon: Icons.qr_code_2_rounded,
                  title: 'QRIS',
                  subtitle: 'Pindai melalui aplikasi pembayaran',
                  selected: _method == 'QRIS',
                  onTap: () => setState(() => _method = 'QRIS'),
                ),
                _PaymentChoice(
                  icon: Icons.account_balance_outlined,
                  title: 'Virtual Account',
                  subtitle: 'BCA, Mandiri, BNI, dan bank lainnya',
                  selected: _method == 'Virtual Account',
                  onTap: () => setState(() => _method = 'Virtual Account'),
                ),
                _PaymentChoice(
                  icon: Icons.wallet_outlined,
                  title: 'E-wallet',
                  subtitle: 'GoPay, OVO, dan DANA',
                  selected: _method == 'E-wallet',
                  onTap: () => setState(() => _method = 'E-wallet'),
                ),
                if (_instructionsVisible) ...[
                  const SizedBox(height: 12),
                  _PaymentInstruction(method: _method),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _method == 'QRIS'
                        ? () => showAppMessage(
                            context,
                            'QRIS belum tersedia karena payment gateway belum dikonfigurasi. '
                            'Instruksi demo ini tidak dapat digunakan untuk membayar.',
                          )
                        : () => _copyToClipboard(
                            context,
                            _method == 'Virtual Account'
                                ? 'Invoice: ${invoice.id}\n'
                                      'Metode: Virtual Account\n'
                                      'Nomor VA: 8808 0012 9950 2026\n'
                                      'Jumlah: ${formatRupiah(invoice.amount)}'
                                : 'Invoice: ${invoice.id}\n'
                                      'Metode: E-wallet\n'
                                      'Jumlah: ${formatRupiah(invoice.amount)}',
                            'Instruksi pembayaran',
                          ),
                    icon: Icon(
                      _method == 'QRIS'
                          ? Icons.info_outline
                          : Icons.copy_outlined,
                    ),
                    label: Text(
                      _method == 'QRIS'
                          ? 'Info ketersediaan QRIS'
                          : 'Salin instruksi',
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loading
                      ? null
                      : _instructionsVisible
                      ? () => showAppMessage(
                          context,
                          'Status masih menunggu konfirmasi server. Pembayaran demo tidak ditandai lunas.',
                        )
                      : _createPayment,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.white,
                          ),
                        )
                      : Text(
                          _instructionsVisible
                              ? 'Periksa status pembayaran'
                              : 'Buat instruksi pembayaran',
                        ),
                ),
                const SizedBox(height: 12),
                const _InfoNotice(
                  text:
                      'Mode pratinjau. Transaksi belum dibuat di Midtrans/Xendit. '
                      'Tagihan hanya dapat ditandai lunas oleh konfirmasi server.',
                ),
              ],
            ),
    );
  }
}

class _PaymentChoice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryBlue, size: 25),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppTheme.primaryBlue : AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentInstruction extends StatelessWidget {
  final String method;

  const _PaymentInstruction({required this.method});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Instruksi demo',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 10),
          if (method == 'QRIS')
            const Text(
              'Kode QR belum tersedia karena payment gateway belum dikonfigurasi. '
              'Tagihan ini belum dapat dibayar melalui QRIS.',
              style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
            )
          else
            Text(
              method == 'Virtual Account'
                  ? '8808 0012 9950 2026'
                  : 'Pembayaran melalui aplikasi e-wallet',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          const Text(
            'Batas pembayaran 14 November 2026, 23.59 WIB.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  String _selectedPackage = 'Home Fiber 300 Mbps';
  MockPackageChangeRequest? _request;

  Future<void> _submitRequest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ajukan perubahan paket?'),
        content: Text(
          'Ajukan $_selectedPackage untuk ditinjau oleh tim SpaceNet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Kirim pengajuan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final request = ProviderScope.containerOf(
      context,
    ).read(mockRepositoryProvider).submitPackageChangeRequest(
      _selectedPackage,
    );
    setState(() => _request = request);
    showAppMessage(
      context,
      'Pengajuan ${request.id} tersimpan di pratinjau. Paket belum berubah.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pilih paket')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const PageHeading(
            title: 'Upgrade koneksi',
            subtitle: 'Pilih paket yang sesuai kebutuhan rumah Anda',
          ),
          const SizedBox(height: 18),
          _PlanCard(
            name: 'Home Fiber 100 Mbps',
            speed: '100 Mbps',
            price: 179000,
            selected: _selectedPackage == 'Home Fiber 100 Mbps',
            onTap: () =>
                setState(() => _selectedPackage = 'Home Fiber 100 Mbps'),
          ),
          _PlanCard(
            name: 'Home Fiber 300 Mbps',
            speed: '300 Mbps',
            price: 349000,
            selected: _selectedPackage == 'Home Fiber 300 Mbps',
            recommended: true,
            onTap: () =>
                setState(() => _selectedPackage = 'Home Fiber 300 Mbps'),
          ),
          _PlanCard(
            name: 'Home Fiber 500 Mbps',
            speed: '500 Mbps',
            price: 499000,
            selected: _selectedPackage == 'Home Fiber 500 Mbps',
            onTap: () =>
                setState(() => _selectedPackage = 'Home Fiber 500 Mbps'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _submitRequest,
            child: const Text('Ajukan perubahan paket'),
          ),
          if (_request case final request?) ...[
            const SizedBox(height: 14),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pengajuan ${request.id}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(request.packageName),
                  const SizedBox(height: 4),
                  Text(
                    request.status,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          const _InfoNotice(
            text:
                'Pengajuan demo tersimpan di perangkat ini. Harga dan perubahan '
                'paket tetap perlu dikonfirmasi melalui backend SpaceNet.',
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String name;
  final String speed;
  final int price;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  const _PlanCard({
    required this.name,
    required this.speed,
    required this.price,
    required this.selected,
    required this.onTap,
    this.recommended = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppTheme.primaryBlue : AppTheme.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (recommended)
                        const StatusPill(
                          label: 'Populer',
                          color: AppTheme.primaryBlue,
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    speed,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              formatRupiah(price),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class NewTicketScreen extends StatefulWidget {
  const NewTicketScreen({super.key});

  @override
  State<NewTicketScreen> createState() => _NewTicketScreenState();
}

class _NewTicketScreenState extends State<NewTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  String _category = 'Internet lambat';
  String? _photoName;
  Uint8List? _photoBytes;
  bool _submitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
        if (mounted) {
          showAppMessage(context, 'Foto harus lebih dari 0 dan maksimal 5 MB.');
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _photoName = image.name;
        _photoBytes = bytes;
      });
    } on PlatformException catch (error) {
      if (mounted) {
        showAppMessage(context, 'Foto tidak dapat dipilih. ${error.message ?? ''}');
      }
    } on Exception catch (error) {
      if (mounted) showAppMessage(context, 'Foto tidak dapat dibaca. $error');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final ticket = ProviderScope.containerOf(context)
        .read(mockRepositoryProvider)
        .createTicket(
          category: _category,
          description: _descriptionController.text.trim(),
          photoName: _photoName,
          photoBytes: _photoBytes,
        );
    context.go('/tickets/${ticket.id}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lapor gangguan')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const PageHeading(
              title: 'Ceritakan kendalanya',
              subtitle: 'Tim dukungan akan menindaklanjuti laporan Anda.',
            ),
            const SizedBox(height: 22),
            const _DetailRow(label: 'ID pelanggan', value: '0012995'),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Kategori gangguan',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items:
                  const [
                        'Internet mati',
                        'Internet lambat',
                        'LOS merah',
                        'Router bermasalah',
                        'Koneksi tidak stabil',
                        'Lainnya',
                      ]
                      .map(
                        (category) => DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        ),
                      )
                      .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Deskripsi kendala',
                hintText: 'Ceritakan kapan kendala mulai terjadi dan lampu indikator router...',
                alignLabelWithHint: true,
              ),
              validator: (value) => value == null || value.trim().length < 8
                  ? 'Deskripsi minimal 8 karakter'
                  : null,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _photoBytes == null
                  ? _pickPhoto
                  : () => setState(() {
                      _photoName = null;
                      _photoBytes = null;
                    }),
              icon: Icon(
                _photoBytes != null
                    ? Icons.delete_outline
                    : Icons.add_a_photo_outlined,
              ),
              label: Text(
                _photoBytes != null ? 'Hapus foto' : 'Pilih foto',
              ),
            ),
            if (_photoBytes case final photoBytes?) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(
                  photoBytes,
                  height: 180,
                  fit: BoxFit.cover,
                ),
              ),
              if (_photoName case final photoName?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    photoName,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.white,
                      ),
                    )
                  : const Text('Kirim laporan'),
            ),
            const SizedBox(height: 10),
            const _InfoNotice(
              text:
                  'Tiket dan foto pada pratinjau tersimpan sementara di aplikasi, '
                  'belum dikirim ke server.',
            ),
          ],
        ),
      ),
    );
  }
}

class TicketDetailScreen extends ConsumerStatefulWidget {
  final String ticketId;

  const TicketDetailScreen({super.key, required this.ticketId});

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen> {
  final List<String> _comments = [];

  Future<void> _addComment() async {
    final controller = TextEditingController();
    final comment = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah komentar'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 240,
          decoration: const InputDecoration(
            hintText: 'Tulis informasi tambahan...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Kirim'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (comment != null && mounted) setState(() => _comments.add(comment));
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(mockRepositoryProvider);
    final ticket = repo.ticketById(widget.ticketId);
    return Scaffold(
      appBar: AppBar(title: const Text('Detail laporan')),
      body: ticket == null
          ? const EmptyState(
              title: 'Tiket tidak ditemukan',
              message: 'Tiket ini tidak tersedia di data pratinjau.',
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket.id,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      StatusPill(
                        label: ticket.status,
                        color: ticket.status == 'Selesai'
                            ? AppTheme.success
                            : AppTheme.warning,
                      ),
                      const SizedBox(height: 14),
                      _DetailRow(label: 'Kategori', value: ticket.category),
                      _DetailRow(label: 'Waktu laporan', value: ticket.date),
                      const Divider(height: 26),
                      Text(
                        ticket.description,
                        style: const TextStyle(height: 1.5),
                      ),
                      if (ticket.photoBytes case final photoBytes?) ...[
                        const SizedBox(height: 14),
                        Text(
                          ticket.photoName ?? 'Lampiran foto',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            photoBytes,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeading(title: 'Perkembangan laporan'),
                const _TimelineEntry(
                  title: 'Laporan diterima',
                  subtitle: 'Tiket tercatat di aplikasi',
                  completed: true,
                ),
                const _TimelineEntry(
                  title: 'Sedang ditinjau',
                  subtitle: 'Tim dukungan akan menghubungi Anda',
                  completed: true,
                ),
                const _TimelineEntry(
                  title: 'Penanganan teknisi',
                  subtitle: 'Menunggu jadwal kunjungan',
                  completed: false,
                ),
                const SizedBox(height: 12),
                SectionHeading(
                  title: 'Komentar',
                  actionLabel: 'Tambah',
                  onAction: _addComment,
                ),
                if (_comments.isEmpty)
                  const Text(
                    'Belum ada komentar tambahan.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  )
                else
                  ..._comments.map(
                    (comment) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SurfaceCard(
                        child: Text(
                          comment,
                          style: const TextStyle(height: 1.4),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                if (ticket.status != 'Dibatalkan' && ticket.status != 'Selesai')
                  OutlinedButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Batalkan laporan?'),
                        content: const Text(
                          'Tiket demo akan ditandai dibatalkan.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Kembali'),
                          ),
                          TextButton(
                            onPressed: () {
                              ref
                                  .read(mockRepositoryProvider)
                                  .updateTicketStatus(ticket.id, 'Dibatalkan');
                              Navigator.pop(dialogContext);
                              setState(() {});
                            },
                            child: const Text('Batalkan tiket'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('Batalkan laporan'),
                  ),
              ],
            ),
    );
  }
}

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(mockRepositoryProvider).transactions;
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat transaksi')),
      body: transactions.isEmpty
          ? const EmptyState(
              title: 'Belum ada transaksi',
              message: 'Pembayaran yang berhasil akan tercatat di sini.',
              icon: Icons.receipt_long_outlined,
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const PageHeading(
                  title: 'Semua transaksi',
                  subtitle: 'Riwayat pembayaran SpaceNet Anda',
                ),
                const SizedBox(height: 18),
                ...transactions.map(
                  (transaction) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SurfaceCard(
                      onTap: () =>
                          context.push('/transactions/${transaction.id}'),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFFE8F6EF),
                            child: Icon(
                              Icons.check_rounded,
                              color: AppTheme.success,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  transaction.id,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${transaction.date} • ${transaction.method}',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  formatRupiah(transaction.amount),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: AppTheme.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class TransactionDetailScreen extends ConsumerWidget {
  final String transactionId;

  const TransactionDetailScreen({super.key, required this.transactionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transaction = ref
        .watch(mockRepositoryProvider)
        .transactionById(transactionId);
    return Scaffold(
      appBar: AppBar(title: const Text('Detail transaksi')),
      body: transaction == null
          ? const EmptyState(
              title: 'Transaksi tidak ditemukan',
              message: 'Transaksi ini tidak tersedia pada data pratinjau.',
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Center(
                  child: CircleAvatar(
                    radius: 34,
                    backgroundColor: Color(0xFFE8F6EF),
                    child: Icon(
                      Icons.check_rounded,
                      color: AppTheme.success,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Center(
                  child: Text(
                    'Pembayaran berhasil',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 20),
                SurfaceCard(
                  child: Column(
                    children: [
                      _DetailRow(
                        label: 'Nomor transaksi',
                        value: transaction.id,
                      ),
                      _DetailRow(
                        label: 'Nomor invoice',
                        value: transaction.invoiceId,
                      ),
                      _DetailRow(
                        label: 'Tanggal pembayaran',
                        value: transaction.date,
                      ),
                      _DetailRow(
                        label: 'Metode pembayaran',
                        value: transaction.method,
                      ),
                      _DetailRow(label: 'Status', value: transaction.status),
                      const Divider(height: 24),
                      _DetailRow(
                        label: 'Total pembayaran',
                        value: formatRupiah(transaction.amount),
                        emphasized: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => _copyToClipboard(
                    context,
                    'Resi: ${transaction.id}\n'
                    'Invoice: ${transaction.invoiceId}\n'
                    'Tanggal: ${transaction.date}\n'
                    'Metode: ${transaction.method}\n'
                    'Jumlah: ${formatRupiah(transaction.amount)}\n'
                    'Status: ${transaction.status}',
                    'Resi transaksi',
                  ),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Salin resi'),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => _copyToClipboard(
                    context,
                    'Bukti pembayaran SpaceNet\n'
                    'Transaksi: ${transaction.id}\n'
                    'Invoice: ${transaction.invoiceId}\n'
                    'Jumlah: ${formatRupiah(transaction.amount)}\n'
                    'Status: ${transaction.status}',
                    'Bukti pembayaran',
                  ),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Salin bukti pembayaran'),
                ),
              ],
            ),
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final Set<int> _readNotifications = {};
  final List<_NotificationItem> _notifications = [
    const _NotificationItem(
      icon: Icons.receipt_long_outlined,
      title: 'Tagihan Oktober tersedia',
      message: 'Tagihan Rp 249.000 jatuh tempo 14 November 2026.',
      date: 'Hari ini, 09.15',
      color: AppTheme.warning,
    ),
    const _NotificationItem(
      icon: Icons.engineering_outlined,
      title: 'Pembaruan laporan gangguan',
      message: 'Teknisi dijadwalkan untuk laporan SPN-2042.',
      date: 'Kemarin, 16.20',
      color: AppTheme.primaryBlue,
    ),
    const _NotificationItem(
      icon: Icons.network_check_outlined,
      title: 'Pemeliharaan jaringan',
      message: 'Pemeliharaan terjadwal di area Bandung pada 8 November.',
      date: '1 Nov 2026',
      color: AppTheme.secondaryBlue,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.length - _readNotifications.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
        actions: [
          TextButton(
            onPressed: _notifications.isEmpty
                ? null
                : () => setState(() {
                    _readNotifications.addAll(
                      List<int>.generate(
                        _notifications.length,
                        (index) => index,
                      ),
                    );
                  }),
            child: const Text('Tandai dibaca'),
          ),
        ],
      ),
      body: _notifications.isEmpty
          ? const EmptyState(
              title: 'Belum ada notifikasi',
              message: 'Pembaruan layanan dan tagihan akan muncul di sini.',
              icon: Icons.notifications_none_rounded,
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  unreadCount == 0
                      ? 'Semua notifikasi sudah dibaca'
                      : '$unreadCount belum dibaca',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                for (var index = 0; index < _notifications.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SurfaceCard(
                      onTap: () =>
                          setState(() => _readNotifications.add(index)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            backgroundColor: _notifications[index].color
                                .withValues(alpha: 0.1),
                            child: Icon(
                              _notifications[index].icon,
                              color: _notifications[index].color,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _notifications[index].title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    if (!_readNotifications.contains(index))
                                      const Icon(
                                        Icons.circle,
                                        size: 9,
                                        color: AppTheme.primaryBlue,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _notifications[index].message,
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  _notifications[index].date,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _NotificationItem {
  final IconData icon;
  final String title;
  final String message;
  final String date;
  final Color color;

  const _NotificationItem({
    required this.icon,
    required this.title,
    required this.message,
    required this.date,
    required this.color,
  });
}

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  static const _topics = [
    ('internet', 'Internet mati atau lambat', Icons.wifi_off_outlined),
    ('los', 'Lampu LOS merah', Icons.warning_amber_rounded),
    ('router', 'Restart router dengan aman', Icons.router_outlined),
    ('payment', 'Panduan pembayaran', Icons.payment_outlined),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _topics
        .where((topic) => topic.$2.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Pusat bantuan')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const PageHeading(
            title: 'Ada yang bisa dibantu?',
            subtitle: 'Panduan ini tersedia saat offline.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Cari panduan atau pertanyaan',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Hapus pencarian',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          const SectionHeading(title: 'Panduan populer'),
          if (filtered.isEmpty)
            const EmptyState(
              title: 'Panduan tidak ditemukan',
              message: 'Coba kata kunci lain, atau hubungi dukungan SpaceNet.',
              icon: Icons.search_off,
            )
          else
            ...filtered.map(
              (topic) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _HelpTopicTile(
                  icon: topic.$3,
                  title: topic.$2,
                  onTap: () => context.push('/help/${topic.$1}'),
                ),
              ),
            ),
          const SizedBox(height: 14),
          const SectionHeading(title: 'Pertanyaan umum'),
          const _FaqTile(
            question: 'Kapan tagihan harus dibayar?',
            answer:
                'Tanggal jatuh tempo tercantum pada invoice di menu Tagihan.',
          ),
          const _FaqTile(
            question: 'Bagaimana cara melihat status tiket?',
            answer: 'Buka menu Bantuan, lalu pilih laporan untuk melihat perkembangannya.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showAppMessage(
              context,
              'Hubungi WhatsApp SpaceNet melalui nomor resmi pada situs perusahaan.',
            ),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Hubungi WhatsApp SpaceNet'),
          ),
          const SizedBox(height: 8),
          const _InfoNotice(
            text: 'Panduan troubleshooting merupakan konten lokal untuk pratinjau offline.',
          ),
        ],
      ),
    );
  }
}

class HelpTopicScreen extends StatelessWidget {
  final String topic;

  const HelpTopicScreen({super.key, required this.topic});

  @override
  Widget build(BuildContext context) {
    final (title, steps) = switch (topic) {
      'internet' => (
        'Internet mati atau lambat',
        [
          'Pastikan router terhubung ke sumber listrik.',
          'Periksa apakah kabel fiber dan LAN terpasang dengan baik.',
          'Matikan router selama 15 detik, lalu nyalakan kembali.',
          'Uji koneksi setelah lampu indikator stabil.',
        ],
      ),
      'los' => (
        'Lampu LOS merah',
        [
          'Jangan menekuk atau menarik kabel fiber optik.',
          'Pastikan kabel tidak terlepas dari modem.',
          'Restart modem satu kali dan tunggu hingga 3 menit.',
          'Jika lampu LOS masih merah, buat laporan gangguan.',
        ],
      ),
      'router' => (
        'Restart router dengan aman',
        [
          'Tekan tombol daya atau cabut adaptor router.',
          'Tunggu 15 detik sebelum menyalakan kembali.',
          'Tunggu hingga lampu internet berwarna normal.',
          'Hubungkan kembali perangkat Anda ke Wi-Fi.',
        ],
      ),
      _ => (
        'Panduan pembayaran',
        [
          'Pilih invoice aktif pada halaman Tagihan.',
          'Periksa jumlah dan tanggal jatuh tempo.',
          'Pilih QRIS, Virtual Account, atau e-wallet.',
          'Simpan bukti pembayaran sampai status diperbarui.',
        ],
      ),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Panduan bantuan')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          PageHeading(
            title: title,
            subtitle: 'Langkah sederhana yang dapat dicoba di rumah',
          ),
          const SizedBox(height: 18),
          for (var index = 0; index < steps.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SurfaceCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: AppTheme.primaryBlue.withValues(
                        alpha: 0.12,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        steps[index],
                        style: const TextStyle(height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () => context.push('/tickets/new'),
            icon: const Icon(Icons.report_problem_outlined),
            label: const Text('Buat laporan gangguan'),
          ),
        ],
      ),
    );
  }
}

class _HelpTopicTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _HelpTopicTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(
          question,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            answer,
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _billingNotifications = true;
  bool _serviceNotifications = true;
  bool _marketingNotifications = false;
  bool _registeringNotifications = false;
  bool _deviceRegistered = false;

  Future<void> _setNotificationPreference(
    bool enabled,
    ValueChanged<bool> updatePreference,
  ) async {
    final repository = ref.read(pushNotificationRepositoryProvider);
    if (!enabled || repository == null || _deviceRegistered) {
      setState(() => updatePreference(enabled));
      return;
    }

    setState(() => _registeringNotifications = true);
    try {
      final settings = await repository.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        if (mounted) {
          showAppMessage(context, 'Izin notifikasi belum diberikan.');
        }
        return;
      }
      await repository.registerDevice();
      if (mounted) {
        setState(() {
          _deviceRegistered = true;
          updatePreference(true);
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        showAppMessage(
          context,
          'Notifikasi tidak dapat diaktifkan. ${error.toString()}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _registeringNotifications = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Preferensi notifikasi')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const PageHeading(
            title: 'Atur notifikasi',
            subtitle: 'Pilih informasi yang ingin Anda terima',
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _billingNotifications,
            onChanged: _registeringNotifications
                ? null
                : (value) => _setNotificationPreference(
                    value,
                    (enabled) => _billingNotifications = enabled,
                  ),
            title: const Text('Tagihan dan pembayaran'),
            subtitle: const Text('Pengingat jatuh tempo dan status pembayaran'),
          ),
          SwitchListTile(
            value: _serviceNotifications,
            onChanged: _registeringNotifications
                ? null
                : (value) => _setNotificationPreference(
                    value,
                    (enabled) => _serviceNotifications = enabled,
                  ),
            title: const Text('Informasi layanan'),
            subtitle: const Text('Status langganan, tiket, dan pemeliharaan'),
          ),
          SwitchListTile(
            value: _marketingNotifications,
            onChanged: _registeringNotifications
                ? null
                : (value) => _setNotificationPreference(
                    value,
                    (enabled) => _marketingNotifications = enabled,
                  ),
            title: const Text('Promo dan penawaran'),
            subtitle: const Text('Informasi paket dan promosi terbaru'),
          ),
          const SizedBox(height: 14),
          const _InfoNotice(
            text:
                'Preferensi kategori berlaku selama sesi ini. Izin perangkat '
                'ditangani secara lokal untuk kebutuhan demo aplikasi.',
          ),
        ],
      ),
    );
  }
}

class LegalScreen extends StatelessWidget {
  final String document;

  const LegalScreen({super.key, required this.document});

  @override
  Widget build(BuildContext context) {
    final isPrivacy = document == 'privacy';
    return Scaffold(
      appBar: AppBar(
        title: Text(isPrivacy ? 'Kebijakan privasi' : 'Syarat dan ketentuan'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            isPrivacy ? 'Privasi pelanggan SpaceNet' : 'Ketentuan penggunaan',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          const Text(
            'Dokumen resmi akan ditampilkan di sini setelah disetujui dan '
            'dipublikasikan oleh PT Space Network Mediatama. Halaman ini '
            'merupakan placeholder UI dan bukan dokumen hukum yang berlaku.',
            style: TextStyle(color: AppTheme.textSecondary, height: 1.6),
          ),
          const SizedBox(height: 18),
          const _InfoNotice(
            text: 'Jangan gunakan konten placeholder ini sebagai kebijakan resmi.',
          ),
        ],
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tentang SpaceNet')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          Center(child: BrandLogo(width: 250)),
          SizedBox(height: 24),
          Center(
            child: Text(
              'SpaceNet Mobile',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(height: 8),
          Center(
            child: Text(
              'Your Internet, Your Control.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          SizedBox(height: 22),
          _InfoNotice(
            text:
                'Aplikasi layanan pelanggan PT Space Network Mediatama. '
                'Versi pratinjau Phase 2.',
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const _DetailRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: emphasized
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
                fontWeight: emphasized ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
                fontSize: emphasized ? 17 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool completed;

  const _TimelineEntry({
    required this.title,
    required this.subtitle,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            completed ? Icons.check_circle : Icons.radio_button_unchecked,
            color: completed ? AppTheme.success : AppTheme.textSecondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoNotice extends StatelessWidget {
  final String text;

  const _InfoNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: AppTheme.secondaryBlue,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
