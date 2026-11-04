# Mengurangi grind pemulihan warga — 2026-11-04

Baseline perubahan lanjutan: `9eba1d20dc9c74121a939554c62a92a0779e1986` pada
`feature/gameplay/playable-needs-recovery-20261104`. Angka berikut adalah
**balance playtest sementara**, masih perlu penilaian manusia dan pengujian
setelah branch logistik serta worker digabung.

## Diagnosis

Pada awal permainan kedua warga berada di 50%, sedangkan merchant pertama baru
datang hari 1. Tanpa shelter keduanya turun pada tengah malam dan tidak dapat
dipekerjakan; pemain masih bisa membangun rumah sendiri. Namun jika merchant
hanya meminta bata, pemain yang belum memiliki pekerja belum tentu bisa
memperoleh Shekel untuk pakaian. Undian dapat mengulang keadaan itu tanpa batas.

Selain itu, Belly bertambah 0,001 per menit: 144 poin persentase per 24 jam
sebelum batas maksimum. Date Cluster lama memulihkan 4 poin, atau kira-kira
36 cluster per hari untuk memenuhi seluruh kebutuhan pemain. Kebutuhan warga
berada di atas itu. Waktu rumah sendiri, 180 menit pembersihan dan 2.880 menit
pembangunan, juga menghasilkan 17 sesi tiga jam. Lonjakan waktu dan Energy
tetap diproses; banyak klik pickup sebelumnya bukan kesalahan penghitung.

## Perubahan yang dipilih

1. Merchant tetap mengundi 1–2 jenis permintaan dari daftar dan jumlah yang
   sama. Setiap kunjungan sekarang juga mencakup permintaan Wood Log yang sudah
   ada, sebanyak **3–6 unit**, **2 Shekel per unit**. Jika hasil undian semula
   hanya bata, permintaan bata tetap ada dan kayu mengisi slot kedua; batas dua
   jenis tetap berlaku. Anggaran, interval tiga hari, stok, harga, dan kuota
   yang ada tidak berubah. Jual sebagian kuota tetap diperbolehkan seperti
   semula: dua kayu menghasilkan empat Shekel untuk dua pakaian, tetapi pemain
   harus mengumpulkan kayu tersebut dan tetap membawa bahan rumah sendiri.
   Tidak ada uang atau barang yang diberikan otomatis.
2. Satu **Date Cluster yang dipanen** kini memulihkan Belly **10%**, dibanding
   4% sebelumnya. Energy-nya menjadi **2,5%**, dibanding 1% sebelumnya:
   keduanya naik 2,5 kali sehingga rasio Energy terhadap Belly ketika efeknya
   terpakai penuh tetap sama. Sepuluh persen sama dengan Fresh Loaf dan masih
   di bawah Roasted Drumstick 15%; alasannya item ini adalah satu *cluster*
   kurma, bukan satu buah. Ini mengurangi jumlah pickup tanpa mengubah jumlah
   barang yang dipanen, stok awal, jumlah pohon, refill, harga, atau kapasitas.
   Nilai makanan warga tetap satu poin per cluster dan kebutuhan harian warga
   tidak berubah.

Pemain tetap dapat membeli dan menyetor pakaian yang sudah ditambahkan pada
commit sebelumnya. Tidak ada perubahan pada +5/-5 Satisfaction, ambang 50%,
masa pakaian tujuh hari, durasi/material rumah, jadwal shift, payroll, atau
skema checkpoint. Kondisi tidur, hunger, dan aturan makanan saat Belly penuh
tetap memakai aturan yang sudah ada.

Sebagai konsekuensi balance, kurma lebih kuat per item bagi pemain dan stok
yang tersisa lebih mudah dipakai untuk warga. Rasio Energy/Belly di atas hanya
tepat saat efek tidak terpotong oleh batas meter. Khusus Belly hampir penuh,
aturan lama tetap memberikan seluruh efek Energy satu item; sekarang efek itu
2,5% per cluster, bukan 1%. Ini perlu ditinjau bersama keseimbangan makanan lain.
Panel item dan pesan konsumsi yang sudah ada membulatkan persentase ke bilangan
bulat, sehingga satu efek 2,5% ditampilkan sebagai 3%; perhitungan sebenarnya
tetap memakai 2,5% dan total beberapa item dibulatkan setelah dijumlahkan.

## Pengukuran terkontrol

Seluruh sampel memakai Godot 4.5.2 headless, kebutuhan pemain aktif, New Game,
food seed terpasang sekali per pohon, dan merchant seed terpasang sekali sebelum
kunjungan. Driver yang sama digunakan sebelum dan sesudah perubahan; ia memakai
aksi/clock permainan untuk kerja, makan, membeli, membangun dan tidur, tetapi
memindahkan pemain langsung ke jarak interaksi dan memajukan waktu menganggur.
Deposit memakai API City Storage yang juga digunakan UI. Karena itu angka
berikut **bukan** waktu berjalan manusia atau bukti kemudahan menemukan alur.

| Skenario | Pemulihan kedua warga | Pickup sampai pulih | Catatan |
| --- | ---: | ---: | --- |
| Sebelum, merchant seed 2, food seed 1 | Hari 14 | 541 | Merchant meminta hanya bata pada hari 1 dan 4; kayu baru diminta hari 7. |
| Sesudah, seed yang sama | Hari 6 | 116 | Bata dari undian hari 1 dipertahankan, kayu juga diminta. |
| Sesudah, merchant seed 937 / food seed 2 | Hari 6 | 116 | Pemulihan dan checkpoint Continue lulus. |
| Sesudah, merchant seed 20261004 / food seed 3 | Hari 6 | 116 | Pemulihan dan checkpoint Continue lulus. |
| Sesudah, sengaja melewatkan kunjungan hari 1 | Hari 8 | 147 | Kayu tersedia pada kunjungan berikutnya; transaksi dilakukan hari 4. |
| Sesudah, sengaja melewatkan empat kunjungan | Hari 23 | 396 | Sampai 0% lalu pulih; pemain sengaja tidak memakai peluang hari 1, 4, 7 dan 10. |

Perbandingan seed 2 memakai driver, strategi, data awal dan benih yang sama;
dua perubahan balance di atas terjadi bersamaan, sehingga tidak mengukur
kontribusi masing-masing secara terpisah. Penurunan pickup sampel dari 541 ke
116 sekitar 79%, bukan jaminan untuk semua pemain atau benih. Rumah tetap 17
sesi, dan 116 interaksi pickup masih bisa terasa repetitif. Pada rerun seed 2,
Hunger tertinggi yang tersampel adalah 47,9% dan Fatigue tertinggi 73,5%; itu
tidak memperhitungkan waktu berjalan manusia. Bila pemain tidak
datang atau tidak punya kayu untuk dijual, permintaan yang dijamin tidak
memberikan dana dengan sendirinya; dari 0% diperlukan sedikitnya sepuluh hari
terpenuhi untuk kembali ke 50% menurut aturan yang ada.

## Save, transaksi dan batas integrasi

Save lama yang dibuat pada `13a6c07` dengan kunjungan **hanya bata** dibuka
ulang tanpa mengubah kuota atau saldo saat kunjungan itu berlangsung. Kayu dan
pakaian tersedia pada kedatangan berikutnya, dan pembelian/save/load ulang tidak
mereset stok. Save perjalanan lama yang dibuat pada `9eba1d2` juga dipulihkan
sama persis pada proses baru. Save menyimpan jumlah/ID barang, bukan nilai
ItemData; sesudah update, Date Cluster yang ada memakai efek baru.

Regresi headless lulus: MerchantRandomRequests (termasuk harga/kuota acak,
konfigurasi salah dan katalog lama), TravelingMerchant, TravelingMerchantAccess,
MerchantMainMapLoop, TravelingMerchantProduction, DatePickup, ConditionHUD,
DateRespawn, DateTreeDuplicate, DatePickupAccess, PlayerEnergyOutput,
InventoryModalPause, CityFoodDaily, CityClothingNeeds,
PopulationEmploymentIntegration, HousePlayerSave, CitySaveEconomy dan
WorksiteIncome. Ketiga perjalanan normal serta dua kasus keterlambatan menulis
checkpoint lalu lulus Continue pada proses baru.
Fixture FoodSurvival enam pohon/seed 1 juga menyelesaikan 72 jam tanpa kolaps
dengan 42 cluster dimakan; ia mengambil semua 150 pickup yang muncul dan tidak
melakukan pekerjaan produksi, sehingga bukan pengukuran klik optimal atau
playthrough lengkap.
HousePlayerSave dan CitySaveEconomy tetap mencetak warning ketika fixture
sengaja mencoba menyimpan saat pembangunan aktif atau membaca save cacat;
penolakan tersebut adalah bagian dari assertion, bukan warning yang disembunyikan.

`FoodWalkingPlaytest` **FAIL pada branch ini dan pada baseline `9eba1d2`** di
koordinat yang sama, `(111.6672, -109.402)` menuju `(112, -108)`, setelah
mengambil 15 pickup dari lima pohon. Fixture memakai koridor jalan yang ditulis
untuk peta lama; run tidak mencapai tes 72 jam, pohon keenam, kerja atau tidur.
Kegagalan ini membatasi bukti berjalan pada peta saat ini dan perlu diselidiki
tersendiri; run teleport di atas tidak menggantikannya.
`ContractJourney` juga **FAIL pada branch ini dan baseline** pada titik yang
sama, `(-103.8726, -64.83441)` menuju `(-112, -64)`, sebelum memperoleh atau
memakan item pertama. Proses gagal itu juga melaporkan ObjectDB instance saat
keluar. Tes kontrak penuh dengan berjalan kaki karenanya belum tervalidasi;
tes payroll/merchant yang disebut lulus di atas adalah fixture terpisah.

Tim logistik masih mengerjakan aturan terbaru: hasil worksite masuk City Storage,
material pembangunan dibawa pemain, dan hauler untuk antar-storage. Sampel di
atas memakai opsi `--allow-legacy-player-worksite` karena baseline ini belum
memiliki perubahan tersebut. Tes standar tanpa opsi legacy **tetap merah** di
baseline dan harus dijalankan ulang setelah integrasi. Driver standar memeriksa
hasil masuk City Storage, pengambilan material ke tas, dan pembayaran rumah dari
tas. Tidak ada klaim pengujian visual Windows atau input manusia.

## Reproduksi

Gunakan direktori `XDG_DATA_HOME` kosong yang berbeda untuk setiap `write` dan
tetap sama untuk `read`. Pada baseline terisolasi ini jalankan:

```sh
godot --headless --path . --fixed-fps 60 res://scenes/test_scenes/test_scene_playable_needs_journey.tscn -- --journey-phase=write --allow-legacy-player-worksite --merchant-request-seed=2 --food-seed=1
godot --headless --path . --fixed-fps 60 res://scenes/test_scenes/test_scene_playable_needs_journey.tscn -- --journey-phase=read
```

Untuk skenario terlambat, tambahkan `--skip-merchant-visits=1`; untuk kasus 0%,
gunakan `--skip-merchant-visits=4 --expect-zero`. Setelah integrasi logistik,
hilangkan `--allow-legacy-player-worksite` agar kontrak output kota diperiksa.
