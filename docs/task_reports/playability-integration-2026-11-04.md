# Pembaruan playability integrasi — 2026-11-04

Semua hasil final tim tetap berada di branch integrasi lokal
`feature/gameplay/integration-worker-animations-20261104`. Laporan ini
melengkapi [laporan integrasi awal](full-integration-logistics-2026-11-04.md),
termasuk konflik merge dan pengujian logistik, navigasi, shift, save, pause,
scene, dan worker yang sudah dijalankan. Tidak ada push ke branch bersama.

## Asumsi sementara untuk review Hendro

Produksi **Daily oleh worker** langsung menjadi stok City Storage. Kerja
**Hourly yang dilakukan pemain** tetap menjadi milik pemain, masuk Inventory
atau pickup pribadi bila tas penuh. Material konstruksi berasal dari Inventory
pemain. Barang yang sudah menjadi milik kota tetap tidak dapat ditarik pemain;
hauler saat ini memindahkan barang antar-storage milik kota. City Storage
sementara tidak dibatasi berat/slot, dengan perlindungan integer overflow.
Pemisahan kepemilikan ini adalah asumsi yang diminta untuk menjaga alur
sementara dan masih perlu review desain.

Deposit manual pemain ke City Storage saat ini dibatasi pada makanan siap
konsumsi, pakaian, uang, perlengkapan tertentu, Stone, dan Wood. Clay, Reed,
Straw, dan Water dari worker tetap dapat diterima sebagai produksi kota dan
diangkut antar-storage; pembatasan deposit manual tersebut patut ditinjau
terpisah bila pemain nantinya diharapkan menyetor semua bahan itu langsung.

`PlayableNeedsJourney` sekarang memeriksa transaksi Hourly tanpa flag legacy:
jumlah hasil harus sama dengan kenaikan Inventory ditambah pickup pribadi,
stok kota harus tetap, dan stok alam berkurang sesuai produksi bila masih pada
hari yang sama. Perjalanan dari New Game lalu Continue pada proses lain
**PASS**: rumah dibangun dengan material personal, kurma dikumpulkan, kayu
dijual, pakaian dibeli dan disetor, kedua warga pulih dan kembali tersedia di
Job Board. Run dengan seed merchant 2 dan seed kurma 1 mencapai pemulihan pada
hari 6, setelah 17 sesi kerja rumah dan 82 interaksi panen; snapshot lengkap
sesudah tidur cocok saat Continue. Driver ini memakai teleport ke jangkauan
interaksi dan memajukan menit menganggur, bukan bukti navigasi manusia.

## Sumber material dan kebutuhan warga

Run `--audit-material-sources` dimulai dari New Game tanpa grant barang atau
uang. Seluruh kerja Hourly dan perdagangan menggunakan implementasi permainan;
kelebihan bahan dijatuhkan melalui aksi Inventory menjadi pickup pribadi dengan
pemeriksaan kuantitas. Pakaian dan makanan warga tetap dipasok. Run mencapai
20 Stone di Inventory pada hari 22 melalui beberapa kunjungan merchant dengan
pendapatan kayu, lalu **PASS** Continue pada proses baru. Angka hari mencerminkan
strategi dan seed fixture, bukan waktu minimum atau kesimpulan balance.

| Kebutuhan | Bukti |
| --- | --- |
| Wood, Clay, Reed | Sesi Hourly sungguhan menghasilkan material pemain; rumah memakai ketiganya dari Inventory. Pemotongan untuk workshop dan Drying Yard juga diuji terpisah. |
| Straw, Water | Sesi Hourly sungguhan menghasilkan sedikitnya satu batch tiga unit masing-masing dalam Inventory. |
| Stone | Merchant biasa menjual 20 unit secara kumulatif, dibayar dengan uang penjualan kayu, dengan debit uang dan kenaikan Inventory diperiksa pada setiap pembelian. |
| Sun-dried mudbrick | `EarnedBrickFixture` melanjutkan checkpoint bahan yang diperoleh di atas, mempekerjakan worker dengan uang hasil kayu, membangun Yard level 1 dari Inventory, lalu memproses Clay, Straw, dan Water yang dikumpulkan. Hasilnya 21 bata basah termasuk bonus worker, satu batch 20 bata kering, dan 10 bata kering ditarik ke Inventory; 10 sisanya tetap di workshop. Kedua fee dibayar. **Workshop sengaja disiapkan sudah jadi** untuk mengisolasi rantai ini; run ini bukan bukti pembangunan workshop tanpa shortcut. |
| Makanan dan pakaian warga | Kurma dipanen, pakaian dibeli dari merchant dengan hasil kayu, dan keduanya disetor ke City Storage; kedua warga pulih dalam perjalanan kebutuhan. |

Tes terpisah `WorkshopConstruction`, `MultiHouseRuntime`, `DefenseImprovements`,
`WallWork`, `MudbrickPlayerFlow` dan `FacilityContributionContinue` telah
lulus dengan fixture material, termasuk tembok build/repair/upgrade, Watchtower,
serta kontribusi/refund beberapa perjalanan dan Continue. Belum ada satu run
tanpa shortcut yang membangun semua jenis bangunan secara berurutan. Penawaran
sementara merchant untuk Stone adalah 12 per kunjungan pada 2 Shekel per unit;
balance tetap perlu review.

## Hauler dan visual

`CityStorageTransportFlow` write/read kembali **PASS** dengan dialog dan aksi
Cancel yang sebenarnya. Selain kayu, run read memindahkan masing-masing satu
Clay, Reed, Straw, dan Water dari Central ke Annex dengan pemeriksaan stock kota,
kargo, dan Inventory pemain. Jumlah selama pembatalan, tujuan penuh, retry,
resignation dan Continue tetap diperiksa. Tes kontrak/hambatan yang dijelaskan
pada laporan awal juga tetap berlaku.

Run grafis GL Compatibility dengan Mesa llvmpipe pada viewport logis 400×225
**PASS** untuk dialog transportasi dan kedua animasi. Tombol, jumlah, status
rute, dan pembatalan diperiksa pada panel; aksi UI dipicu driver tes, bukan
input manusia. Bukti:

- [Transport siap](evidence/playability-integration-2026-11-04/haul-ready.png),
  [aktif](evidence/playability-integration-2026-11-04/haul-active.png),
  [dibatalkan dan kembali](evidence/playability-integration-2026-11-04/haul-cancelled.png).
- [Pohon kurma](evidence/full-integration-2026-11-04/palm-sway.gif) dan
  [langkah warga](evidence/full-integration-2026-11-04/resident-footsteps.gif).
  GIF menghilangkan beberapa HUD/aktor/papan hanya saat capture. Run grafis
  terbaru kembali menghasilkan 130 frame; pause, transition, lokasi pickup,
  dan lifecycle animasi diperiksa oleh tes otomatis. Penilaian estetika manusia
  dan pengujian Windows/Android masih diperlukan.

## Jalur berjalan

`FoodWalkingPlaytest` **PASS** setelah driver memilih pendekatan yang bebas
tabrakan untuk pohon/pickup dan mengikuti waypoint dengan input arah normal.
Ia menempuh 72 jam, mengunjungi keenam pohon, mengumpulkan 132 kurma, bekerja
1.080 menit, tidur dua kali lewat pintu sebenarnya, berjalan sekitar 29.956
pixel dan tidak tumbang. Seed
kurma 1 digunakan; ini tes rute yang mengetahui lokasi, bukan penilaian apakah
pemain manusia dapat menemukan seluruh rute.

Driver `ContractJourney` tanpa seed atau grant juga sudah melewati hambatan
baseline, berjalan lebih dari 4.600 piksel, dan menjual enam kayu ke merchant;
perekrutan berikutnya tidak menghasilkan worker. Diagnostik menunjukkan Job
Board kosong, kebutuhan dua warga belum terpenuhi, dan kepuasan masing-masing
0,45 sementara ambang pelamar adalah 0,50. Driver lama tidak menyediakan rumah
maupun pakaian sebelum meminta perekrutan, sehingga tidak membuktikan perjalanan
lengkap dengan aturan eligibility kebutuhan baru.
Percobaan tambahan dari checkpoint perjalanan kebutuhan yang sudah pulih
**PASS write/read**: tahap kontrak berjalan memakai input normal sejauh sekitar
14.937 pixel, merekrut dari Job Board dengan uang yang telah diperoleh,
menugaskan worker, memeriksa output Daily di City Storage, menunggu kontrak
habis, membuktikan tidak ada output setelah kedaluwarsa, memperpanjangnya, dan
melihat output kembali bertambah. Tidur membuat save dan Continue di proses baru
memulihkan snapshot, kontrak, saldo dan tugas. Tahap pemulihan sebelum checkpoint
tersebut menggunakan driver percepatan/teleport; rangkaian dari New Game sampai
kontrak belum terbukti seluruhnya dengan berjalan normal. Mekanisme muatan
saat kontrak habis dan diperpanjang juga diuji dalam fixture logistik pada
laporan awal.

Godot 4.5.2 stable dijalankan di cloud dengan profil XDG terisolasi; proses
Godot diurutkan untuk menghindari port runtime plugin yang sama. Bukti log run
tersedia dalam arsip yang disertakan bersama bundle integrasi.
