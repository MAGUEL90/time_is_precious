# Payroll — perpanjangan tujuh hari, jeda dan resume

Tanggal 2026-10-22. Branch `feature/economy/worker-payroll-renewal`, baseline
`2cc80ac51cbfea422446a1ce433f747c4b7b263e` (PR #117, turunan #116). Working tree
bersih sebelum implementasi. Cloud saja, Godot 4.5.1 resmi; tanpa akses laptop.

## Kontrak scope

Pengguna mengizinkan lanjut setelah tahap berikutnya dinyatakan sebagai
perpanjangan tujuh hari dan jeda/resume ketika kas tidak cukup. Aturan berasal
dari handoff dan keputusan pengguna, bukan balance/desain baru. Risiko LEVEL 3:
integrasi runtime worker/produksi/worksite dan persistensi. Root menangani kontrak
waktu dan migrasi save; subagen Luna XHigh menangani worksite dan fixture terbatas
sesuai AGENTS. Runtime root tidak dapat berganti ke Astra (keterbatasan yang telah
dilaporkan pada tahap sebelumnya); tidak mengklaim pergantian model/reasoning.

Scope: kumpulan pembayaran awal+renewal+waiting, penghentian kontribusi pekerja,
reservasi/progres/bahan/muatan tetap utuh, UI status/proyeksi, save/Continue.
Tarif uji 1/2 shekel tetap. Fee Shape/Drying, hasil milik pemain, kebutuhan,
filter City Storage, akses warehouse → workshop, addon/settings dan autoload list
bukan bagian perubahan. Pemecatan/UI refund warning, promosi, rumah/satisfaction
berbasis rumah tetap tahap berikutnya. Tidak merge main atau force-push.

## Kontrak waktu dan pembayaran

- Periode dari hari D pukul 08:00 sampai hari D+7 pukul 08:00 (eksklusif).
  `paid_until_day = D+6`; sebelum pukul 08:00 pada hari berikutnya masih dibayar.
- Pukul 08:00 kumpulkan semua pekerja baru, jatuh tempo dan waiting. Quote memakai
  tarif profesi saat pembayaran. Dana/price cukup → potong total sekali dan isi
  seluruh periode baru; tidak cukup/unpriced → tidak ada potongan untuk siapa pun.
- Periode lama tetap tercatat pada kegagalan; `last_attempt_day` mencatat hari retry.
  Tidak ada saldo utang atau tunggakan. Setoran dompet eksplisit tidak memicu retry.
- Worker yang belum jatuh tempo tetap berhak bekerja. Worker legacy tanpa payroll
  (`start_day = -1`) tetap memakai kompatibilitas lama, tidak ditagih retroaktif.
- Sebelum record periode diganti, `payroll_settling` menyelesaikan interval kerja
  sampai boundary dengan entitlement lama. Ini mencegah hilangnya menit terakhir
  yang sudah dibayar atau penambahan menit gratis saat resume. Broadcast waktu
  biasa setelah settlement tidak memajukan interval sama dua kali.
- Quote Job Board kini memasukkan renewal, bukan hanya pembayaran pertama.
  Status worker/job menunjukkan waiting dan Worker Hub menunjukkan jatuh tempo.
  Nominal periode yang sudah dibayar tidak diubah saat tarif tabel berubah;
  pembayaran periode berikutnya memakai tarif baru, tanpa charge tengah periode.

## Progres kerja saat jeda

- WorkManager menggeser kedua timestamp order sebesar menit tidak berbayar.
  Durasi dan progres yang sudah dikerjakan tetap; input tidak dikonsumsi lagi.
  Reservasi order dipertahankan. Proses pasif Drying tidak memakai gate worker.
- Clearing/build mempertahankan tim. Hanya worker berbayar menyumbang worker-minute;
  sisa pembagian terhadap jumlah anggota disimpan sebagai `payroll_work_remainder`.
  Tim dua orang dengan satu unpaid menghasilkan satu menit progres per dua menit.
- Standing worksite tidak mengumpulkan output saat unpaid dan mempertahankan
  progres parsial worker tersebut saat shift selesai. Batas shift/kuota/tools dan
  kebutuhan lain tetap dipakai. Resume tidak menghapus hambatan selain payroll.
- Hauler membekukan posisi/muatan dengan menggeser start/arrival sebesar interval
  unpaid. Tidak mengambil muatan baru di boundary kedaluwarsa sebelum pembayaran.
  Visual berhenti bergerak saat unpaid. Assignment/cargo tidak dilepas otomatis.
- UI status disegarkan setelah settlement tanpa menambah progres. Ini juga menjaga
  konsistensi snapshot pada pukul 08:00 persis dengan status setelah Continue.

## Save v6 dan kompatibilitas

Schema v6 menambahkan satu integer per plot: `payroll_work_remainder`. Lima field
payroll WorkerData, timestamp WorkOrder dan route hauler yang sudah disimpan tetap
memakai format yang sama. Tidak menambah owner/autoload baru.

- v1–v5 yang benar-benar tidak memiliki field plot baru dimigrasikan ke remainder 0.
- v5 mempertahankan lima field payroll yang sudah ada, tanpa potongan saat load.
- v1–v4 tetap menggunakan codec worker lama eksplisit dengan sentinel legacy.
- v6 menolak remainder yang hilang, negatif atau >= ukuran tim. Periode paid tetap
  wajib tujuh hari. Last attempt kini boleh sesudah paid-from karena renewal gagal.
- Save saat settlement sedang berlangsung ditolak sebagai transaksi belum selesai.
- File lama tidak ditulis ulang sampai save eksplisit berikutnya. Header versi
  lama dengan field baru yang tidak semestinya ditolak, bukan diterima diam-diam.

## Perjalanan normal terpisah dari fixture

`test_scene_renewal_journey` melanjutkan checkpoint earned-income dari tahap produksi
sebelumnya, bukan membuat fixture kaya. Sumber schema v5 adalah checkpoint bed
H7 12:36 dari `paid-production-integration-2026-10-22.md`: dompet 7, kas 0,
paid days H2–H8, 5 dry bricks di tas, 15 dry +14 wet di workshop. SHA256 sumber:
`1b8a330dfc7d7716323a28f177549e2364104b14498fcba1cff7d5baafeb2c05`.

Tidak ada grant/teleport/override waktu, kebutuhan, harga, RNG atau kapasitas.
Driver memakai jalan kaki, makan, panen, supply dan tidur normal. Migrasi v5
membandingkan seluruh snapshot dengan perubahan eksplisit header6/remainder0 saja.

Tiga proses terpisah PASS, exit0, tanpa runtime error/leak:

1. `write`: melanjutkan v5, mempertahankan kebutuhan, mengalami gagal renewal H9
   pukul 08:00, lalu bed menyimpan worker paused H10 07:36. Dompet tetap 7/kas0.
2. `fund`: Continue paused tepat; gagal retry H10 08:00, deposit UI 1 pada H10 08:16
   dari dompet (menjadi6). Worker tetap paused. Observer mencatat tepat satu renewal
   H11 08:00 (menit16320), paid H11–H17, kas0. Tidak membayar hari H9/H10 yang dijeda.
   Bed menyimpan paid state H11 15:29 (menit16769).
3. `read`: Continue paid tepat, kembali ke kota dan upkeep. Dompet6/kas0; bata dan
   bahan produksi tetap. Satisfaction0.01/reliability0.45 tidak diperbaiki agar lolos.

Ini uji normal kelanjutan save earned-income, bukan New Game baru pada tahap ini.
Kebutuhan tetap aktif, clothing/shelter belum tersedia. Satu sampel bukan validasi
balance ekonomi atau seluruh RNG. Produksi saat pause dan muatan hauler diuji oleh
fixture terpisah, bukan diklaim terjadi pada perjalanan normal worker idle ini.

Reproduksi normal: buat checkpoint melalui `test_scene_paid_production_journey`
(write) dahulu; untuk migrasi v5 gunakan parent `2cc80ac`. Salin file checkpoint
aktual tersebut ke `user://renewal_journey/checkpoint.json` pada XDG terisolasi baru.
Kemudian jalankan scene `test_scene_renewal_journey.tscn` dengan
`--headless --fixed-fps 60 -- --renewal-phase=write`, lalu `fund`, lalu `read`,
masing-masing proses baru, memakai XDG yang sama. Timeout 360/360/120 detik; timeout
bukan PASS. Driver tidak menghapus checkpoint pengguna.

## Regresi dan fixture

Batch final Godot 4.5.1: **19 PASS**, semua exit0, tanpa runtime error/warning/leak.
Lihat `evidence/worker-payroll-renewal-2026-10-22/regression-results.json` dan log
bernama sama. Batch ini dijalankan setelah integrasi payroll; koreksi cache commute yang ditemukan
fixture cargo kemudian diuji tersendiri dengan cargo, commute dan departure.

| Kelompok | Proses | Cakupan |
| --- | ---: | --- |
| Renewal core | 1 | Semua due dibayar/jeda atomik, tarif baru, legacy/still-paid, replay, produksi dan Drying pasif |
| Worksite payroll | 1 | Gather parsial, coworker paid, cargo jeda/resume, boundary pickup dan teks tarif |
| Renewal Continue | 4 | write/expire/resume/finish; produksi panjang, tim campuran/remainder1, v1–v5→v6 |
| First payment | 1 | Rekrut, deposit eksplisit, grup pembayaran pertama |
| First-payment Continue | 6 | pending/waiting/paid serta sleep dan Continue |
| Paid production Continue | 3 | Shape/Drying, fee dan output sekali |
| Population, clock, construction | 3 | Regresi employment, broadcast tanpa charge dan konstruksi |

Fixture renewal menambahkan uang, input, recipe delapan hari dan citizen khusus,
serta menempatkan clock untuk boundary. Ini memisahkan determinisme pengujian dari
perjalanan normal. Fixture aktif membuktikan sisa pekerjaan/progres/bahan tidak
hilang, bukan membuktikan balance. Tiga proses normal dicatat terpisah di atas.

Pada iterasi awal, setup fixture diperbaiki (input clay yang kurang, periode seed
agar tepat tujuh hari, dan assertion quote sesudah deposit). Import awal tanpa
XDG_CACHE_HOME serta run tanpa izin jaringan sandbox menghasilkan error lingkungan
cache/socket; keduanya bukan PASS dan tidak termasuk batch final bersih. Tidak
menyembunyikan failure dengan mengubah aturan runtime demi fixture.

### Temuan cache commute dari fixture cargo

Continue awal dibandingkan setelah frame visual berjalan, sehingga cache derived
sudah bertambah. Fixture kini menangkap seluruh snapshot sinkron pada sinyal
`session_started`, sebelum frame berikutnya, seperti driver normal. Pemeriksaan
save tetap memakai snapshot penuh dan validasi CitySave.

Pemeriksaan berikutnya menemukan bug runtime yang nyata: pemanggilan departure
hari pertama penugasan memasukkan key hari lama ke cache yang berlabel hari kini.
Save sesudahnya ditolak validator. `worker_journey` kini hanya menyimpan query hari
kini; query hari lama/depan tetap dihitung tetapi tidak mencemari cache persisten.
Tidak melonggarkan validasi save atau membuang cache sebagai workaround fixture.

Fixture cargo juga membedakan snapshot sebelum save dengan state setelah sinyal
UI. Perbandingan Continue memakai payload encoded langsung terhadap JSON yang
sudah dibaca, tanpa serialize/parse berulang. Diagnosis nilai hunger menunjukkan
angka identik `0.00899999999999999932`; pemrosesan JSON tambahan pada assertion
menimbulkan selisih floating-point. Tidak mengecualikan hunger/field lain dan tidak
menambah toleransi: payload lengkap tetap dibandingkan secara rekursif dengan equality numerik tepat.
Header schema int/float JSON boleh merepresentasikan angka yang sama; integer
gameplay tetap encoded sebagai tag/string. Expected sebelum save melewati tepat
satu serialize/parse, sesuai boundary disk, sedangkan hasil Continue tidak diparse ulang.

## Hasil akhir dan batas review

- Cargo New Game/Continue **4 PASS**: write, paused, resume, deliver. Hauler membawa
  tiga wood logs memakai Cart asli dan DeliveryPoint City Storage asli; deposit
  eksplisit sesudah kegagalan tidak langsung resume, pembayaran pagi berikutnya
  melanjutkan posisi/muatan dan delivery terjadi sekali. Stok alam hari berikutnya
  tetap di-reset menurut aturan existing, tidak diklaim sebagai konservasi lintas hari.
- Commute dan departure **2 PASS** setelah koreksi cache; keduanya exit0 bersih.
- Total **28 proses perilaku PASS**: 19 regresi, 3 perjalanan normal, 4 cargo,
  2 commute/departure. Log cargo bernama `cargo-<phase>.log`, perjalanan normal
  `normal-<phase>.log` dan JSON hasilnya disimpan terpisah dari fixture.
- Editor import Godot 4.5.1 exit0 tanpa error/warning; lihat `editor-import.log`.
  Perubahan otomatis import pada project/addon dan UID/import sampingan dipulihkan.
- `git diff --check` bersih; review runtime, test dan scope dilakukan root.
  Tidak ada perubahan filter City Storage, jalur warehouse → workshop, fee,
  tarif sementara, addon/settings atau daftar autoload.

Pengujian ini headless; bukan review visual baru atas teks status Worker Hub yang
lebih panjang. UI yang telah diterima pada tahap sebelumnya tidak didesain ulang.
Schema6 memerlukan build ini atau yang lebih baru untuk menulis/membaca save baru;
reader tetap menerima v1–v5 melalui migrasi eksplisit. Tarif final, pemecatan dan
refund warning, serta rumah/satisfaction berbasis rumah belum divalidasi tahap ini.
