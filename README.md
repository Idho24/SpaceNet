# SpaceNet Mobile

Aplikasi self-service pelanggan PT Space Network Mediatama dengan Flutter.

## Menjalankan aplikasi

Pastikan Flutter SDK sesuai constraint Dart pada `pubspec.yaml` sudah terpasang.
Untuk menjalankan di perangkat Android, siapkan Android SDK dan emulator atau
hubungkan perangkat dengan USB debugging aktif.

```powershell
flutter pub get
flutter run --dart-define-from-file=.env.supabase.local.json
```

Untuk pengujian login Google di web, gunakan port tetap:

```powershell
flutter run -d chrome --web-port 3000 --dart-define-from-file=.env.supabase.local.json
```

## Pemeriksaan

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

Uji widget mencakup alur login pratinjau, lima tab utama, pembayaran, pengajuan
tiket, serta seluruh rute fitur pada lebar layar ponsel 320 px.

## Supabase setup (versi non-Firebase)

Aplikasi ini sekarang menggunakan Supabase untuk autentikasi, profil pengguna, dan data pelanggan. Konfigurasi lokal disimpan di file `.env.supabase.local.json` dan tidak dipublikasikan ke Git.

### 1. Buat konfigurasi lokal

```json
{
  "SUPABASE_URL": "https://your-project.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "your-publishable-key",
  "SUPABASE_ENABLE_PHONE_OTP": false,
  "SUPABASE_TESTING_MODE": false
}
```

Simpan file itu di root project, lalu jalankan:

```powershell
flutter run --dart-define-from-file=.env.supabase.local.json
```

`.env.supabase.local.json` sudah ditambahkan ke `.gitignore`.
Jangan masukkan `service_role` key atau JWT secret ke aplikasi mobile.

### 2. Konfigurasi Supabase

1. Buat project baru di Supabase.
2. Jalankan migrasi `supabase/migrations/20261104000000_customer_security.sql` melalui Supabase CLI atau SQL Editor.
3. Jika menjalankan `SUPABASE_TESTING_MODE=true`, jalankan `supabase/testing/20261111000000_testing_link_customer.sql` secara manual hanya pada project pengujian terpisah. File ini sengaja berada di luar folder migrasi agar tidak ikut diterapkan oleh `supabase db push` di production. Migrasi ini menyediakan validasi OTP lokal dan pengaitan tanpa OTP; jangan jalankan di production.
4. Aktifkan Authentication > Providers > Google dan isi OAuth client ID/secret sesuai konfigurasi Google.
5. Tambahkan `io.spacenet.mobile://login-callback` pada Authentication > URL Configuration > Redirect URLs. Untuk web lokal dengan perintah di atas, tambahkan `http://localhost:3000/**`. Aplikasi mengarahkan callback OAuth ke origin web yang sedang digunakan.
6. Impor data pelanggan ke tabel `customers` menggunakan kredensial administrator dari lingkungan tepercaya, bukan aplikasi mobile. Nomor pelanggan harus E.164.
7. Migrasi production mengaktifkan RLS, membatasi pembacaan data pelanggan pada akun yang sudah tertaut, melarang perubahan tabel oleh client, dan hanya mengizinkan pengaitan lewat RPC `link_customer`.

### Midtrans Sandbox

1. Setelah data pelanggan diimpor, jalankan `supabase/migrations/20261112000000_midtrans_core_api.sql` melalui SQL Editor Supabase. Migrasi ini membuat tabel invoice dan pembayaran; invoice contoh `INV-2026-10-001` hanya dibuat jika pelanggan `0012995` sudah ada. Invoice lain harus diisi backend billing tepercaya. Jangan jalankan migrasi pengujian OTP ke project production.
   Untuk membuat invoice awal seluruh pelanggan, jalankan `supabase/operations/create_current_cycle_invoices.sql` secara manual di SQL Editor dengan hak administrator. Skrip memvalidasi paket dan pelanggan sebelum mengubah tarif Basic Rp150.000, Gamer Rp350.000, Home Rp170.000, dan Pro Rp220.000 per bulan. Skrip membuat satu invoice unpaid per pelanggan untuk tanggal pemasangan bulanan berikutnya (tanggal 29-31 disesuaikan ke hari terakhir bulan); periode yang sudah memiliki invoice tidak diduplikasi. Skrip ini bukan migrasi otomatis dan tidak boleh dijalankan dari aplikasi.
2. Ambil **Server Key Sandbox** dari dashboard Midtrans Sandbox. Beri key izin **Snap Checkout: Write** untuk membuat checkout dan **Core API: Read** untuk memeriksa status transaksi. Simpan hanya sebagai secret Edge Function di Supabase (`Project Settings > Edge Functions > Secrets`) dengan nama `MIDTRANS_SERVER_KEY`. Jangan masukkan Server Key ke file konfigurasi Flutter atau Git.
3. Deploy function:

   ```powershell
   supabase functions deploy create-midtrans-payment
   supabase functions deploy get-midtrans-payment-status
   supabase functions deploy midtrans-webhook
   ```

4. Di pengaturan notifikasi Midtrans Sandbox, atur **Payment Notification URL** menjadi `https://<project-ref>.supabase.co/functions/v1/midtrans-webhook`.
5. Masuk ke aplikasi dengan akun Supabase sungguhan yang sudah tertaut ke pelanggan. Daftar invoice diambil dari Supabase dan dibatasi RLS ke pelanggan yang tertaut; `customer_id` invoice harus cocok dengan `customer_id` pada profil akun. Invoice contoh hanya untuk pelanggan `0012995`. Akun demo lokal tidak dapat membuat transaksi; nominal invoice dibaca dan divalidasi di server.
6. Snap membuka halaman checkout Midtrans Sandbox. Metode yang tersedia (mis. QRIS, Virtual Account, dan e-wallet) mengikuti aktivasi metode pada akun Sandbox. Status lunas hanya berubah setelah notifikasi/status transaksi diverifikasi di server.
7. Jika checkout menampilkan HTTP 403, periksa log `create-midtrans-payment` dan pastikan secret `MIDTRANS_SERVER_KEY` di project Supabase berisi **Server Key Sandbox** akun yang sama (awalan `SB-Mid-server-`), bukan Client Key atau key Production. Setelah mengubah secret, coba kembali dari aplikasi.
8. Untuk menerima notifikasi, webhook menggunakan secret Edge Function `MIDTRANS_SERVER_KEY` yang sama dengan Server Key Sandbox untuk checkout dan pemeriksaan status. Midtrans menghitung signature notifikasi menggunakan Server Key; tidak perlu secret signature terpisah.
9. Agar checkout kembali ke halaman bukti aplikasi, atur **Settings > Snap Preference > System Settings > Finish Redirect URL** pada akun Sandbox ke alamat web aplikasi, misalnya `http://localhost:3000/#/payment-result` untuk development. Jalankan web dengan port tetap (`flutter run -d chrome --web-port 3000 --dart-define-from-file=.env.supabase.local.json`). Halaman hasil mengambil status dari API Midtrans lewat backend; jangan gunakan parameter status pada URL sebagai bukti lunas. Untuk deployment, gunakan alamat HTTPS aplikasi yang dapat diakses pelanggan.

### 3. OTP dan pengaitan pelanggan

Catatan pemeriksaan status Snap: respons Core API `status_code: 404` dapat
terjadi sebelum pelanggan memilih metode pembayaran. Backend mempertahankan
status `pending` dan mengarahkan pelanggan untuk membuka checkout apabila belum
ada referensi transaksi/metode pembayaran. Respons ini bukan bukti pembayaran
gagal atau lunas. Error akses dan 404 untuk transaksi yang sudah memiliki
referensi tetap ditampilkan. Halaman pembayaran memeriksa status setiap 10 detik
saat aktif; invoice hanya dilunasi setelah respons Midtrans yang cocok diverifikasi.

Uji regresi backend (Node.js dengan dukungan TypeScript bawaan):

```powershell
node --test supabase/tests/midtrans_status_test.ts
node --experimental-vm-modules --test supabase/tests/payment_status_endpoint_test.mjs
```

Setelah mengubah backend, deploy ulang `get-midtrans-payment-status`; hot reload
Flutter saja tidak memperbarui Edge Function di Supabase.

OTP lokal hanya aktif ketika Supabase tidak dikonfigurasi dan tidak dapat menautkan akun backend. Saat Supabase aktif, OTP dinonaktifkan secara default agar konfigurasi yang belum siap tidak mengirim SMS berbayar.

Untuk pengujian tanpa SMS, daftarkan nomor uji dan kode OTP di pengaturan Supabase Auth terlebih dahulu. Setelah itu, aktifkan `SUPABASE_ENABLE_PHONE_OTP` hanya pada konfigurasi lokal. Jika menggunakan provider SMS sungguhan, periksa biaya provider sebelum mengaktifkannya.

Setelah OTP dikonfirmasi oleh Supabase Auth, RPC memverifikasi nomor terkonfirmasi terhadap data pelanggan di database sebelum menyimpan tautan. Aplikasi tidak membaca profil pelanggan sebelum pengaitan berhasil.
Setelah akun tertaut, nama pada beranda diambil dari kolom `customers.name`; nama akun Google hanya digunakan sebelum ID pelanggan tertaut.

### 4. Jalankan aplikasi

```powershell
flutter pub get
flutter run --dart-define-from-file=.env.supabase.local.json
```

Aplikasi tetap menyediakan mode demo lokal jika Supabase tidak dikonfigurasi, sehingga UI bisa terus dipakai dalam development tanpa kredensial produksi.


### Sinkronisasi Midtrans DANA

DANA memakai `transaction_id` dan header `transaction-source: SNAP_API` saat
memeriksa status. Webhook memvalidasi signature; jika signature tidak cocok,
backend melakukan challenge GET Status menggunakan Server Key di server.
Hanya respons Midtrans yang cocok dengan order, nominal, mata uang, dan
transaction ID yang boleh diterapkan. Isi status callback yang gagal signature
tidak dipakai sebagai bukti pembayaran.

Terapkan migrasi `20261118000000_atomic_midtrans_status.sql` sebelum deploy ulang
`midtrans-webhook` dan `get-midtrans-payment-status`. RPC pembaruan hanya dapat
dijalankan service_role; pembayaran dan tagihan diperbarui dalam satu transaksi.
Notifikasi pending yang terlambat tidak menurunkan status paid.

Untuk transaksi DANA lama yang notifikasinya sudah ditolak dan transaction ID
belum tersimpan, kirim ulang notifikasi dari detail transaksi Midtrans Sandbox.
Jangan membuat pembayaran baru atau mengubah tagihan ke paid secara manual.

Pengujian backend:
```sh
node --experimental-vm-modules --test supabase/tests/midtrans_status_test.ts supabase/tests/payment_status_endpoint_test.mjs supabase/tests/midtrans_webhook_test.mjs supabase/tests/midtrans_apply_test.mjs
```
`supabase/tests/atomic_midtrans_status_test.sql` menguji RPC dengan fixture terpisah
dalam transaksi yang di-rollback, termasuk nominal, settlement, notifikasi
berulang, pemulihan invoice, dan batas akses.


### Setelah pembayaran: kembali, riwayat, dan masa aktif

Checkout web baru mengirim alamat aplikasi yang sedang dibuka sebagai returnUrl.
Backend membatasi alamat kembali ke origin yang sama, mengisi callbacks.finish
serta callback DANA/GoPay/ShopeePay, dan menyertakan order_id secara eksplisit.
Halaman hasil memeriksa status melalui backend; hanya status paid terverifikasi
yang mengarahkan ke /billing dan memuat ulang tagihan, riwayat, serta pelanggan.
Tautan checkout lama tetap memakai konfigurasi saat dibuat.

Riwayat menggunakan RPC get_my_payment_history, dibatasi ke akun dan pelanggan
yang terhubung. Kolom Berakhir membaca customers.expiry_date. Migrasi
20261118010000_payment_history_and_renewal.sql memperpanjang satu bulan kalender
dari tanggal berakhir saat ini atau waktu pembayaran (mana yang lebih akhir).
Penanda per invoice mencegah perpanjangan ganda dari notifikasi berulang.
Migrasi juga memulihkan invoice yang sudah memiliki pembayaran Midtrans paid.
Ini memperbarui langganan aplikasi; integrasi provisioning router MikroTik
belum ditambahkan oleh perubahan ini.

Validasi:
- Backend: node --experimental-vm-modules --test supabase/tests/*.mjs supabase/tests/*.ts
- Database: supabase/tests/payment_renewal_test.sql (fixture di-rollback).
- Flutter: flutter test test/payment_flow_test.dart test/widget_test.dart
- Jalankan ulang aplikasi web: flutter run -d chrome --web-port 3000 --dart-define-from-file=.env.supabase.local.json

Untuk aplikasi native, tentukan PAYMENT_RETURN_URL (alamat HTTPS aplikasi)
saat build, atau MIDTRANS_FINISH_URL pada Edge Function. Deep link native
memerlukan konfigurasi platform tersendiri.

### Laporan pelanggan dan admin

- Pelanggan: Bantuan → Buat laporan. Kategori, deskripsi, dan foto opsional dikirim
  ke Supabase; daftar laporan tidak lagi menggunakan data contoh.
- Admin browser: http://localhost:3000/#/admin/reports (ganti origin jika dihosting).
  Masuk menggunakan Google **spacenetlite@gmail.com**. Akun admin tidak perlu
  menghubungkan ID pelanggan. Gunakan profil browser terpisah untuk membuka
  sesi pelanggan dan admin bersamaan.
- Status: Laporan diterima → Sedang ditinjau → Dalam penanganan → Selesai.
  Admin wajib memberi catatan saat mengubah status, dan dapat membuka ulang
  atau membatalkan laporan. Pelanggan dapat berkomentar atau membatalkan laporan
  yang masih terbuka. Catatan admin terlihat oleh pelanggan.
- Daftar dan detail diperbarui otomatis setiap 10 detik. Pelanggan hanya dapat
  membaca laporannya sendiri. Foto JPG/PNG/WebP maksimal 5 MB disimpan di bucket
  privat dengan URL sementara yang berlaku 5 menit.
- Untuk lingkungan baru, terapkan migrasi `20261118132806_support_reports.sql`,
  lalu jalankan `supabase/operations/support_admin.sql` sebagai operator database.
  Daftar email admin berada di schema privat; aplikasi tidak dapat mengeditnya.
  Email harus terverifikasi dan akun anonim tidak mendapat akses admin.
- ID permintaan tetap mencegah laporan ganda saat pengiriman diulang. Versi laporan
  mencegah penimpaan oleh pembaruan bersamaan. Status dan catatan tersimpan atomik.

Validasi:
- Database: `supabase/tests/support_reports_test.sql` (fixture di-rollback).
- Flutter: `flutter test test/support_flow_test.dart test/widget_test.dart`.
- Muat kode web terbaru dengan menjalankan ulang:
  `flutter run -d chrome --web-port 3000 --dart-define-from-file=.env.supabase.local.json`.

### Pengumuman perbaikan dan gangguan massal

Admin membuka `/admin/announcements` atau tombol **Pengumuman layanan** di halaman
laporan pelanggan. Isi jenis informasi, judul, area terdampak, keterangan, dan
status, lalu tekan **Terbitkan**. Semua pelanggan yang sudah terhubung dapat
membaca pengumuman; area adalah keterangan, bukan filter penerima.

Pengumuman muncul di menu Notifikasi dan, selama belum selesai, banner beranda.
Tanda belum dibaca tersimpan per akun di server. Pembaruan status atau keterangan
membuat pengumuman menjadi belum dibaca kembali. Daftar dimuat ulang setiap
10 detik setelah permintaan sebelumnya selesai. Status **Selesai** menghapus
banner aktif tetapi tetap ada di riwayat; **Arsipkan** menyembunyikan pengumuman
dari pelanggan. Admin tetap bisa mengakses dan memulihkannya.

Preferensi **Informasi layanan** menyimpan pengaturan banner dan badge per akun.
Riwayat tetap tersedia saat preferensi dimatikan. Notifikasi ini berada di dalam
aplikasi, bukan push saat aplikasi/browser ditutup; FCM/Web Push belum dikonfigurasi.
Menu notifikasi contoh dan pengaturan registrasi perangkat palsu sudah diganti.

Migrasi: `20261120130126_service_announcements.sql`.
Tes database: `supabase/tests/service_announcements_test.sql`, seluruh fixture
di-rollback tanpa menerbitkan pengumuman nyata. Tes antarmuka:
`flutter test test/announcement_flow_test.dart test/support_flow_test.dart test/widget_test.dart`.
