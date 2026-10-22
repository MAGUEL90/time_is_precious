# Pekerja berbayar — integrasi produksi dan fee

Tanggal: 2026-10-22. Cloud saja, Godot 4.5.1 resmi, tanpa akses laptop.
Baseline remote payroll `057af10a3b3f581fd1a613e3027fd952acec59b5`, working tree
bersih. Branch lanjutan `test/process-workshop/payroll-production-integration`
sesuai pemisahan tahap pada handoff. Tidak merge main atau force-push.

## Kontrak scope dan review pengguna

Pengguna menerima UI saat ini, akan menyiapkan aset tambahan, dan menginstruksikan
lanjut. Panah existing ditemukan pada `assets/ui/ui_icon/right_arrow_icon.png`;
tidak membuat aset pengganti. UI tidak diubah pada tahap pengujian ini.
Tarif sementara yang disetujui sebelumnya tetap 1/2 shekel per tujuh hari.

Tujuan: memvalidasi integrasi pembayaran pertama dengan produksi/output/fee dan
Continue, sebelum mengubah mekanisme perpanjangan/jeda. LEVEL 1, test/dokumentasi
saja. File di scope: driver di `scenes/test_scenes`, README dan laporan/bukti.
Tidak mengubah runtime, save schema, balance, kebutuhan, fee, City Storage,
warehouse → workshop, addon atau project settings. Tidak mengubah dokumen kontrol.
AGENTS meminta root Astra; runtime root tidak dapat berganti model (keterbatasan
sudah dilaporkan pada tahap awal). Fixture didelegasikan secara sempit ke Luna
XHigh sesuai AGENTS; root bertanggung jawab atas review diff/hasil.

## Audit fee

- `resources/job_data/mudbrick_make.tres`: `workshop_fee_amount = 5`.
  Workshop meneruskannya ke WorkManager saat memulai Shape, kemudian fee didaftarkan
  pada output selesai oleh `WorkShopStorage.register_completed_job_fee`.
  Sumber ledger adalah `job`, ID `mudbrick_make`; bukan tagihan payroll.
- `resources/process_data/drying_mudbrick.tres`: `station_fee_per_batch = 2`.
  ProcessManager mendaftarkan fee fasilitas per batch. Ledger bertipe `process`,
  ID `drying_mudbrick`.
- Held Output menyimpan fee sampai dibayar menjadi Free Stock. Pembayaran berasal
  dari Inventory/dompet; dana kas kota khusus payroll tetap terpisah.
- Kode memakai istilah fee job/service dan station; ini tidak membuktikan rincian
  naratif seluruh biaya sebagai cetakan saja. Tidak mengganti nama atau menghapus
  salah satu biaya. Tidak ada perubahan kepemilikan hasil workshop.

## Perjalanan normal dengan kebutuhan aktif

Driver `test_scene_paid_production_journey` memperpanjang driver onboarding normal:
New Game kosong, pendanaan merchant alami, deposit UI, hire, pembayaran pagi,
clearing, konstruksi, produksi, pembayaran fee dan tidur/Continue. Tidak ada grant
uang/material/pekerja, forced request/seed, override clock/kecepatan/kapasitas, atau
penonaktifan kebutuhan. Rute mengetahui lokasi authored, bukan uji discoverability.

Route berhenti menambah pekerjaan pada hari terakhir periode pertama agar tidak
mengandalkan expiry/renewal yang belum diimplementasikan. PASS write memerlukan
setidaknya satu drying, pembayaran fee, dan checkpoint masih dalam periode pertama.
Batas waktu tanpa target menjadi PARTIAL/exit 2, bukan PASS. Penjualan bata bukan
syarat gate ini; sampel ini tidak menjual bata. Driver read membandingkan seluruh
snapshot Continue sebelum clock maju, lalu kembali ke kota dan melanjutkan upkeep.
Counter read dimulai nol; bukti produksi ada pada write pasangannya.

Hasil sampel:

- H1: menjual 6 Wood → 12 Shekel; deposit 1, sisanya dompet 11.
- H2 tepat 08:00: pembayaran pertama tepat sekali sebesar 1; periode H2–H8,
  kas menjadi 0. Observer mencatat menit absolut 3360.
- H4: penjualan Wood tambahan 8 Shekel. Total pendapatan 20, tanpa penjualan bata.
- H6 18:21: workshop built (menit 9741), seluruh material dikumpulkan secara normal.
- H7: dua Shape masing-masing menghasilkan 17 wet bricks; satisfaction 0.15 dan
  reliability 0.65 tetap hasil kebutuhan aktif. Dua fee Shape masing-masing 5.
- Satu Drying memakai 20 wet bricks → 20 dry bricks, fee 2. Total fee 12 dari dompet.
  Kas tetap 0; payroll tidak ditagih ulang. Sisa wet bricks 14.
- Pemain menarik 5 dry bricks, 15 tetap di workshop. Tidak ada penjualan bata
  pada sampel ini; tidak memaksa merchant meminta bata agar tes lolos.
- Checkpoint bed H7 12:36 (menit 10836): dompet 7, kas 0, dry bricks 5 di tas
  +15 di workshop, 14 wet bricks. Masih dalam paid days H2–H8.
- Write dan proses terpisah Continue: PASS, exit 0, tanpa runtime error/leak.

## Reproduksi normal

Gunakan XDG data/config/cache terisolasi dan kosong sebelum write, lalu directory
sama untuk read, dengan Godot 4.5.1. Jangan memakai data driver tahap 1 yang lama:
checkpoint internal sengaja mewarisi path `payroll_first_playthrough`.

```sh
godot --headless --fixed-fps 60 --path . scenes/test_scenes/test_scene_paid_production_journey.tscn -- --journey-phase=write
godot --headless --fixed-fps 60 --path . scenes/test_scenes/test_scene_paid_production_journey.tscn -- --journey-phase=read
```

Batas proses eksternal 600s write / 120s read. Hasil JSON di
`user://paid_production_journey/`. Log dan JSON sampel disalin ke
`evidence/paid-production-integration-2026-10-22/`.

## Batas tahap

Satu sampel normal tidak memvalidasi seluruh RNG merchant atau balance ekonomi.
Supply pakaian/shelter tetap belum tersedia; tidak memperbaiki satisfaction dengan
fixture agar perjalanan normal lolos. Renewal, jeda/resume produksi sesudah expiry,
refund/pemecatan UI, perubahan tarif periode berikutnya, rumah dan satisfaction
berbasis rumah belum diimplementasikan. Integrasi tersebut tetap tugas berikutnya.
Tidak mengklaim Windows/Android atau UI visual baru diuji pada tahap ini.

## Fixture save di tengah produksi

`test_scene_paid_production_continue` berjalan dalam tiga proses terpisah:

1. `write`: New Game, hire authored Laborer, penolakan assignment/produksi pending
   tanpa mengonsumsi input; grant dompet 8 lalu deposit eksplisit 1; callback 08:00
   membayar 1 dari kas, dompet tetap 7. Clearing/build memakai API plot asli;
   Shape mengonsumsi bahan sekali dan disimpan saat progres 50%.
2. `continue-shape`: seluruh snapshot harus sama dengan disk. Shape diselesaikan
   menjadi satu Held Output 20 wet bricks dengan satu fee 5. Pembayaran dari dompet
   membukanya menjadi Free Stock, dompet 2/kas 0. Yard dibangun lewat API fasilitas;
   satu batch Drying dan fee 2 disimpan pada pertengahan proses.
3. `continue-dry`: seluruh snapshot harus sama dengan disk. Drying selesai menjadi
   satu Held Output 20 dry bricks, fee 2 tetap belum dibayar. Waktu tambahan tidak
   menggandakan output maupun ledger. Fee Shape tetap tercatat paid, payroll tetap
   satu periode. Ini melengkapi normal journey yang membayar fee Drying dan menarik
   output ke Inventory.

Ketiga fase PASS, exit 0, tanpa warning/runtime error/leak pada log final.
Fixture sengaja memberi uang/material, menetapkan clear weather, menghentikan
clock otomatis, meloncat ke boundary selesai konstruksi dan memakai seed(42) untuk
roll hasil Shape. Kebutuhan tidak dinonaktifkan, tetapi clock jump **bukan perjalanan
normal tiga hari dengan upkeep**. Bukti normal hanya berasal dari driver terpisah.
Kapasitas 200 berasal dari workshop yang benar-benar built, bukan edit max_load.

Reproduksi: data/config/cache XDG terisolasi, kosong sebelum write, lalu sama untuk
ketiga invocation Godot 4.5.1 berikut (masing-masing proses baru):

```sh
godot --headless --path . scenes/test_scenes/test_scene_paid_production_continue.tscn -- --production-phase=write
godot --headless --path . scenes/test_scenes/test_scene_paid_production_continue.tscn -- --production-phase=continue-shape
godot --headless --path . scenes/test_scenes/test_scene_paid_production_continue.tscn -- --production-phase=continue-dry
```

Driver menolak data fixture yang sudah ada; tidak menghapus checkpoint lama.
Root membaca implementasi dan log final subagen, termasuk pemisahan dana,
assertion snapshot penuh, konsumsi input dan ledger. Tidak ada perubahan produksi
untuk membuat tes lolos.

## Review akhir

Import editor Godot 4.5.1 selesai exit 0, tanpa parse error. Satu warning UID driver
MVP historis berasal dari cache. Perubahan otomatis project/addon import dan
metadata import screenshot lama dipulihkan/dibuang; tidak masuk commit.
Dua driver beserta scene/UID, README, laporan dan bukti adalah seluruh perubahan.
Diff diperiksa, tidak ada perubahan runtime atau file protected. Lima invocation
behavioral final (dua normal, tiga fixture) PASS. Status: PASSED — NEEDS HUMAN
REVIEW untuk integrasi periode pertama, bukan klaim seluruh payroll selesai.
