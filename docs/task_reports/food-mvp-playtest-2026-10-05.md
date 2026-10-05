# Food MVP playtest — 5 Oktober 2026

**Kesimpulan: mekanisme pickup/respawn lulus skenario yang diuji, tetapi satu pohon kurma belum cukup sebagai satu-satunya sumber makanan.** Tidak ada perubahan balancing pada pekerjaan ini.

Baseline gameplay: `d727b2236c452a0bc1ad8cd1059d527ad423a0be`, branch `feature/item/food-mvp`, working tree awal bersih. Scope LEVEL 1: fixture pengujian dan laporan; gameplay, aset, scene produksi dan pengaturan tidak diubah. Godot yang tersedia: 4.6.3, headless.

## Metode

Tiga run memakai seed respawn 1, 2, 3 untuk hasil yang bisa diulang. Kondisi awal asli: hari 0 pukul 10.00, energi 50%, hunger 0%, inventory kosong. Satu pohon, tiga pickup maksimum, satu item per pickup, jeda acak 1–18 jam. Tidak ada debug refill, makanan tambahan, atau perlindungan hunger/fatigue.

Target run adalah 72 jam, dihentikan saat kolaps pertama. Pemain memeriksa pohon setiap jam saat terjaga, mengambil semua buah tersedia, dan makan ketika hunger minimal 4%. Pemain tidur tujuh jam mulai pukul 16.00 setiap hari menggunakan HomeDoor, SleepSpot dan ExitDoor sebenarnya. Timer diperiksa saat masuk rumah, setelah tidur, dan setelah kembali. Perjalanan diteleport; pengambilan dan makan dipanggil lewat metode gameplay, bukan klik manual. Jam dimajukan deterministik. Run ini tidak melakukan pekerjaan produksi, jadi bukan playtest lengkap mencari uang atau pengukuran navigasi pemain. Kunjungan per jam dan perjalanan tanpa biaya merupakan kondisi yang menguntungkan pencarian makanan.

## Hasil kebutuhan hidup

Hari 0 adalah hari pertama menurut penomoran game.

| Run | Jeda respawn yang terundi (jam) | Kurma diambil/dimakan | Hunger pertama 100% | Kolaps pertama | Waktu berlalu | Energi saat kolaps |
| --- | --- | ---: | --- | --- | --- | ---: |
| Seed 1 | 16, 1, 14, 5, 10 | 15/15 | D1 08.40 | D2 12.47 | 50 jam 47 menit | 24,2% |
| Seed 2 | 11, 4, 13, 3, 8, 17 | 18/18 | D1 08.40 | D2 15.16 | 53 jam 16 menit | 25,6% |
| Seed 3 | 13, 1, 4, 16, 18 | 15/15 | D1 10.40 | D2 13.53 | 51 jam 53 menit | 20,9% |

Ketiganya kolaps ketika fokus mencapai sekitar 10%; energi masih di atas ambang kritis. Tidak ada run yang mencapai target 72 jam. Seluruh assertion kontinuitas scene dan timer lulus (`failures: 0`). Ini kegagalan kecukupan pasokan dalam skenario, bukan kegagalan assertion implementasi.

Pada ketiga run, sebelum tidur pertama hunger 24% dan energi 35%; setelah tidur hunger 66% dan energi 88,3%. Saat tidur kedua, hunger 88–100% menyebabkan pemulihan energi jauh lebih kecil. Seed 1: energi 43,3% → 59,55%; seed 2: 46,3% → 68,4%; seed 3: 46,3% → 62,55%.

Data pengukuran lengkap: `food-mvp-playtest-2026-10-05.json`.

## Mengapa makanan kurang

Nilai existing: hunger bertambah 0,001 per menit (= 6 poin persentase per jam, 144 per 24 jam sebelum cap). Satu kurma mengurangi 0,04 (= 4 poin), setara sekitar 40 menit kebutuhan. Tiga kurma satu siklus hanya menutup sekitar dua jam kebutuhan.

Secara teoritis, jika semua pickup langsung diambil setelah respawn, rata-rata jeda uniform 1–18 jam adalah 9,5 jam. Satu pohon menghasilkan sekitar `3 × 24 / 9,5 = 7,58` item per hari dalam jangka panjang, menutup sekitar 30,3 poin hunger/hari, atau 21% kebutuhan 144 poin. Ini estimasi rata-rata ideal, bukan jaminan harian; tidur dan terlambat mengunjungi pohon bisa menurunkannya. Stok awal tiga item bukan pendapatan berulang.

## Pemeriksaan mekanisme

- DateRespawnTest: PASS — batas tiga, waktu acak 1–18 jam, 100 siklus, timer tidak direset oleh pickup berikutnya, snapshot jam tidak menghitung menit, hanya isi slot kosong, buah lama tetap, timer/stok bertahan saat map tidak dimuat, timer per pohon independen.
- DatePickupTest: PASS — inventory penuh menolak pickup, tidak ada pengambilan ganda, konsumsi satu item, efek hunger existing, world sprite terpisah dari ikon inventory dan fallback item lama.
- DatePickupAccessTest: PASS — proximity fisik memilih ketiga pickup, dispatcher E menambah inventory, gerakan pulih setelah animasi. Spawn masih terjadi ketika waktu refill jatuh pada cuaca storm; ini perilaku saat ini, belum ada aturan cuaca yang diterapkan.
- Debug: PASS — melihat panel tidak mengubah timer/stok, refill hanya mengisi pickup tanah tanpa memberi item inventory, timer dibersihkan, pemanggilan berulang tidak melewati batas.
- Door/sleep di tiga run: PASS — pintu asli berfungsi, tidur tujuh jam mengurangi timer 420 menit atau menyelesaikannya, kembali ke map menampilkan stok yang benar.
- MerchantMainMapLoopTest: PASS — enam jam kerja menghasilkan tujuh wood, tidur dan perjalanan rumah tetap berfungsi, penjualan enam wood menghasilkan 12 Shekel, pembelian/buyback dan quota tetap konsisten. Fixture ini tidak memakan kurma dan tidak membuktikan keseimbangan makanan selama kerja.
- Editor import: tidak ada script/parse error. Diff whitespace diperiksa sebelum commit.

## Batas dan peringatan

Tes headless, bukan pemeriksaan visual atau input manual Windows. Godot 4.5.x dan Android belum diuji. Tidak mengklaim disk-save persistence. Tiga seed adalah contoh terukur, bukan distribusi statistik lengkap.

DatePickupTest, DateRespawnTest dan run survival masih mengeluarkan warning ObjectDB saat shutdown; warning pada dua fixture awal sudah ada sebelum pekerjaan ini. Access test dan merchant loop selesai tanpa warning tersebut. Sumber shutdown belum diselesaikan; tidak ditutupi sebagai QA bersih sepenuhnya. Salah satu run awal bertabrakan dengan port debug 9877 karena proses paralel; seed 2 dijalankan ulang secara terpisah, hasil gameplay sama dan error port tidak muncul. Laporan memakai run ulang.

## Rekomendasi

Pertahankan aturan waktu acak dan batas pickup yang sudah disepakati. Keputusan berikutnya: menambah jumlah pohon atau isi item per pickup, lalu ulangi playtest. Patokan kasarnya perlu sekitar 4,75 kali pasokan rata-rata sekarang untuk menutup hunger penuh, sebelum buffer untuk jeda buruk dan waktu perjalanan. Ini perkiraan untuk diskusi balancing, bukan nilai yang otomatis diterapkan.

Tunda penalti produksi saat badai sampai pasokan dasar dan cadangan makanan cukup. Perbaiki warning shutdown sebelum menyatakan QA branch sepenuhnya bersih. Human review tetap diperlukan; tidak melakukan merge.
