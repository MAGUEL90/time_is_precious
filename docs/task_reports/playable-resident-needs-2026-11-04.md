# Pemulihan kebutuhan warga tanpa debug — 2026-11-04

> Tindak lanjut: `needs-recovery-grind-2026-11-04.md` mencatat perubahan
> permintaan merchant dan nilai Date Cluster setelah pengukuran awal ini.
> Hasil dan angka di bawah adalah bukti historis sebelum tindak lanjut tersebut.

## Cakupan dan keputusan

- Baseline: `13a6c0725a08c91bfcbc2606646e8ebf0f668968`, branch terisolasi
  `feature/gameplay/playable-needs-recovery-20261104`; perubahan ini masih perlu
  integrasi dan penilaian manusia.
- `Simple Clothes` ditawarkan merchant umum sebanyak **2 unit per kunjungan**,
  seharga **2 Shekel per unit**. Ini angka playtest sementara: dua unit mencukupi
  dua warga awal, merchant datang tiap tiga hari, dan harga mengikuti harga
  beli barang sederhana lain yang bernilai dasar 1. Tidak ada perubahan pada
  uang awal, jadwal, permintaan acak, harga lain, payroll, threshold 50%, aturan
  +5/-5, atau masa pakai pakaian tujuh hari.
- Pembelian menghasilkan barang fisik di Inventory; pemain harus menyetorkannya
  ke City Storage. Settlement tengah malam tetap membagikan satu pakaian per
  orang, mengonsumsi makanan dan mengevaluasi shelter seperti semula.
- New Game memiliki dua warga pada 50%, belum punya uang atau shelter, sedangkan
  merchant pertama datang hari 1. Tanpa kebutuhan lengkap keduanya turun ke 45%
  pada tengah malam dan tidak lagi terlihat sebagai applicant. Rumah yang sudah
  ada dapat dibersihkan dan dibangun langsung oleh pemain tanpa pekerja: 180
  menit pembersihan, lalu 2.880 menit kerja; biayanya 4 Wood Log, 8 Clay Lump,
  6 Reed Bundle dari Inventory, dan hasilnya 3 kapasitas shelter. Ini jalur
  pemulihan yang sudah ada, bukan perubahan aturan perekrutan.
- Checkpoint lama menyimpan katalog dan stok merchant. Bila katalog lama belum
  berisi pakaian, item baru ditambahkan saat kedatangan merchant **berikutnya**,
  bukan saat Continue di tengah kunjungan. Stok, harga, permintaan, dan uang dari
  kunjungan yang tersimpan tidak diisi ulang. Format save tidak berubah.

## Bukti pada Godot 4.5.2 headless

| Pengujian | Hasil |
| --- | --- |
| New Game, merchant acak alami, kebutuhan pemain aktif | PASS pada sampel perjalanan: dua warga kembali ke 50% pada hari 6, 17 sesi rumah, 4 pakaian dibeli, 14 Shekel dari kayu. |
| Job Board nyata | PASS: dua applicant awal terlihat; setelah kebutuhan tidak terpenuhi tampilan kosong; setelah pulih keduanya terlihat lagi. |
| Merchant terlambat, seed 2 | PASS sebagai sampel deterministik: hari 1 dan 4 hanya meminta bata, hari 7 meminta kayu; kedua warga kembali ke 50% pada hari 14. |
| Penundaan sampai 0%, seed 937 | PASS sebagai sampel deterministik: empat kunjungan pertama hanya meminta bata, kayu baru diminta hari 13; minimum satisfaction tercatat 0% dan kedua warga mencapai 50% lagi pada hari 23. |
| Sleep / Continue | PASS pada perjalanan acak, seed 2 dan seed 937: checkpoint tidur yang diperoleh selama perjalanan dipulihkan sama persis di proses baru; rumah, shelter, alokasi pakaian, dan satisfaction tetap ada. |
| Save lama | PASS: checkpoint kunjungan yang sudah membeli tanah liat dibuat pada baseline `13a6c07` dalam proses terpisah, lalu dibuka pada branch ini; saldo, stok, dan permintaan bertahan. Pakaian muncul pada kunjungan berikutnya, pembelian serta save/reload ulang tidak menambah stok, dan kunjungan setelahnya mengisi ulang sekali. |
| Regresi | PASS: TravelingMerchant, MerchantRandomRequests, TravelingMerchantAccess, CityFoodDaily, CityClothingNeeds, PopulationEmploymentIntegration, CityResident, CitizenHousePlayer, HousePlayerSave, CitySaveEconomy, dan DebugResidentNeeds. Fixture debug terakhir adalah regresi tersendiri, bukan bagian dari perjalanan tanpa debug. |

Driver perjalanan memakai menu New Game, pickup kurma, worksite, UI merchant,
UI rumah, UI Job Board, kebutuhan pemain yang aktif, dan jalur tidur/checkpoint
yang ada. Deposit makanan/pakaian memakai API City Storage yang sama dengan UI.
Driver **memindahkan pemain ke jarak interaksi** dan memajukan menit menganggur
melalui clock yang sesungguhnya; tidak ada item/uang/shelter gratis, perubahan
aturan kebutuhan, atau perlindungan debug. Waktu berjalan, navigasi, penglihatan,
dan kemudahan menemukan tindakan belum teruji oleh manusia. Seed 2 dan 937 hanya
memilih urutan permintaan yang sah untuk menguji keterlambatan, bukan hasil acak
yang dijamin oleh permainan.

## Batas penting integrasi dan risiko

Instruksi terbaru Game Director menetapkan hasil worksite masuk City Storage,
kapasitas kota besar sementara, material bangunan berasal dari pemain, dan
hauler saat ini mengirim antar-storage. Tim logistik mengerjakan perubahan itu
secara terpisah. Pengujian perjalanan di atas berjalan pada baseline sebelum
integrasi tersebut dan **belum membuktikan kontrak logistik baru**. Driver dapat
mengambil material dari City Storage ke Inventory melalui API penarikan bila
barang telah berada di sana. Setelah integrasi, jalankan ulang tes standar;
pemeriksaan bawaannya mensyaratkan hasil worksite masuk City Storage
dan tidak langsung masuk tas pemain. Bangunan tetap harus mengonsumsi material
yang sudah dibawa pemain. Pemeriksaan gabungan tim worker/logistik tetap wajib.
Pada baseline branch ini pemeriksaan tersebut **FAIL seperti yang diperkirakan**: hasil
kerja manual masuk Inventory pemain. Ini adalah hasil merah untuk tim integrasi,
bukan validasi bahwa instruksi terbaru sudah dilaksanakan.

Permintaan merchant tetap acak dan dapat tidak memilih kayu pada sejumlah
kunjungan; belum ada batas atas penantian atau jaminan pemasukan. Jalur pemulihan
karena itu masih berisiko lambat dan repetitif. Sampel seed 2 mengumpulkan 558
kurma sebelum kedua warga pulih; sampel seed 937 mengumpulkan 893 kurma sampai
pulih pada hari 23. Karena posisi karakter dipercepat, angka-angka ini bukan
ukuran waktu atau kenyamanan bermain manusia. Jumlah pakaian per kunjungan
juga bukan bukti keseimbangan untuk kota yang populasinya terus bertambah.
Jangan menyebut seluruh loop baru selesai sampai diuji pada branch terintegrasi
dan ditinjau dalam permainan biasa.

## Menjalankan tes

Gunakan `XDG_DATA_HOME` baru dan kosong untuk setiap perjalanan, dengan cache dan
konfigurasi Godot di lokasi sementara. Contoh perintah dalam checkout branch:

```sh
godot --headless --path . --fixed-fps 60 res://scenes/test_scenes/test_scene_playable_needs_journey.tscn -- --journey-phase=write
godot --headless --path . --fixed-fps 60 res://scenes/test_scenes/test_scene_playable_needs_journey.tscn -- --journey-phase=read
```

Kedua proses memakai `XDG_DATA_HOME` yang sama agar proses kedua membaca save
pertama. Tes standar ditujukan untuk branch terintegrasi dan mewajibkan hasil
worksite masuk City Storage. Hanya untuk mengulangi pengujian baseline lama pada
branch ini, tambahkan `--allow-legacy-player-worksite` pada proses `write`.
Untuk sampel merchant lambat, tambahkan `--merchant-request-seed=2` pada proses
`write`. Untuk sampel 0%, gunakan `--merchant-request-seed=937 --expect-zero`.
Fixture save lama menggunakan `test_scene_playable_needs_legacy_merchant.tscn`
dengan `--legacy-mode=write` pada baseline dan `--legacy-mode=read` pada branch
baru, memakai direktori data sementara yang sama.
