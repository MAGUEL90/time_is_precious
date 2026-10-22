# Payroll — validasi akhir sebelum review manusia

Tanggal: 2026-10-22, Asia/Jakarta. Status **PASSED — NEEDS HUMAN REVIEW** untuk
cakupan pengujian di bawah, bukan penerimaan balance atau persetujuan merge.
Branch `test/economy/payroll-final-acceptance`, baseline
`7fd1211d8bb9f1955b71dd227aa9b2d1ac0b7149` (#120). Working tree awal bersih.
Risiko LEVEL 1: menjalankan pengujian existing dan menambahkan laporan/bukti saja.
Pengguna mengizinkan lanjut; tujuan berikutnya menutup celah validasi perjalanan
normal renewal setelah koreksi idle assignment pada #120.

## Scope dan hasil

Cloud, Godot **4.5.1.stable.official.f62fdbde1**, headless, XDG terisolasi per kelompok.
Tidak ada perubahan kode runtime, test driver, schema, balance, aset, addon atau
setting. Tidak mengakses laptop. Tidak merge main atau force-push. Tidak mengubah
filter City Storage maupun membuka warehouse → workshop. Tidak ada subagen baru.

**11 proses baru PASS**, masing-masing exit0 dengan marker PASS, tanpa warning,
SCRIPT ERROR atau runtime error di log. Ini tambahan bukti di atas 21 proses pada
#120; bukan klaim seluruh rangkaian lama dijalankan ulang. Tidak perlu editor import
baru karena tidak ada source/resource yang berubah; 11 proses memuat project dan
scene terkait. Import terakhir tercatat di laporan #120 beserta warning UID lama.

| Pengujian pada baseline ini | Proses | Hasil |
| --- | ---: | --- |
| Normal renewal write/fund/read | 3 | Migrasi v5, gagal bayar, deposit UI, renewal, bed dan Continue |
| First-payment Continue write/pending/waiting/paid/sleep-write/sleep-read | 6 | Pending/jeda/paid lintas proses dan tidur melewati 08.00 |
| WorkerPayrollFixtureTest | 1 | Deposit guard, jam rekrut, grup pembayaran pertama, still-paid |
| WorkerPayrollRenewalFixtureTest | 1 | Grup due atomik, tarif periode berikutnya, replay, no arrears dan progres |

## Perjalanan normal — bukan fixture

Checkpoint sumber earned-income adalah hasil tahap produksi sebelum renewal,
schema v5, H7 12:36, dompet7/kas0, periode H2–H8. SHA256:
`1b8a330dfc7d7716323a28f177549e2364104b14498fcba1cff7d5baafeb2c05`.
Provenance/reproduksi sumber: `paid-production-integration-2026-10-22.md`.
File sumber disalin ke XDG baru, tidak ditimpa. Driver tidak memberi uang/bahan,
memaksa merchant, atau mengubah kebutuhan, tarif, RNG maupun clock. Perjalanan
memakai berjalan, panen, makan, supply dan tidur dengan kebutuhan aktif.

- write: Continue v5 cocok setelah migrasi eksplisit v6/remainder0 dan perbaikan
  status draft idle. Gagal bayar H9; riwayat paid H2–H8 tetap, uang tidak dipotong.
  Bed menyimpan paused pada H10 07:36, dompet7/kas0.
- fund: Continue paused cocok. Retry H10 gagal. Deposit lewat UI pada H10 08:16
  memindahkan1 dari dompet ke kas (dompet6/kas1), worker tetap paused. Observer
  mencatat tepat satu renewal H11 08:00 (menit16320), paid H11–H17, kas0.
  Tidak ada tagihan hari jeda H9–H10. Bed menyimpan H11 15:29.
- read: Continue paid cocok penuh, lalu kembali ke kota hingga H11 15:59.
  Dompet6/kas0 tetap; workshop15 dry+14 wet dan tas5 dry tidak berubah.

Worker idle selama perjalanan ini. Jeda produksi aktif dan cargo tetap dibuktikan
oleh fixture terpisah di #118/#120. Ini kelanjutan satu save earned, bukan New Game
baru atau bukti semua variasi RNG/balance. Delapan proses fixture dalam batch ini
secara eksplisit menggunakan grant/clock/rate setup untuk kasus deterministik.

## Peta keputusan terhadap implementasi dan bukti

| Keputusan pengguna | Lokasi kode utama | Bukti |
| --- | --- | --- |
| Rekrut 08–17, mulai besok08 | WorkerDatabase.hire_applicant/is_job_board_open | first-core; first-* |
| Setoran eksplisit, bayar7 hari dari kas | CityStockManager.deposit_wallet_shekel; WorkerDatabase._on_payroll_hour | first-core; normal-fund |
| Semua due dibayar/jeda; still-paid lanjut | WorkerDatabase.get_payroll_quote/_on_payroll_hour | first-core; renewal-core |
| Top-up siang menunggu besok; tanpa tunggakan | WorkerData payroll entitlement; WorkerDatabase settlement | normal-fund; renewal-core |
| Tarif profesi, perubahan berlaku periode berikutnya | WorkerDatabase.onboarding_period_rates | renewal-core |
| Output/penjualan milik pemain; fee tetap | WorkShopStorage/Inventory, merchant; mudbrick_make fee5, drying_mudbrick fee2 | Laporan produksi #117; regresi produksi #120 |
| Fire tanpa refund, peringatan sisa periode | WorkerControlUI; dismissal manager | Laporan dismissal #119; regresi #120 |
| Continue tidak menyisakan draft idle | CitySaveState capture/prepare | #120; normal-write pada batch ini |

Tarif sementara tetap Laborer/Hauler/Scavenger1, Crafter/Farmer2 per7 hari.
Nominal final belum tervalidasi. Tidak ada promosi otomatis baru.

## Checklist review pemain

Ini daftar pemeriksaan yang masih membutuhkan penilaian manusia, bukan tes yang
sudah diklaim lulus. Gunakan save pengujian terpisah, bukan save utama.

- Job Board: apakah Wallet, City, total grup pagi berikutnya dan Shortfall jelas?
  Memilih calon harus memperbarui total; merekrut tidak membuatnya langsung aktif.
- Deposit: apakah jelas uang dipindah dari dompet ke kas, dan pekerja yang menunggu
  tidak langsung aktif setelah setoran siang?
- Worker Hub: apakah status pending/paid/waiting dan tanggal periode mudah dibaca?
- Fire pada pekerja idle berbayar: apakah peringatan tidak ada refund dan sisa
  periode terbaca; Cancel mempertahankan pekerja, Confirm mengakhiri employment?
- Bed → Continue: apakah pemain mengerti status yang dipulihkan dan dapat mengelola
  worker idle langsung tanpa memilih ulang di workshop?

Screenshot historis Job Board ada di `evidence/worker-payroll-normal-start-2026-10-22/`;
konfirmasi Fire ada di `evidence/worker-dismissal-payroll-2026-10-22/`.
Tidak ada perubahan visual atau screenshot baru dalam batch ini. Headless tidak
membuktikan kenyamanan UI, Windows maupun Android.

## Reproduksi dan penutupan

Pakai binary4.5.1 dan XDG_DATA_HOME/XDG_CONFIG_HOME/XDG_CACHE_HOME baru di luar repo.
Salin checkpoint earned yang hash-nya cocok ke
`<XDG_DATA_HOME>/godot/app_userdata/time_is_precious/renewal_journey/checkpoint.json`.
Jalankan `test_scene_renewal_journey.tscn` dengan `--headless --fixed-fps 60`, lalu
`-- --renewal-phase=write`, `fund`, `read` sebagai proses terpisah (batas360/360/120s).
Untuk fixture gunakan direktori kelompok lain yang kosong; urutan/perintah ada di
`scenes/test_scenes/README.md`. Timeout/failure bukan PASS.

Log11 proses, ringkasan exit/timing dan tiga JSON hasil normal ada di
`evidence/payroll-final-acceptance-2026-10-22/`. Diff hanya menambah dokumen dan bukti;
root mereview scope, hasil lengkap dan `git diff --check`. Tidak mengubah catatan
historis atau ROADMAP/DEVLOG menjadi seolah rangkaian draft PR sudah merged.

Kontrak payroll yang disepakati sudah memiliki implementasi dan bukti terpisah
untuk fixture/perjalanan normal. Gerbang berikutnya adalah review manusia atas UI
serta nominal tarif. Rumah/satisfaction berbasis rumah, akses pakaian/shelter/Stone
serta balancing pendanaan awal tetap pekerjaan lanjutan dengan keputusan desain
tersendiri; tidak otomatis dimasukkan karena pengujian payroll lulus.
