# Dust dan notifikasi kontrak — 31 Oktober 2026

Basis: `a0e66997cb51042a877870edf5dadde4335266c1` pada branch validasi. Scope: hilangkan dust produksi pada bangunan selesai, periksa laporan indikator merah setelah expiry/renew, dan dokumentasikan regresi. Tidak mengubah pembayaran, tarif, durasi, produksi, kebutuhan, pergerakan worker, atau schema save.

## Dust

Sebelum perubahan, fixture menampilkan pekerja yang sudah tiba dan order produksi aktif di workshop berfase `built`; [puff terlihat di atas artwork bangunan](evidence/worker-dust-notification-2026-10-31/before-fix-built-production.png). Kode sebelumnya mengizinkan WorkOrder produksi menjadi sumber aktivitas dust.

Sekarang `_has_dust_activity()` hanya menerima aktivitas worker yang eligible dan sudah tiba pada fase `clearing` atau `building`. Jalur worker, WorkOrder, output, dan fungsi cleanup dust tetap sama. [Capture setelah perubahan](evidence/worker-dust-notification-2026-10-31/after-fix-built-production.png) menunjukkan produksi aktif tanpa puff. Kedua gambar berasal dari fixture terkontrol, bukan playtest manusia.

`WorkshopWorkerPresenceTest` **PASS** dengan dust aktif pada clearing/building, tidak sebelum arrival, flag disabled tetap dihormati, dan tidak ada dust pada produksi aktif maupun setelah reload. Worker tetap tersembunyi pada plot produksi dan order tetap aktif; [log rendered](evidence/worker-dust-notification-2026-10-31/after-fix-dust.log). Fixture `WorkerIdleProgressTest` juga **PASS** untuk write/read proses terpisah dan roundtrip: expired menghentikan dust, renew tidak menyalakannya saat perjalanan, dan construction kembali berjalan setelah arrival.

## Diagnosa notifikasi

Pada checkpoint dari perjalanan normal yang sebelumnya berhasil hire, bekerja, expired, renew, tidur dan Continue, warna merah tetap terlihat. Hasil pemeriksaan state: worker sudah dibayar sampai Day 8 dan tidak blocked; daftar event worker kosong. Event yang belum dibaca adalah `visit:4:departed` dari merchant, sedangkan raid tidak aktif. Membuka popup mengakui event dan mengembalikan ikon ke warna normal. Popup menampilkan jadwal merchant berikutnya, bukan kalimat eksplisit bahwa notifikasi berasal dari keberangkatan merchant. [Sebelum membuka](evidence/worker-dust-notification-2026-10-31/normal-renewed-continue-alert.png), [popup](evidence/worker-dust-notification-2026-10-31/normal-renewed-continue-popup.png), [log](evidence/worker-dust-notification-2026-10-31/normal-renewed-continue.log).

Indikator kota merupakan gabungan event belum dibaca dan ancaman raid aktif, bukan status satu kontrak saja. Saat raid menyerang, indikator tetap merah setelah popup dibuka; ini mempertahankan peringatan aktif. [Capture fixture](evidence/worker-dust-notification-2026-10-31/baseline-active-raid-acknowledged.png) dan [log](evidence/worker-dust-notification-2026-10-31/baseline-active-raid.log). `ContractNotificationsTest` juga **PASS** pada branch ini.

## Regresi expiry → renew → Continue

Fixture baru memakai New Game dan scene kota sebenarnya, lalu menyiapkan waktu, dana, dan worker secara terkontrol. Renew dilakukan melalui Worker Hub dan tombol konfirmasi; checkpoint dibuat lewat CitySave lalu dimuat melalui Continue pada proses Godot terpisah. Seluruh sepuluh fase **PASS** tanpa kegagalan:

- **Satu worker:** expiry membuat tanda seru merah; renew membersihkan sumber worker dan mengembalikan warna normal segera, setelah tick, serta setelah Continue. Popup notifikasi tetap tertutup selama pembuktian. [Saat expired](evidence/worker-dust-notification-2026-10-31/notice-single-expired.png), [setelah renew](evidence/worker-dust-notification-2026-10-31/notice-single-renewed.png), [setelah Continue](evidence/worker-dust-notification-2026-10-31/notice-single-continue.png), [log renew](evidence/worker-dust-notification-2026-10-31/notice-single-renew.log).
- **Dua worker:** setelah satu di-renew, worker lain masih expired dan indikator tetap merah, termasuk setelah save dan Continue. Setelah keduanya di-renew, indikator normal dan tetap normal setelah Continue. [Satu diperpanjang](evidence/worker-dust-notification-2026-10-31/notice-multi-one-renewed.png), [Continue parsial](evidence/worker-dust-notification-2026-10-31/notice-multi-partial-continue.png), [Continue kedua worker](evidence/worker-dust-notification-2026-10-31/notice-multi-all-continue.png), [log Continue parsial](evidence/worker-dust-notification-2026-10-31/notice-multi-partial-read.log).
- **Merchant belum dibaca:** setelah renew, sumber worker kosong tetapi kedatangan merchant yang belum dibaca mempertahankan warna merah, termasuk setelah Continue; membuka popup mengubahnya ke warna normal. [Sebelum renew](evidence/worker-dust-notification-2026-10-31/notice-merchant-before-renew.png), [setelah renew](evidence/worker-dust-notification-2026-10-31/notice-merchant-after-renew.png), [setelah dibaca](evidence/worker-dust-notification-2026-10-31/notice-merchant-acknowledged.png), [log Continue](evidence/worker-dust-notification-2026-10-31/notice-merchant-read.log).

Bug refresh worker yang tertinggal tidak terulang pada skenario ini, sehingga logika notifikasi tidak diubah. Checkpoint perjalanan normal menunjukkan satu penyebab yang mungkin, tetapi belum membuktikan bahwa kejadian yang diingat pemilik memiliki penyebab yang sama. Daftar lengkap log setiap fase tersedia di folder bukti.

Untuk mengulang fixture pada display grafis Godot 4.5.1, jalankan `scenes/test_scenes/test_scene_expired_notice_regression.tscn` dengan argumen pengguna `--notice-mode=<mode> --notice-phase=<phase>`. Gunakan profil XDG baru untuk setiap mode, tetapi profil yang sama antar-fase: `single` dan `merchant` berurutan `write → renew → read`; `multi` berurutan `write → renew → partial-read → read`. Fixture `write` menolak checkpoint yang sudah ada.

## Usulan mekanisme payroll berikutnya

Keputusan saat ini adalah kontrak prabayar 3/6/9 hari yang dibayar dari dompet pemain, dengan renew manual; [rancangan terdahulu yang membayar payroll dari kas kota telah digantikan](prepaid-worker-contracts-2026-10-23.md). Perubahan aturan itu atau renew otomatis belum diusulkan sebagai pekerjaan yang sudah disetujui.

Langkah terkecil yang disarankan adalah membuktikan siklus pendanaan payroll: worker menghasilkan barang → pemain mengambil dan menjualnya → pemasukan masuk dompet → hasilnya membiayai renew berikutnya, sebaiknya setidaknya dua siklus. Catat hasil bersih yang benar-benar bisa dijual, fee, kebutuhan, waktu perjalanan dan permintaan merchant; lalu gunakan hasilnya untuk membahas keseimbangan tarif per profesi. [Validasi perjalanan sebelumnya](payroll-flow-validation-2026-10-31.md) sudah membuktikan hire, kerja, expiry dan renew, tetapi penjualan awal berasal dari kayu yang dikumpulkan pemain dan belum membuktikan bahwa hasil worker membiayai renew. Tarif saat ini masih sementara, dan perubahan balance memerlukan keputusan tersendiri.

## Batas

Godot 4.5.1 Linux, viewport logis 400×225; capture rendered menggunakan Compatibility/llvmpipe dan menghasilkan peringatan bahwa driver tidak mendukung perubahan VSync. Skenario fixture dapat mengatur clock, dana dan roster untuk mengisolasi kondisi; bukan seluruhnya perjalanan normal. Windows dan review manusia dalam game belum diuji. Tidak ada keputusan baru untuk mengubah arti unread atau otomatisasi payroll.
