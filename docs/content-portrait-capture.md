# Capture portrait: manual vs delegation

## Status branch setelah integrasi — 2026-10-16

Pekerjaan capture tersimpan di branch `content/portrait-capture`, commit
`19d1da9`. Commit merge `11a6d13` mengintegrasikan startup/save `d901018` tanpa
konflik dan tanpa mengubah script, scene, preset, atau tes capture.

Pada branch ini, F5 membuka start menu dengan Continue / New Game / Quit.
Untuk capture, buka `scenes/content_scene/capture/portrait_capture.tscn` dan F6.
Preset lokal tetap memakai preview 360×640 dan hasil PNG 1080×1920.

Verifikasi Windows/Godot 4.5.1 setelah integrasi mencakup capture headless dan
grafis, PNG, hiring/hauling, New Game, save rusak, serta Continue kota/rumah.
Rincian hasil terbaru ada di bagian awal laporan QA. Bagian berikut menyimpan
riwayat pemasangan dan pengujian sebelumnya; nama branch/baseline di bagian
riwayat bukan status checkout saat ini.

## Riwayat pemasangan lokal Hendro

Capture sudah dipasang langsung di
`C:\Users\Hendro\OneDrive\Documents\Project\Github\time_is_precious` pada branch
`fix/gameplay-hud/ui-consistency`, HEAD `696da34972444189317e2605fc9472d11de46485`.
Buka project lokal tersebut, pilih `scenes/content_scene/capture/portrait_capture.tscn`,
lalu F6. Tidak perlu mengekstrak ZIP atau mengganti branch lagi.
Tes capture headless dan grafis lulus pada Godot 4.5.1. PNG 1080x1920 juga diuji;
restart melalui tombol R masih perlu dicoba langsung. Preview lokal memakai
`preview_scale=1` (360x640) agar muat di layar; PNG tetap 1080x1920.
Semua teks capture memakai `assets/font/pixel_rpg.ttf`, ukuran logis 6, termasuk
menu dinamis dan popup. Label dunia mengimbangi zoom kamera sehingga ukurannya
konsisten dengan HUD dan label muatan/stockpile tidak bertumpuk.
Rumah `YSortWorld/HomeDoor` beserta label Home / Sleep disembunyikan dan trigger
masuknya dinonaktifkan hanya di capture. F4 tetap memakai sleep pemain asli;
map, theme dan rumah gameplay utama tidak diubah.
Instruksi salinan/branch terpisah di bawah mencatat workflow paket asal.

Setup ini disiapkan di branch `feature/content-scene/portrait-capture`, dari
`fix/gameplay-hud/ui-consistency` commit `d901018f0fca495d4ca70e671cfde0e4defb01e2`.
Ini setup pengambilan footage sekitar 30 detik, bukan video final atau overlay promosi.
Perubahan hanya tersedia di salinan kerja ini sampai dipindahkan ke komputer pengguna.
Revisi fokus satu worksite menampilkan Clay Site dan stockpile Clay pada framing yang sama.

## Membuka dan mengulang take

1. Buka proyek pada salinan/branch kerja terpisah dari commit dasar tersebut.
2. Buka `scenes/content_scene/capture/portrait_capture.tscn`, lalu **F6** untuk
   menjalankan scene itu secara langsung. F5 tetap membuka start menu game biasa.
3. Tunggu pesan `Portrait capture ready` di Output. Mulai dari `Day 0 14:00 HOLD`.
4. Untuk take ulang, tekan **R** di jendela game. Proses baru memulai preset yang sama;
   jangan mengulang dengan me-reload map di dalam sesi gameplay yang sedang berjalan.
   Bila restart tidak didukung editor tertanam/OS, hentikan sesi lalu F6 lagi.

Alternatif terminal, dari direktori proyek:

```sh
godot --path . --scene res://scenes/content_scene/capture/portrait_capture.tscn
```

Gunakan jendela game terpisah jika preview editor tertanam membatasi ukuran portrait.
Viewport lokal 360×640, preview 720×1280; ubah `preview_scale` ke 1 di resource preset
untuk layar laptop pendek. Resolusi game biasa tetap 400×225 / 1200×675.
Sumber gameplay selalu `content_scene.tscn` yang sama, tanpa salinan map/asset.

Preset awal memakai `focus_site_only = true`: empat worksite lain, empat stockpile
lain, serta ikon/label City Storage disembunyikan hanya dalam proses capture.
Clay Site, stockpile Clay, worker, ground output dan jalur hauling tetap terlihat.
Semua lima session worksite, endpoint delivery dan collision shape tetap terdaftar;
filter ini mengatur tampilan, bukan menghapus node atau menonaktifkan gameplay.
Hanya Daily plan Clay yang dijadwalkan dalam take contoh. Workshop dan rumah tetap
menjadi konteks kota; zoom kamera tetap 2.0. Ubah `focus_site_only` ke false jika
konten berikutnya membutuhkan seluruh worksite. Scene ContentScene biasa tidak
menerapkan filter ini. Interaksi native tetap tersedia pada node yang tersembunyi,
jadi gunakan area pengambilan di Clay dan arah workshop untuk take ini.

## Kontrol operator

| Tombol | Fungsi |
| --- | --- |
| E | Interaksi gameplay biasa; pemain mulai dalam jangkauan Clay Site. |
| I | Inventory asli; gunakan untuk memperlihatkan hasil manual. |
| WASD | Gerak pemain asli. |
| Space | HOLD / jalankan clock. HOLD tidak membekukan animasi atau gerak pemain. |
| F5 **di jendela game** | Berganti x1 / x10 melalui TimeDebugOverlay asli. |
| 1 | Kamera tetap yang memuat Clay Site, stockpile Clay, dan arah workshop. |
| 2 | Kamera mengikuti pemain; pakai 1 lagi untuk memperlihatkan kedua worker. |
| F4 | Persiapan antar-shot setelah Daily plan committed dan semua menu ditutup. |
| F8 | Simpan seluruh frame PNG 1080×1920, nearest-neighbor, ke folder sesi capture. |
| R | Take baru melalui proses baru, bukan reset sebagian autoload. |

Shortcut operator tidak mengambil input ketika kolom teks/jumlah sedang fokus.
Tetap di map konten selama take ini. Perjalanan ke home/nightmare serta
reload checkpoint capture bukan bagian dari preset yang diverifikasi.

## Rencana shot sekitar 30 detik

Durasi berikut adalah durasi **hasil edit**, bukan waktu gameplay yang dipaksakan.
Rekam potongan sedikit lebih panjang untuk memberi ruang potong.

| Hasil edit | Pengambilan |
| --- | --- |
| 0–3 dtk | Kamera 1, pemain di Clay Site, penanda `Day 0 14:00 HOLD` terlihat. |
| 3–9 dtk | E → Hourly → 3 h → Next → Start Work. Pertahankan fade asli. Tampilkan perubahan 14:00 → 17:00 dan hasil di Inventory (I). |
| 9–15 dtk | Tutup Inventory. E → Daily. Slot pertama pilih Workshop Laborer; slot kedua Worksite Hauler. Pilih storage **Clay**, target 20, Assign → Next → Start Work. |
| Potongan antar-shot | Semua menu ditutup, tekan F4. Rekam/pertahankan bukti pergantian ke **Day 1 06:45**, atau beri keterangan “hari berikutnya” dalam edit. |
| 15–25 dtk | F5 ke x10, Space menjalankan clock. Shift asli mulai 07:00; hasil pertama sekitar 07:30. Tampilkan laborer bekerja dan hauler membawa cart. Gerakkan pemain ke atas menuju area workshop; kamera 1 tetap memperlihatkan worker. |
| 25–30 dtk | Ambil frame penutup dengan hasil stockpile atau E → Worker Progress. Sisakan ruang bagi caption penutup dalam editor video. |

Manual work pada branch ini adalah transaksi dengan fade/time skip; jangan
menyajikannya sebagai animasi menggali kontinu selama tiga jam. Hauler mengangkut,
laborer menghasilkan bahan. Angka hasil/upah mengikuti implementasi asli; ini
perbandingan alur dan waktu pemain, bukan klaim kedua cara memiliki output setara.

## Apa yang disiapkan preset

`manual_vs_delegation.tres` mengatur site, filter satu worksite, jam awal, fatigue awal,
persediaan, framing, zoom, skala preview, speed clock dan seed. Untuk konten berikutnya,
buat/ubah **resource preset** dan pasang ke properti `preset` pada scene capture
yang sama. Tidak perlu membuat satu scene/map baru untuk tiap video.

Fixture merekrut dua applicant awal melalui `WorkerDatabase.hire_applicant`,
memasang satu cart kota asli melalui API equipment, memberi pemain 20 shekel dan
4 roasted drumstick, serta menyiapkan supply kota untuk penduduk awal. Ini kondisi
awal take; tidak menggambarkan pemain mendapat worker/cart gratis lewat gameplay.
Worker masih harus ditugaskan lewat UI asli. Stock site, output, kapasitas cart,
upah, shift, aturan assignment dan kebutuhan pemain tidak diubah.

F4 memakai sleep tujuh jam asli dengan fade, memakai tiga makanan fisik setelah
bangun melalui transaksi Inventory, lalu menunggu menit demi menit hingga 06:45.
Pergantian hari, kebutuhan kota dan upah tetap berjalan. F4 tidak mematikan collapse
guard dan menolak persiapan yang tidak dapat memenuhi syarat sleep/jadwal asli.
Periksa Output jika ditolak, lalu ulangi take dengan R. Preset jam/supply lain perlu
diverifikasi lagi; fixture ini belum menjadi editor skenario umum.

## Save dan hasil capture

Scene ini hanya bisa dimulai dalam proses debug yang fresh. Ia tidak membuka start
menu atau membaca checkpoint gameplay. Sesudah map terikat, `CitySave.disk.path`
diarahkan ke `user://content_capture/session-<timestamp>-<ticks>/checkpoint_v1.json`.
Save native berikutnya memakai slot itu; primary, backup dan kandidat recovery
`user://city_save/checkpoint_v1.json` tidak dipindahkan atau ditimpa. F4 sendiri
tidak menulis checkpoint; F8 menulis PNG. Lokasi absolut dicetak di Output.

Hentikan proses capture sebelum menjalankan game biasa. Folder sesi lama sengaja
disimpan; penghapusan/arsipnya keputusan pengguna. Jangan menggunakan scene capture
sebagai main scene proyek atau melanjutkan save capture melalui start menu biasa.

## Batas dan verifikasi

Lihat `docs/task_reports/2026-10-11-portrait-capture.md` untuk hasil pengujian dan
daftar perubahan. Screenshot berasal dari renderer grafis, bukan mockup.
Verifikasi memakai Godot 4.6.3 GL Compatibility di Linux; proyek menargetkan 4.5.x.
Uji ulang di Godot 4.5.x dan review di perangkat/layar pengguna masih diperlukan.
Seed membantu mengulang kondisi awal; input, timing animasi dan pengambilan frame
tidak dijamin identik per piksel. Audio, rekaman/encoding video, platform mobile,
dan fitur roadmap di luar commit dasar tidak diuji atau diselesaikan oleh setup ini.
