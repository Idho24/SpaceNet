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
  "SUPABASE_ENABLE_PHONE_OTP": false
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
3. Aktifkan Authentication > Providers > Google dan isi OAuth client ID/secret sesuai konfigurasi Google.
4. Tambahkan `io.spacenet.mobile://login-callback` pada Authentication > URL Configuration > Redirect URLs. Untuk web, tambahkan origin aplikasi web yang dipakai.
5. Impor data pelanggan ke tabel `customers` menggunakan kredensial administrator dari lingkungan tepercaya, bukan aplikasi mobile. Nomor pelanggan harus E.164.
6. Migrasi mengaktifkan RLS, membatasi pembacaan data pelanggan pada akun yang sudah tertaut, melarang perubahan tabel oleh client, dan hanya mengizinkan pengaitan lewat RPC `link_customer`.

### 3. OTP dan pengaitan pelanggan

OTP lokal hanya aktif ketika Supabase tidak dikonfigurasi dan tidak dapat menautkan akun backend. Saat Supabase aktif, OTP dinonaktifkan secara default agar konfigurasi yang belum siap tidak mengirim SMS berbayar.

Untuk pengujian tanpa SMS, daftarkan nomor uji dan kode OTP di pengaturan Supabase Auth terlebih dahulu. Setelah itu, aktifkan `SUPABASE_ENABLE_PHONE_OTP` hanya pada konfigurasi lokal. Jika menggunakan provider SMS sungguhan, periksa biaya provider sebelum mengaktifkannya.

Setelah OTP dikonfirmasi oleh Supabase Auth, RPC memverifikasi nomor terkonfirmasi terhadap data pelanggan di database sebelum menyimpan tautan. Aplikasi tidak membaca profil pelanggan sebelum pengaitan berhasil.

### 4. Jalankan aplikasi

```powershell
flutter pub get
flutter run --dart-define-from-file=.env.supabase.local.json
```

Aplikasi tetap menyediakan mode demo lokal jika Supabase tidak dikonfigurasi, sehingga UI bisa terus dipakai dalam development tanpa kredensial produksi.
