# Uji keseimbangan pendapatan–upah

Tanggal 2026-10-22 Asia/Jakarta. Branch `test/economy/payroll-balance-samples`.
Baseline `d0c8fca0fb0fc642a400054bc321ae7cffaa375a` (#122), tree awal bersih.
Risiko LEVEL1: test, analisis dan dokumentasi. Pengguna meminta uji keseimbangan;
tidak mengizinkan penetapan tarif final. Status teknis **PASSED — NEEDS HUMAN REVIEW**,
bukan pernyataan ekonomi seluruh permainan sudah seimbang.

## Hasil utama

Untuk rute satu Laborer pada periode pertama, pendapatan menutup upah dan fee di
ketiga sampel. Upah1 bukan pengeluaran uang terbesar. Risiko yang lebih terlihat
adalah kapan pendanaan awal tersedia: merchant alami membuat uang pertama baru
masuk H1, H4 atau H7. Menunggu itu juga memperpanjang kebutuhan yang harus dipenuhi.

| Sampel | Uang pertama | Periode paid | Pendapatan kayu | Pendapatan bata | Fee | Upah | Dompet akhir |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | H1 09:02, 8 shekel | H2–H8 | 14 | 45 (15 bata) | 12 | 1 | 46 |
| 2 | H7 08:26, 10 shekel | H8–H14 | 30 | 39 (13 bata) | 12 | 1 | 56 |
| 3 | H4 08:34, 10 shekel | H5–H11 | 28 | 36 (12 bata) | 12 | 1 | 51 |

Kas akhir **0 pada semua sampel**: saldo di dompet tidak otomatis mendanai renewal.
Pemain tetap perlu menyetor1 sebelum pembayaran berikutnya. Sampel2 memiliki uang
akhir lebih besar karena penjualan kayu lebih banyak, bukan bukti menunggu lebih
lama adalah strategi yang lebih baik.

Ini **surplus kas, bukan laba ekonomi penuh**. Bahan dikumpulkan pemain dan belum
diberi nilai uang/waktu; pembangunan, perjalanan, makanan serta stok akhir bukan
beban kas yang dihapus dari tabel. Semua sampel masih menyimpan14 wet bricks dan
5/7/8 dry bricks yang belum terjual. Stok itu tidak dihitung sebagai pendapatan.

## Protokol dan cakupan

Tiga New Game terpisah ditetapkan sebelum batch final, semua hasil dicatat. Dunia,
dompet, kas dan roster dimulai kosong. Godot4.5.1 resmi di cloud, kebutuhan aktif,
RNG merchant/cuaca/reliability alami. Tidak seed, grant, teleport, edit clock,
kapasitas, harga, tarif atau pemaksaan permintaan. Tidak ada akses laptop.

Rute yang sama untuk ketiganya:

1. Panen/makan/supply dan kumpulkan kayu, jual saat merchant meminta.
2. Deposit1 lewat Job Board, hire Laborer, tunggu besok08 untuk pembayaran.
3. Clearing, kumpulkan material, bangun workshop dan Drying Yard1.
4. Produksi hingga satu batch20 dry bricks; bayar fee dari dompet.
5. Tarik bata yang muat, sisakan ruang8 beban untuk kebutuhan, jual ke merchant
   alami sampai batas observasi hari terakhir paid; tidak menambah batch produksi.
6. Bed checkpoint dan Continue proses baru, membandingkan snapshot owner penuh.

Perubahan kebijakan dari driver produksi lama: tidak sengaja menyisakan10 bata
untuk upgrade yard2. Sampel ini menguji monetisasi awal, bukan strategi upgrade.
Rute tahu lokasi authored, menjual kayu juga bila diminta, dan belum dioptimalkan
sebagai pemain ahli. Batas proses600s write/120s read; PARTIAL/timeout bukan PASS.

File baru `test_scene_payroll_balance.gd/.tscn/.uid` mewarisi helper produksi
normal. Runtime gameplay, tarif, fee, schema, settings/addon dan aset tidak berubah.
Tidak mengubah City Storage filter/warehouse → workshop atau kebutuhan rumah.

## Waktu dan tekanan kebutuhan

| Sampel | Workshop built | Drying pertama selesai | Bed checkpoint | Satisfaction / reliability akhir |
| --- | --- | --- | --- | --- |
| 1 | H6 18:30 | H7 06:40 | H8 00:53 | 0.10 / 0.60 |
| 2 | H12 19:15 | H13 06:36 | H14 02:18 | 0.01 / 0.30 |
| 3 | H9 19:32 | H10 06:52 | H11 01:21 | 0.01 / 0.45 |

Bata pertama baru tersedia sekitar lima hari setelah pembayaran pertama, termasuk
clearing dan pembangunan. Konstruksi satu worker memang3 hari (`SOLO_MINUTES`),
selain pengumpulan bahan dan clearing180 menit. Membandingkan pendapatan/biaya
periode ini tidak sama dengan throughput workshop yang sudah jadi.

Sampel2 mengamati kunjungan H1 dan H4 yang hanya meminta bata, sehingga belum ada
barang awal yang dapat dijual. H7 baru meminta5 kayu. Sampel3 mengalami satu
kunjungan awal hanya bata. Ini bukti variasi tiga sampel, bukan estimasi peluang
atau batas maksimum tunggu. Tidak ada klaim H7 adalah kondisi terburuk.

Player memanen294/525/408 dan memakan274/492/383 kurma pada tiga rute. Angka ini
mencakup durasi kalender berbeda, bukan laju per hari atau diagnosis tunggal hunger.
Pakaian/shelter belum tersedia; satisfaction tidak dipulihkan dengan fixture.
Keterlambatan, suplai makanan dan kebutuhan lain saling terkait, sehingga beda
reliability tidak boleh diklaim semata-mata akibat RNG merchant.

## Fee, upah dan titik impas kas

Kode yang diaudit:

- WorkerDatabase: Laborer1 per7 hari; profesi lain tetap tabel sementara1/2.
- `mudbrick_make.tres`: input3 clay +3 straw +3 water, output nominal20, fee5.
- WorkerData/WorkManager: satisfaction <0.4 memakai multiplier0.85; reliability
  dapat menambah penalti output0.75. Hasil nyata seluruh Shape batch final17.
- `drying_mudbrick.tres`: batch penuh20 wet →20 dry, fee2.
- `common_merchant.tres`: beli dari pemain wood2/bata3; kunjungan tiap3 hari,
  permintaan alami1–2 jenis, wood3–6/bata10–20. Harga input yang dibeli pemain2/unit.

Karena17 wet belum cukup untuk20, setiap sampel membayar **dua Shape5 + Drying2 =12**,
lalu upah1. Dari13 pengeluaran kas yang teramati, fee menyumbang92.3%, upah7.7%.
Lima bata terjual pada harga3 sudah menutup13 biaya kas itu, **hanya** bila biaya
bahan/waktu/infrastruktur dikecualikan seperti pada strategi gather ini.

Untuk mengeluarkan batch pertama dibutuhkan modal kas kumulatif13 sebelum bata
tersebut bisa dijual. Satu kunjungan maksimal meminta6 kayu ×2 =12, sehingga rute
ini memerlukan setidaknya dua kunjungan pembeli kayu jika seluruh modal berasal
dari kayu dan hasil Shape17. Ini tidak berlaku untuk semua strategi/yield.

Dua Shape juga meninggalkan14 wet, sehingga fee12 bukan biaya berulang tetap per
20 dry. Dengan yield17 yang sama, batch berikutnya cukup satu Shape lagi + Drying
(fee7), memakai sisa wet. Payroll juga per waktu, bukan per batch. Jangan mengalikan
13 dengan jumlah batch untuk menyimpulkan biaya jangka panjang.

Sebagai perhitungan saja: membeli seluruh18 unit bahan untuk dua Shape pada harga2
memerlukan36 tambahan; bersama fee/upah menjadi49. Penjualan20 dry penuh bernilai60,
menyisakan11 kas sebelum biaya lain dan masih ada14 wet. **Strategi membeli bahan
ini belum disimulasikan**, dan tidak otomatis menghasilkan arus kas tepat waktu.

## Penilaian dan rekomendasi

- Pertahankan tarif uji1/2 dahulu. Sampel satu Laborer ini tidak menunjukkan upah
  terlalu mahal; belum cukup untuk menetapkan upah semua profesi atau menyimpulkan
  upah final terlalu murah. Tidak ada angka runtime yang diubah.
- Prioritas desain untuk dibahas: toleransi menunggu pendanaan awal. Apakah menunggu
  sampai H7 tanpa pendapatan dapat diterima? Bukti ini lebih mendukung membahas
  akses pendanaan daripada langsung mengubah upah. Tidak memasukkan starter uang,
  quest atau request merchant terjamin tanpa keputusan pengguna.
- Validasi keseimbangan jangka panjang perlu rute workshop sudah jadi selama
  beberapa periode, beberapa pekerja/profesi, serta suplai kebutuhan yang tersedia.
  Satisfaction rendah mengubah yield, sehingga menaikkan gaji sekarang berisiko
  menutupi masalah suplai yang berbeda.

Sensitivitas aritmetika, **bukan run tarif alternatif**: bila semua hasil dan waktu
transaksi dipertahankan, mengganti satu pembayaran1 menjadi2/3 akan mengurangi
saldo akhir hanya1/2. Tetapi modal awal lebih besar dapat menggeser waktu produksi;
karena itu selisih tersebut tidak memprediksi hasil simulasi tarif2/3.

## QA, provenance dan keterbatasan

Batch final **6 proses PASS/exit0**, tiga write + tiga Continue, tanpa warning atau
runtime error. Tidak ada reroll hasil final. PASS berarti rute dan persistence
bekerja, bukan berarti balance telah disetujui. Setiap titik pengukuran direkonsiliasi:
`pendapatan = wood_terjual×2 + bata_terjual×3`; `dompet+kas = pendapatan−fee−payroll`.
Seluruh equality lolos. `evidence/.../analyze.py` menghasilkan `summary.json` dari
JSON mentah dan dapat dijalankan dengan Python standard library untuk memeriksanya.

Pilot sebelum koreksi driver tetap disimpan di subfolder `pilot/`. Dua write
PARTIAL karena helper lama meminta bed tambahan setelah upkeep sudah tidur pada
hari terakhir paid, sehingga observasi melewati periode; read keduanya PASS.
Pilot ketiga write PASS, read dihentikan saat batch final disiapkan. Pilot tidak
dicampurkan dengan tiga sampel final dan bukan bukti perubahan balance runtime.
Driver baru memakai checkpoint bed final-day yang sudah benar-benar ditulis,
bukan membuat snapshot/grant pengganti. Batas paid period tidak dilonggarkan.

Editor import4.5.1 exit0; warning UID driver MVP lama dibuat ulang dari cache dicatat.
Noise import pada addon/project/screenshot lama dipulihkan, UID test baru disimpan.
Review source/diff dan `git diff --check` lulus. Tidak merge main atau force-push.

Belum diuji: probabilitas populasi RNG, masa stabil multi-periode, pembelian bahan,
hauler/crafter/farmer sebagai strategi ekonomi, optimasi carry/penjualan, review
pemain manusia serta Windows/Android. Save/Continue diuji pada akhir rute, bukan
pengukuran ekonomi baru setelah read yang counternya memang dimulai nol.

Reproduksi: fresh XDG per sampel, directory sama hanya antara write/read; jalankan
`test_scene_payroll_balance.tscn -- --journey-phase=write` kemudian `read` dengan
`--headless --fixed-fps 60` di Godot4.5.1. JSON berada di
`user://paid_production_journey/`, save mewarisi `payroll_first_playthrough/`.
