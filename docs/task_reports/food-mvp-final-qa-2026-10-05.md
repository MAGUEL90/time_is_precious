# Food MVP — pemeriksaan akhir, 5 Oktober 2026

Baseline awal pekerjaan: `a4f5193`, branch `feature/item/food-mvp`, working tree awal bersih. Scope: LEVEL 2, keamanan duplikasi pohon, debug/visual QA, perbaikan lifecycle feedback inventory dan teardown test, serta uji pasokan dengan beberapa pohon. Tidak ada perubahan hunger, efek makanan, interval respawn, isi pickup, cuaca, atau jumlah pohon di map produksi.

## Perubahan pohon berulang

Identitas pohon dibuat otomatis dari path scene dan path node. Duplikasi node DatePalmTree di editor memberi stok dan timer independen; tidak perlu mengetik tree_id. Identitas tetap sama saat map dimuat ulang. Pertahankan nama/path node selama sesi berjalan; mengubah struktur scene pada saat game berjalan bukan migrasi state yang didukung. Ini tetap state sesi, bukan disk-save.

Setiap slot memakai scene pickup existing. Penempatan memakai transform pohon; menghapus view pohon juga membersihkan view pickup miliknya. Debug menampilkan path node yang bisa dibaca, bukan hash identitas. max_pickups dan pickup_positions tetap bisa diatur di Inspector; sediakan posisi minimal sebanyak kapasitas dan restart sesi setelah mengubah konfigurasi.

DateTreeDuplicateTest lulus: duplikasi tanpa ID manual, pengambilan dari satu pohon tidak memengaruhi pohon lain, masing-masing timer dan slot kosong bertahan saat map dibuat ulang, serta pickup view dibersihkan ketika pohon dihapus.

## Pemeriksaan visual

Godot 4.6.3, GL Compatibility/llvmpipe, Xorg dummy display. Pengaturan project tetap: viewport logis 400×225, window pengembangan 1200×675. Screenshot viewport disimpan pada resolusi logis, bukan gambar mockup.

- Map: pohon dan buah terlihat, posisi mengikuti layout yang dibuat Game Director.
- Pickup: prompt E muncul saat pendekatan fisik; interaksi dan animasi mengambil berjalan.
- Inventory: ikon Date Cluster existing tampil setelah pengambilan.
- Debug: bagian DATE PICKUPS dapat digulir ke dalam panel; stok, countdown dan tombol refill terlihat. Panel berada di dalam viewport dan tombol dapat dipakai.

DateFoodVisualTest lulus. Screenshot diperiksa langsung:

- [Map](food-mvp-final-visuals/map.png)
- [Prompt pickup](food-mvp-final-visuals/pickup-focus.png)
- [Debug kurma](food-mvp-final-visuals/debug.png)
- [Inventory](food-mvp-final-visuals/inventory.png)

Percobaan grafis awal gagal pada assertion karena fixture menggulir sebelum layout selesai; fixture diperbaiki untuk menunggu layout. Rerun berikutnya mengungkap assertion stok yang terlalu cepat terhadap deferred refresh; fixture kini menunggu dua frame sebelum memeriksa hasil refill. Run final hanya menghasilkan peringatan V-Sync yang tidak didukung display virtual, tanpa script error. Audio memakai driver Dummy pada test karena environment tidak memiliki perangkat audio. Pengaturan project tidak diubah.

## Penyelesaian warning lifecycle dan test

Diagnosis verbose membedakan timer/coroutine pada teardown dari hasil pengujian gameplay:

- InventoryUI mengganti coroutine SceneTreeTimer untuk feedback dengan tween yang terikat pada node UI. Pesan baru membatalkan timer sebelumnya, clear membatalkannya, dan penghapusan scene otomatis menghentikannya. Durasi tiga detik dan perilaku saat inventory mem-pause game tetap sama. InventoryFeedbackLifecycleTest memverifikasi ketiga jalur tersebut serta expiry saat pause.
- DatePickupTest kini menunggu feedback inventory selesai, dengan batas lima detik, sebelum membebaskan scene dan keluar.
- DateRespawnTest dan DatePickupAccessTest memakai perlindungan kebutuhan pemain khusus fixture agar loncatan waktu untuk menguji timer tidak memulai kolaps yang tidak terkait. Test survival tetap menggunakan kebutuhan pemain aktif.
- FoodSurvivalPlaytest menunggu feedback/animasi/transisi selesai melalui frame, membebaskan current_scene, mengosongkan antrean penghapusan, lalu keluar secara deferred.

Run awal beberapa pohon mengungkap timer feedback yang tertinggal setelah perpindahan scene cepat; itulah alasan perbaikan produksi InventoryUI di atas. Tidak ada peringatan yang disembunyikan dan tidak ada kode produksi hunger/kolaps yang diubah. Fixture pickup/respawn sudah lulus tanpa ObjectDB/leaked-instance warning. Fixture akses juga membebaskan scene sebelum deferred quit; diagnosis verbose sebelumnya menunjukkan play_faint yang dipicu loncatan waktu, sehingga kebutuhan pemain diisolasi khusus fixture itu. Run survival kontrol satu pohon setelah perbaikan juga bersih; hasilnya tetap kolaps D2 12.47. Run final 5 pohon/seed 3 juga selesai 72 jam, memperoleh 120 kurma dan memakan 106, tanpa ERROR, WARNING, atau Leaked instance. Output verbose engine masih mencatat diagnostik StringName pada exit; tidak diklaim sebagai audit kebocoran memori engine menyeluruh.

## Perbandingan pasokan, 72 jam

Tiga seed (1, 2, 3) untuk masing-masing 5 dan 6 pohon. Pohon tambahan hanya dibuat oleh fixture, tidak disimpan ke ContentScene. Setiap pohon tetap maksimal tiga pickup, satu kurma per pickup, refill acak 1–18 jam. RNG tiap pohon memakai seed berbeda dan tidak direset saat masuk rumah.

Pemain mulai dengan inventory kosong dan kebutuhan normal. Pohon dikunjungi setiap jam saat terjaga; semua kurma yang tersedia diambil; makan dilakukan ketika hunger minimal 4%; tidur tujuh jam mulai pukul 16.00 memakai pintu rumah dan SleepSpot asli. Perjalanan diteleport dan tidak ada kerja produksi pada run survival. Ini skenario pencarian makanan yang menguntungkan, bukan bukti pacing navigasi atau keseimbangan ekonomi penuh.

| Pohon | Seed | Kurma diperoleh | Dimakan | Sisa inventory | Hunger akhir | Energi akhir | Fokus akhir | Hasil |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 5 | 1 | 135 | 106 | 29 | 8% | 82% | 83,5% | Bertahan 72 jam |
| 5 | 2 | 123 | 106 | 17 | 8% | 82% | 83,5% | Bertahan 72 jam |
| 5 | 3 | 120 | 106 | 14 | 8% | 82% | 83,5% | Bertahan 72 jam |
| 6 | 1 | 150 | 106 | 44 | 8% | 82% | 83,5% | Bertahan 72 jam |
| 6 | 2 | 147 | 106 | 41 | 8% | 82% | 83,5% | Bertahan 72 jam |
| 6 | 3 | 138 | 106 | 32 | 8% | 82% | 83,5% | Bertahan 72 jam |

Tidak ada run 5/6 pohon yang mencapai hunger 100% atau kolaps. Semua assertion kontinuitas timer/scene lulus. Kontrol satu pohon/seed 1 tetap mendapatkan 15 kurma dan kolaps setelah 50 jam 47 menit. Data lengkap: `food-mvp-final-balance-2026-10-05.json`.

Data enam perbandingan diambil sebelum koreksi teardown terakhir; warning penutupan pada run tersebut tidak dihapus dari sejarah. Koreksi berikutnya tidak mengubah mekanik atau angka gameplay; run representatif diulang untuk membuktikan hasil tetap dan teardown bersih.

**Rekomendasi:** 5 pohon adalah titik awal yang lulus tiga contoh ini; 6 pohon memberi cadangan lebih besar (32–44 kurma pada akhir run) untuk playtest manual berikutnya. Belum ada jaminan untuk semua seed, sesi panjang, waktu perjalanan, kerja, atau cuaca ekstrem. Map produksi masih satu pohon sesuai penempatan pengguna; penambahan dan letaknya tetap keputusan Game Director.

## Batas

Pemeriksaan grafis dilakukan di Linux virtual, bukan komputer Windows pengguna. Godot 4.5.x dan Android belum tersedia untuk divalidasi. Tidak ada klaim disk-save atau aturan badai. Merge tetap dilakukan oleh Game Director.

## Reproduksi dan hasil akhir

Jalankan dari root repo menggunakan Godot 4.6.3:

```sh
godot --headless --path . scenes/test_scenes/date_pickup_test.tscn
godot --headless --path . scenes/test_scenes/date_respawn_test.tscn
godot --headless --path . scenes/test_scenes/date_tree_duplicate_test.tscn
godot --headless --verbose --path . scenes/test_scenes/date_pickup_access_test.tscn
godot --headless --path . scenes/test_scenes/inventory_feedback_lifecycle_test.tscn
godot --headless --path . scenes/test_scenes/test_scene_inventory_modal_pause.tscn
TIP_FOOD_TREES=5 TIP_FOOD_SEED=3 godot --headless --verbose --path . scenes/test_scenes/food_survival_playtest.tscn
TIP_FOOD_TREES=1 TIP_FOOD_SEED=1 godot --headless --verbose --path . scenes/test_scenes/food_survival_playtest.tscn
```

Untuk visual, sediakan folder capture dan display grafis:

```sh
TIP_FOOD_CAPTURE_DIR=/tmp/food-visual godot --audio-driver Dummy --path . scenes/test_scenes/date_food_visual_test.tscn
```

Tambahan/ubah file pada tahap ini: spawner pohon, label debug, lifecycle feedback InventoryUI; fixture pickup/respawn/akses/survival dan fixture baru duplikasi/visual/lifecycle (termasuk scene dan UID); laporan QA/data pasokan/screenshot serta tautan pada dua laporan sebelumnya. Tidak ada file dihapus atau diganti nama. Import addon yang otomatis berubah karena editor dipulihkan; project settings, addon, kontrol agen, balance, dan ContentScene tidak diubah pada tahap ini. Perubahan project.godot yang sudah ada pada branch berasal dari commit aset pengguna, bukan tahap QA ini.

Hasil final: enam fixture headless di atas **PASS**, exit 0, tanpa ERROR/WARNING/ObjectDB leaked-instance warning. Dua survival representatif **PASS** (kontrol memang diharapkan kolaps), hasil tetap sama, tanpa warning instance. Uji grafis final **PASS**, exit 0, dengan peringatan V-Sync display virtual yang dijelaskan di atas. `git diff --check` bersih. Status: **PASSED — NEEDS HUMAN REVIEW**.
