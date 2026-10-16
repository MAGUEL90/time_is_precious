# Food MVP — enam pohon dan rute jalan kaki

Tanggal: 5 Oktober 2026 (Asia/Jakarta). Baseline: `47dcd3a`, branch `feature/item/food-mvp`, working tree awal bersih. Scope LEVEL 2: pengguna menyetujui tahap penempatan enam pohon dan playtest makanan di map sebenarnya. Merge tetap membutuhkan keputusan Game Director.

## Implementasi

ContentScene sekarang memiliki enam pohon kurma. Pohon pertama dan node/layout lain dipertahankan. Lima node memakai script spawner, texture pohon dan scene pickup existing. Dua pohon di pantai memakai offset pickup khusus agar buah tetap di daratan; kapasitas tetap tiga dan refill tetap acak 1–18 jam game. Tidak ada perubahan efek makanan, hunger, fatigue, focus, berat barang, cuaca, atau aturan kerja/tidur.

Posisi berikut relatif terhadap YSortWorld:

| Node | Posisi |
| --- | --- |
| DatePalmTree (existing) | (-440, -496) |
| DatePalmTree2 | (-368, -496) |
| DatePalmTree3 | (-464, -416) |
| DatePalmTree4 | (-392, -416) |
| DatePalmTree5 | (-152, -496) |
| DatePalmTree6 | (-152, -330) |

[Overview enam pohon](food-walking-visuals/six-tree-overview.png) memakai zoom kamera inspeksi 0,65 agar seluruh area terlihat. Ini screenshot renderer scene, bukan mockup; zoom produksi tidak diubah. [Map normal](food-walking-visuals/map.png), [prompt pickup](food-walking-visuals/pickup-focus.png), [debug enam pohon](food-walking-visuals/debug.png), dan [inventory](food-walking-visuals/inventory.png) menggunakan viewport/pengaturan kamera normal.

## Metode

`food_walking_playtest` menguji map produksi selama tepat 4.320 menit, dari D0 10.00 sampai D3 10.00. Pemain mulai dengan inventory kosong dan kebutuhan normal; needs/fatigue guard tetap mati. Driver menggunakan Input movement actions, state machine dan collision pemain, serta interaction E untuk pickup, membuka worksite, dan tidur. Driver tidak menulis posisi pemain. Perpindahan map menggunakan pintu asli dan spawn point produksi.

- Kecepatan pemain tetap 50 px/detik, clock tetap 1 detik = 1 menit game. `--fixed-fps 60` menjalankan langkah waktu tetap secara offline tanpa mengubah rasio gerak/jam. Waktu eksekusi host bukan ukuran pacing manusia.
- Rute memakai koridor terbuka di bawah rumah. Keenam pohon dikunjungi pada setiap putaran, termasuk pohon kosong. Driver tidak membaca countdown tersembunyi untuk memilih jadwal panen.
- Sesudah putaran, pemain mengerjakan satu sesi kayu tiga jam jika pukul 08.00–17.00 dan kuota kerja hari itu belum enam jam. Tidak ada perubahan hasil atau biaya kerja.
- Tidur dicoba malam/pagi (>=19.00 atau <08.00), fatigue >=30%, dan `can_sleep()` mengizinkan. Aturan existing mencatat hari ketika bangun; driver mematuhinya. Dalam ketiga run ada dua tidur tujuh jam, bukan tiga tidur yang dipaksakan.
- Pada waktu lain, pemain menunggu sampai tiga jam melalui clock normal. Work/sleep menggunakan time advancement produksi; driver tidak memanggil advance_minutes untuk perjalanan atau menunggu.
- Makan memakai aksi inventory existing, dengan pemilihan jumlah otomatis setiap hunger >=4% bila stok ada. Waktu berpikir/mengoperasikan UI manusia tidak disimulasikan.
- RNG respawn diberi seed per pohon (`seed + 1009 * index`) sekali per sesi; pulang-pergi rumah tidak mereset RNG/state.
- Hunger maksimum disampel setiap menit, termasuk menit dalam kerja/tidur. Putaran terakhir dan aktivitas panjang dibatasi supaya hasil akhir tepat 72 jam.

Perintah, ulangi TIP_FOOD_SEED dengan 1, 2, 3:

```sh
TIP_FOOD_SEED=1 godot --headless --fixed-fps 60 --path . scenes/test_scenes/food_walking_playtest.tscn
```

Driver mencetak `WALK_MEASURE`, `WALK_RESULT`, dan hasil assertion bernama. Data terstruktur lengkap: [food-walking-playtest-2026-10-05.json](food-walking-playtest-2026-10-05.json).

## Hasil 72 jam

| Seed | Dipanen | Dimakan | Sisa kurma | Kerja kayu | Hasil kayu | Hunger tertinggi | Energi akhir | Fokus akhir |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 123 | 108 | 15 | 18 jam | 35 log | 46,0% | 66,05% | 65,4% |
| 2 | 114 | 108 | 6 | 18 jam | 35 log | 46,4% | 65,65% | 65,2% |
| 3 | 123 | 108 | 15 | 18 jam | 35 log | 46,2% | 66,45% | 65,85% |

Ketiganya: tidak kolaps, hunger akhir sekitar 0%, 17 putaran panen, semua enam pohon terjangkau dan menghasilkan buah, dua kali tidur, semua assertion lulus. Waktu berjalan 586,65–592,63 detik simulasi, setara 9 jam 47 menit–9 jam 53 menit game. Jarak sekitar 29.040–29.324 px. Angka berjalan tidak termasuk animasi pickup, menunggu, kerja, dan tidur.

**Keputusan balance:** pertahankan konfigurasi enam pohon untuk review/playtest manusia. Sampel ini menunjukkan ada waktu untuk bekerja dan tidur, tetapi seed 2 hanya menyisakan enam kurma. Belum ada bukti cukup untuk mengubah hunger, efek kurma, atau interval refill. Dibandingkan laporan teleport, cadangan lebih tipis; perbandingan itu juga berbeda dalam jadwal panen, kerja dan tidur, sehingga selisihnya tidak boleh dianggap akibat perjalanan saja.

## Regresi dan diagnosis

- DatePickupTest, DateRespawnTest, DateTreeDuplicateTest, DatePickupAccessTest, InventoryFeedbackLifecycleTest, dan InventoryModalPauseTest: PASS, exit 0, tanpa script error atau ObjectDB warning.
- DateFoodVisualTest: PASS. Debug keenam pohon dapat digulir dan tombol refill bekerja. Renderer GL Compatibility/llvmpipe menggunakan viewport logis 400×225 dan window 1200×675. Peringatan unsupported V-Sync berasal dari display virtual.
- Fixture duplikasi memakai nama test khusus agar tidak bertabrakan dengan DatePalmTree2 produksi. Fixture survival pembanding mengisolasi jumlah pohon sesuai TIP_FOOD_TREES; satu pohon tetap kolaps D2 12.47, dipanen/dimakan 15, assertions 0 gagal. Run normal verbose tanpa ERROR/WARNING/leaked instance; diagnostik StringName engine pada exit tetap dicatat.
- Percobaan pertama rute jalan kaki terhalang collision kasur karena target test berada di tengah kasur. Target diperbaiki ke sisi depan yang berada dalam jangkauan interaksi; scene kasur tidak diubah. Assertion pintu lanjutan pada run gagal itu merupakan akibat fixture yang sudah dihentikan.
- Percobaan awal rute melewati target 72 jam karena menyelesaikan sesi kerja terakhir; batas aktivitas diperbaiki sebelum tiga pengukuran final. Data run awal tidak dicampurkan ke tabel.
- Mode fixed-fps pada fixture pembanding lama sempat menghasilkan retained coroutine pada return Nightmare: teardown menunggu enam detik wall-clock sehingga game offline sempat menjalankan siklus Nightmare berikutnya. Penantian fixture diganti menjadi enam detik delta simulasi melalui frame, konsisten pada mode normal maupun fixed-step. Mekanik Nightmare produksi tidak diubah.
- Display virtual lama tidak dapat diakses saat awal sesi; display lokal baru dibuat dengan driver yang sudah tersedia. Tidak ada dependency yang dipasang atau setting project yang diubah.

## Batas dan review

Godot yang tersedia adalah 4.6.3/Linux. Godot 4.5.x, Windows, Android, input manusia, sesi lebih dari tiga hari, seed lain, produksi selain kayu, kebutuhan makanan warga, dan disk-save belum divalidasi oleh tahap ini. Uji ini mengukur rute yang sudah diketahui, bukan waktu eksplorasi pertama atau kelalaian pemain. Tidak ada aturan badai baru.

File diubah: ContentScene (lima pohon), dua fixture lama untuk isolasi, README test dan ROADMAP. File baru: fixture walking (.gd/.uid/.tscn), laporan/data dan screenshot di folder dengan .gdignore. Tidak ada file existing dihapus/diganti nama; addon import otomatis dipulihkan. Tidak ada perubahan autoload, addon, project settings atau dokumen kontrol agen.

Verifikasi final: ketiga pengukuran 72 jam menghasilkan `failures: 0`; rerun seed 1 dengan assertion hasil akhir bernama mencetak `FoodWalkingPlaytest: PASS` dan exit 0. Pembanding satu pohon setelah koreksi teardown juga exit 0 tanpa ERROR/WARNING/leaked instance dalam mode fixed-step verbose, dengan hasil gameplay yang sama. `git diff --check` bersih. Status: **PASSED — NEEDS HUMAN REVIEW**.
