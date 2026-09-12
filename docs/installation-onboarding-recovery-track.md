# Jalur khusus: instalasi, pemulihan, dan onboarding pengguna baru

Status: **tercatat untuk ditangani; belum diimplementasikan**.
Tanggal laporan: 5 September 2026. Konteks: pengujian instalasi AkuBrowser v0.9.0 RC3 pada lingkungan pengguna.

## Tujuan

Menangani perjalanan instalasi sampai pengguna memperoleh akses sumber sebagai satu jalur perbaikan. Instalasi yang berhasil menyalin binary belum berarti pengguna berhasil memakai produk. Pengguna harus memahami status, hambatan, dan tindakan berikutnya tanpa mencari residu sendiri, menebak perlunya Chrome, atau mencoba restart tanpa arahan.

Dokumen ini mencatat laporan, bukti, kebutuhan mitigasi, dan kriteria penerimaan. Ini bukan persetujuan untuk menghapus data, memindahkan sesi Chrome, mengubah arsitektur browser, atau menerapkan perbaikan.

## Urutan kejadian yang dilaporkan

1. Instalasi/startup berulang kali gagal dengan ketidakcocokan schema database: pengguna melaporkan schema lama 5, sedangkan runtime baru membutuhkan 25.
2. Setelah mencari residu instalasi dan membersihkannya, aplikasi dapat terinstal dan menyala. Lokasi serta isi residu yang dibersihkan belum tercatat; jangan menganggap tindakan tersebut sebagai prosedur pemulihan yang sudah tervalidasi.
3. Peluncuran berikutnya tertahan pada layar putih. Banner Chrome for Testing menampilkan tautan **Download Chrome**, tanpa panduan AkuBrowser yang menjelaskan langkah selanjutnya.
4. Karena bingung, pengguna menutup lalu membuka aplikasi. Setelah itu halaman **Grant access** muncul. Penyebab perbedaan peluncuran pertama dan kedua belum diketahui.
5. Pengguna harus login ulang karena sesi Chrome yang biasa dipakai tidak tersedia di profil AkuBrowser. Ini dilaporkan sebagai hambatan adopsi yang besar karena pengguna mengandalkan sesi Chrome yang sudah login.

## Bukti dan batas kepastian

- Photo 1: aplikasi browser berhalaman putih dan terminal runtime terlihat bersamaan. Log yang terbaca menunjukkan AkuSidecar 0.9.0, runtime Go, endpoint lokal `127.0.0.1:11122`, peluncuran app-shell Chromium, serta Auto Update ditunda sampai onboarding selesai. Ini membuktikan sebagian startup berlangsung, bukan bahwa UI atau onboarding sudah siap.
- Photo 2: halaman putih lebih jelas; banner Chrome for Testing dan tautan **Download Chrome** terlihat. Tampilan ini dapat mengarahkan pengguna mengunduh Chrome meskipun paket AkuBrowser sudah membawa browser sendiri. Belum ada laporan bahwa pengguna benar-benar mengklik tautan tersebut.
- Kedua foto tidak memperlihatkan error schema awal atau halaman Grant access setelah restart; kedua kejadian itu bersumber dari laporan pengguna.
- Referensi foto lokal sesi: `.codex-remote-attachments/01a07138-1baa-7cd1-9e0b-32c6a596c84f/c6c0e4a4-5f4f-4a40-ae67-5efc5d28d386/1-Photo-1.jpg` dan `2-Photo-2.jpg`, relatif terhadap AkuWorkspace. Foto tidak disalin ke repository atau dipublikasikan; ketersediaan lampiran tidak dijamin di checkout lain.
- Pemeriksaan kode sebelumnya: `AkuSidecar/internal/store/store.go` menyediakan migrasi mulai schema 7; schema 5 tidak mempunyai jalur migrasi. `TestRetiredSchemasFailWithoutMutation` secara eksplisit menguji penolakan schema 5. Kontrak installer RC3 menerima schema 7–25.
- Installer mempertahankan data pengguna. Karena itu pemasangan ulang binary saja tidak menyelesaikan database lama yang tidak didukung. Lokasi database default adalah `%LOCALAPPDATA%\AkuBrowser\data\aku-sidecar.db`; lokasi aktual pada mesin pengujian belum diverifikasi.
- Validasi build RC3 yang lulus tidak membuktikan pengalaman upgrade schema 5 atau keberhasilan onboarding pertama pada mesin pengguna. Tahap persis yang berhenti tanpa pesan (installer, launcher, atau Sidecar) perlu dipastikan.

## INST-01 — Residu dan schema lama: kegagalan harus bisa dipulihkan

Prioritas: tinggi, menghalangi penggunaan.

Masalah: pengguna hanya mengalami kegagalan/keluar tanpa pesan yang membantu dan harus menemukan residu sendiri. Binary baru tidak otomatis berarti database lama kompatibel.

Kebutuhan perbaikan:

- Deteksi database yang sudah ada serta schema aktual sebelum aktivasi runtime; tampilkan kompatibilitas dan tindakan yang tersedia.
- Jelaskan schema ditemukan, schema tujuan, lokasi data, apakah migrasi didukung, dan alasan aplikasi belum dapat dibuka menggunakan bahasa pengguna.
- Untuk schema tidak didukung, sediakan pemulihan terpandu yang melindungi data: cadangan terverifikasi, pilihan mempertahankan data, serta pilihan mulai dengan data baru yang membutuhkan persetujuan eksplisit dan menjelaskan dampaknya.
- Jangan menyarankan mengubah angka schema secara manual atau menghapus seluruh folder sebagai solusi umum. Penanganan database dan profil browser harus dibedakan agar pemulihan database tidak ikut menghilangkan sesi login.
- Tampilkan error yang tetap dapat dibaca, tombol menyalin diagnostik, lokasi log, dan langkah mitigasi. Pengguna tidak boleh harus membaca terminal yang segera tertutup.

Mitigasi sementara yang perlu dipandu: identifikasi lokasi data dan error aktual, cadangkan data sebelum tindakan, lalu tentukan apakah data lama harus dipertahankan atau pengguna menyetujui database baru. Keberhasilan pembersihan pada laporan ini bukan izin untuk mengulang penghapusan pada pengguna lain.

Kriteria penerimaan: uji instalasi bersih, upgrade schema yang didukung, residu schema 5, database bermasalah, dan pembatalan pemulihan. Setiap kegagalan menampilkan alasan dan tindakan berikutnya; data tidak berubah tanpa jalur yang diizinkan; mengulang instalasi tidak menjebak pengguna pada kegagalan yang sama tanpa penjelasan.

## INST-02 — Layar putih dan banner Download Chrome

Prioritas: tinggi, menghalangi onboarding dan mengarahkan tindakan yang salah.

Masalah: proses backend dapat hidup sementara halaman produk kosong. Banner browser menjadi satu-satunya arahan yang terlihat, sehingga pengguna dapat menyimpulkan bahwa mereka harus mengunduh Chrome.

Tambahan bukti pengguna, 5 September 2026: setelah onboarding berhasil dilewati, banner **Chrome for Testing** beserta tautan **Download Chrome** tetap muncul. Foto terbaru memperlihatkan halaman **Settings** AkuBrowser sudah dirender, dengan pengaturan sumber terlihat di bawah banner. Artinya masalah banner juga terjadi saat UI sudah dapat digunakan; penyelesaiannya tidak boleh bergantung pada perbaikan layar putih atau dianggap selesai ketika onboarding berhasil.

Referensi foto tambahan lokal sesi: `.codex-remote-attachments/01a07138-1baa-7cd1-9e0b-32c6a596c84f/75fc2188-54b6-4fb2-9dc9-911a0bf8acef/1-Photo-1.jpg`, relatif terhadap AkuWorkspace. Keberhasilan melewati onboarding berasal dari laporan pengguna; tampilan Settings dan banner didukung foto. Belum ada bukti pengguna benar-benar mengklik tautan unduhan.

Kebutuhan perbaikan:

- Tampilkan status persiapan yang bermakna sejak peluncuran pertama, dengan batas waktu dan jalur pemulihan yang terlihat ketika UI gagal siap.
- Bedakan kesiapan Sidecar, navigasi browser, pemuatan aset/UI, Bridge, dan onboarding. Respons health backend saja bukan bukti halaman berhasil tampil.
- Sediakan retry yang terarah dan diagnostik saat timeout; jelaskan jika aplikasi membutuhkan restart, beserta cara dan alasannya.
- Evaluasi penyajian browser bawaan dan banner Chrome for Testing agar tidak memberi arahan mengunduh browser lain yang tidak diperlukan oleh distribusi ini. Pilihan teknis belum ditentukan.

Investigasi yang masih diperlukan: urutan startup, navigasi awal, waktu kesiapan Bridge, error JavaScript/aset, inisialisasi profil pertama, serta perbedaan peluncuran pertama dan kedua. Race startup adalah hipotesis, bukan diagnosis yang sudah terbukti.

Kriteria penerimaan: peluncuran pertama pada profil baru menampilkan status lalu halaman yang dapat digunakan, atau error dengan langkah pemulihan; tidak berhenti pada layar putih tanpa batas; tidak membuat Download Chrome menjadi satu-satunya tindakan yang tersedia.

Kriteria tambahan untuk banner: verifikasi setelah onboarding, pada halaman utama/Settings, dan setelah buka ulang. Pengalaman aplikasi tidak boleh tetap mengarahkan pengguna mengunduh Chrome sebagai langkah yang diperlukan untuk memakai AkuBrowser. Perbaikan layar putih saja tidak menutup masalah banner; keduanya memerlukan bukti penerimaan masing-masing. Solusi teknis banner belum dipilih atau diimplementasikan.

## INST-03 — Perjalanan ke Grant access terputus dan bergantung restart

Prioritas: tinggi, satu rangkaian dengan INST-02.

Masalah: halaman Grant access baru terlihat setelah pengguna menutup dan membuka ulang aplikasi tanpa panduan. Pemulihan kebetulan ini belum merupakan perjalanan produk yang dapat diterima.

Kebutuhan perbaikan:

- Definisikan satu urutan yang terlihat: instalasi selesai → runtime siap → UI siap → Grant access → kesiapan sumber → siap digunakan.
- Simpan progres onboarding dan pulihkan ke langkah yang benar setelah aplikasi ditutup, gagal, atau dibuka kembali.
- Jika kesiapan berubah selama halaman terbuka, UI harus melanjutkan atau menawarkan tindakan yang jelas tanpa menuntut restart yang tidak dijelaskan.

Kriteria penerimaan: uji peluncuran pertama, buka ulang sebelum/sesudah pemberian akses, startup lambat, serta gangguan pada setiap tahap. Pengguna selalu tahu posisi dan langkah berikutnya; pemberian akses tidak harus diulang karena state yang hilang.

## INST-04 — Login ulang dan kontinuitas sesi Chrome

Prioritas: tinggi sebagai hambatan aktivasi/adopsi.

Masalah: profil Chromium AkuBrowser terisolasi sehingga sesi Chrome pengguna tidak otomatis terbawa. Pengguna mengandalkan sesi yang sudah aktif dan menganggap login ulang sebagai beban besar. Ini adalah keputusan pengalaman produk yang perlu ditinjau, bukan sekadar tambahan teks bantuan.

Kebutuhan dan keputusan yang perlu diselesaikan:

- Beri tahu kebutuhan login dan pemisahan profil sebelum pengguna mencapai langkah yang mengejutkan tersebut.
- Evaluasi jalur resmi yang dapat memakai sesi browser yang sudah aktif, dibanding mempertahankan browser terisolasi dengan login terpandu. Jelaskan dampak terhadap distribusi, izin, dukungan browser, keamanan sesi, dan beban pengguna sebelum memilih arsitektur.
- Jangan mengasumsikan cookie/sesi dapat disalin dengan aman atau bahwa impor sesi sudah didukung. Jangan menyalin profil aktif atau kredensial secara diam-diam.
- Bila login ulang tetap diperlukan, bantu pengguna per sumber, tampilkan progres, dan pastikan sesi tersimpan pada peluncuran berikutnya. Akses Bridge dan login ke sumber harus dijelaskan sebagai dua kebutuhan yang berbeda.

Kriteria penerimaan: pengguna mengetahui kebutuhan login sebelum memulai, mendapat panduan yang dapat dijalankan, dan tidak diminta login ulang tanpa alasan setelah restart normal. Keputusan mengenai penggunaan sesi Chrome yang sudah aktif harus terdokumentasi, termasuk keterbatasan teknis yang telah diverifikasi.

## INST-05 — Panduan memperoleh API key Gemini dan memahami kuota

Prioritas: tinggi untuk aktivasi pengguna yang memilih Gemini. Status: tercatat, belum diimplementasikan.

Masalah: pengguna yang memilih Gemini tetapi belum memiliki API key tidak mendapat arahan yang cukup untuk memperolehnya. Permintaan pengguna juga mencakup informasi jatah gratis 1.000 request per hari; angka tersebut perlu diverifikasi untuk model dan proyek yang digunakan sebelum dijadikan janji produk.

Kebutuhan perbaikan:

- Saat Gemini dipilih, tampilkan tindakan **Belum punya API key? Dapatkan di Google AI Studio** menuju [halaman API key resmi](https://aistudio.google.com/apikey), dekat kolom key.
- Berikan langkah singkat: masuk dengan akun Google → ikuti pembuatan/pemilihan proyek dan API key di AI Studio → salin key → kembali ke AkuBrowser → tempel dan validasi → lanjutkan onboarding.
- Pertahankan progres ketika pengguna membuka situs tersebut dan kembali ke aplikasi. Pengguna yang sudah punya key dapat langsung melanjutkan.
- Jelaskan ketersediaan free tier sesuai model/proyek dan sediakan tautan untuk memeriksa kuota aktual. Jangan mencantumkan **gratis 1.000 request per hari** sebagai jaminan umum atau menyamakan request API dengan satu aksi pengguna di AkuBrowser.
- Jika angka 1.000 telah diverifikasi untuk model/proyek tertentu, tampilkan konteks model/tier dan tanggal verifikasi; tetap beri akses ke kuota aktual. Kuota yang belum diketahui tidak boleh ditampilkan sebagai nol atau sebagai jatah pasti.
- Berikan pesan dan langkah berikutnya yang berbeda untuk key tidak valid, akses model tidak tersedia, dan kuota habis. Jangan membuat pengguna mengulang registrasi ketika penyebabnya kuota.

Verifikasi sumber resmi, 5 September 2026: [panduan API key](https://ai.google.dev/gemini-api/docs/api-key) mengarahkan pembuatan key melalui Google AI Studio. [Dokumentasi rate limits](https://ai.google.dev/gemini-api/docs/rate-limits) menyatakan limit bergantung antara lain pada tier dan dapat dilihat di AI Studio; ini tidak mendukung jaminan universal 1.000 request gratis per hari. Rujuk juga [pricing resmi](https://ai.google.dev/gemini-api/docs/pricing) saat menulis informasi free tier.

Kriteria penerimaan: pengguna tanpa key dapat menemukan tautan dan menyelesaikan alur kembali ke AkuBrowser tanpa kehilangan progres; pengguna dengan key dapat langsung validasi; informasi kuota memiliki sumber dan tidak menjanjikan angka yang belum terverifikasi.

## Penanganan dalam satu jalur

1. Lengkapi reproduksi dan diagnostik pada lingkungan pengujian: versi/hash installer, schema/error aktual, residu yang dibersihkan, dan jejak peluncuran pertama/kedua tanpa mengumpulkan isi sesi pribadi.
2. Tangani deteksi serta pesan pemulihan schema lama (INST-01).
3. Tangani kesiapan UI, layar putih, dan kelanjutan ke Grant access sebagai satu perjalanan (INST-02/03).
4. Putuskan pendekatan kontinuitas sesi dan login bersama pengalaman onboarding (INST-04).
5. Lengkapi alur pilihan Gemini dengan panduan mendapatkan API key dan informasi kuota yang akurat (INST-05).
6. Validasi seluruh perjalanan pada instalasi bersih dan upgrade dengan residu. Jangan menutup jalur ini hanya karena binary berhasil dibangun atau endpoint health berhasil merespons.

Setiap implementasi dibahas dan disetujui secara terpisah. Bukti penyelesaian dicatat per butir di dokumen ini; belum ada butir yang dinyatakan selesai.
