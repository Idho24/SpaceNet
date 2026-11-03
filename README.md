# SpaceNet Mobile

Aplikasi self-service pelanggan PT Space Network Mediatama dengan Flutter.

## Menjalankan aplikasi

Pastikan Flutter SDK sesuai constraint Dart pada `pubspec.yaml` sudah terpasang.
Untuk menjalankan di perangkat Android, siapkan Android SDK dan emulator atau
hubungkan perangkat dengan USB debugging aktif.

```powershell
flutter pub get
flutter run
```

## Pemeriksaan

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

Uji widget mencakup alur login pratinjau, lima tab utama, pembayaran, pengajuan
tiket, serta seluruh rute fitur pada lebar layar ponsel 320 px.

## Firebase lokal (Phase 3)

### 1. Buat konfigurasi lokal

Buat `.env.firebase.local.json` di root proyek, lalu isi nilai dari Firebase
Console. Jangan gunakan placeholder saat menjalankan aplikasi dan jangan commit
file ini:

```json
{
  "FIREBASE_PROJECT_ID": "nilai-dari-firebase-console",
  "FIREBASE_API_KEY": "nilai-dari-firebase-console",
  "FIREBASE_MESSAGING_SENDER_ID": "nilai-dari-firebase-console",
  "FIREBASE_AUTH_DOMAIN": "nilai-dari-firebase-console",
  "FIREBASE_STORAGE_BUCKET": "nilai-dari-firebase-console",
  "FIREBASE_ANDROID_APP_ID": "nilai-dari-firebase-console",
  "FIREBASE_IOS_APP_ID": "nilai-dari-firebase-console",
  "FIREBASE_WEB_APP_ID": "nilai-dari-firebase-console",
  "FIREBASE_IOS_BUNDLE_ID": "nilai-dari-firebase-console",
  "FIREBASE_MEASUREMENT_ID": "nilai-dari-firebase-console",
  "GOOGLE_WEB_CLIENT_ID": "OAuth-Web-client-ID",
  "FIREBASE_APP_CHECK_WEB_SITE_KEY": "reCAPTCHA-v3-site-key",
  "FIREBASE_MESSAGING_VAPID_KEY": "Web-Push-certificate-key",
  "FIREBASE_USE_EMULATORS": true,
  "FIREBASE_ENABLE_APP_CHECK": false,
  "FIREBASE_EMULATOR_HOST": "127.0.0.1"
}
```

Save it as an ignored local file such as `.env.firebase.local.json`, then run:

```powershell
flutter run --dart-define-from-file=.env.firebase.local.json
```

`.env.firebase.local.json` sudah dicantumkan dalam `.gitignore`.

### 2. Atur autentikasi dan emulator

Aktifkan Google Sign-In sebagai provider di Firebase Console. Konfigurasikan
OAuth client sesuai platform: SHA-1/SHA-256 untuk Android, URL scheme dari
reversed client ID untuk iOS, dan authorized origins untuk Web.

Untuk uji OTP tanpa mengirim SMS dan Firestore lokal, pasang Firebase CLI lalu
jalankan Auth dan Firestore Emulator di terminal:

```powershell
firebase emulators:start --only auth,firestore --project <project-id-anda>
```

Gunakan ID proyek yang sesuai dengan konfigurasi lokal, dan biarkan
`FIREBASE_USE_EMULATORS` bernilai `true`. Aplikasi mengarahkan Firebase Auth
dan Firestore ke emulator pada host yang ditentukan oleh
`FIREBASE_EMULATOR_HOST`. Muat [firestore.rules](./firestore.rules) di emulator
dan siapkan dokumen `customers/{customer_id}` melalui emulator sebelum menguji
link pelanggan. Nomor pelanggan harus berformat E.164, misalnya
`+6283125998929`.

Auth Emulator tidak mengirim SMS produksi. Gunakan nomor uji/OTP yang disiapkan
melalui alur emulator. Tanpa Firebase configuration, aplikasi memakai
repository demo dan OTP lokal terpisah; demo OTP hanya untuk pratinjau dan
tidak dapat menghubungkan akun Firebase atau menulis ke Firestore.

### 3. Jalankan aplikasi

Di terminal lain, dari root proyek:

```powershell
flutter run --dart-define-from-file=.env.firebase.local.json
```

Google Sign-In memerlukan konfigurasi provider dan OAuth client yang benar;
emulator terutama digunakan untuk menguji OTP dan Firestore. Untuk Android
debug App Check, daftarkan debug token yang dicetak SDK di Firebase Console
sebelum mengaktifkannya. App Check dilewati saat emulator aktif. Jangan
nonaktifkan `FIREBASE_USE_EMULATORS` sampai proyek Firebase dan platform OAuth
siap; SMS produksi tetap dinonaktifkan di aplikasi untuk menghindari biaya tak
terduga.

### Spark Plan limits

Firestore, Firebase Authentication with Google, FCM, and App Check have free
usage subject to Firebase quotas and platform setup. Firebase Phone
Authentication SMS may incur charges, so do not use production SMS when
requiring a zero-cost test; use the Auth Emulator. Cloud Storage is not enabled:
the requested 5 GB storage allowance is not available on Spark for current
Firebase Storage buckets and requires a billing plan. The Storage repository
and rules are not used by the app. No Cloud Functions are required.

Customer records must be provisioned by a trusted administrator with the phone
stored in E.164 format. Firestore rules allow a one-time atomic link only after
the signed-in Firebase account has a verified phone-number claim matching that
record. Customer details are readable only after the link succeeds; clients
cannot edit customer business data.

The FCM repository requests notification permission and registers an app
instance when called. Web builds also need the VAPID key from Firebase Console.
Keep FCM HTTP v1 service-account credentials on a trusted sender; never put
them in the mobile app. The client does not send notifications or store device
tokens in customer documents.
