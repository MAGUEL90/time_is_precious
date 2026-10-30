# Pemecatan dan sisa periode payroll

Tanggal 2026-10-22, Asia/Jakarta. Branch `feature/economy/worker-dismissal-payroll`,
baseline `649322760d2f07b96eafce94a3cafefdb4ae791f` (#118), working tree awal bersih.
Cloud saja; Godot 4.5.1 resmi. Tidak mengakses laptop, merge main, atau force-push.

## Kontrak tugas

Pengguna mengizinkan lanjut setelah tahap berikutnya disebut pemecatan tanpa refund
dan kejelasan pesan UI. Handoff sudah mewajibkan peringatan sisa masa berbayar.
Scope terbatas: pesan konfirmasi Worker Hub, refresh quote sesudah pemecatan,
verifikasi no-refund, arsip/rehire dan Save/Continue. Risiko konservatif LEVEL 3
karena sinyal autoload employment dan validasi save; tidak mengubah format save v6, balance,
aturan eligibility atau mekanisme pemecatan. Root menangani keputusan/runtime dan
review; satu subagen Luna XHigh menulis fixture Continue terisolasi sesuai AGENTS.
Keterbatasan root tidak bisa berpindah ke Astra telah dilaporkan pada tahap sebelumnya.

File runtime: `worker_database.gd`, `clay_worker_management.gd`,
`ui_sandbox/worker_control/worker_control.gd` (UI ini sudah dipakai map utama),
serta `city_save_state.gd` untuk referensi tim konstruksi selesai.
Di luar scope: fee cetakan/fasilitas, tarif sementara, City Storage filters,
warehouse → workshop, kebutuhan, rumah/satisfaction, project/addon/settings.

## Hasil audit dan perubahan

- `dismiss_worker` sudah mengarsipkan WorkerData/XP, mengubah warga ke UNEMPLOYED,
  dan menghapus worker dari roster. Tidak ada refund uang yang perlu dihapus.
- `hire_applicant` sudah mempertahankan XP tetapi mengosongkan lima field periode
  lama, menjadwalkan besok08 dan menunggu pembayaran baru. Eligibility warga tetap
  mengikuti aturan existing; tidak otomatis menjadikan warga dismissed applicant.
- Worker aktif/travelling, route dengan cargo, atau worker reserved di pekerjaan
  lain tetap tidak dapat dipecat. Standing idle assignment dilepas melalui adapter,
  lalu alat dikembalikan ke City Storage. Tidak memaksa membuang muatan/progres.
- Worker Hub menambahkan warning dari provider: unpaid, expired, atau tanggal
  berakhir tepat08 beserta sisa hari/jam/menit dan `Unused pay is not refunded.`
  Panel lokal 200×96 logical pixel memuat teks+Yes/No; tidak mengubah viewport.
- Dismissal sukses kini memancarkan `payroll_changed` setelah roster diperbarui,
  agar quote grup berikutnya tidak memasukkan pekerja yang sudah dipecat.

## Perjalanan normal dan visual

Sumber adalah checkpoint earned renewal H11 15:29 (dompet6/kas0, paid H11–H17),
bukan grant fixture. SHA256 sumber:
`2cb6d49aaf0257ec32e7a239ecbfea408e1d939a1aba9806e873929d947b908f`.
Driver `test_scene_dismissal_journey` memakai Continue, navigasi, UI workshop/Hub,
kebutuhan aktif, makan/panen/supply dan bed normal; tanpa clock/needs/RNG override.

Temuan batas existing: snapshot menyimpan citizen ASSIGNED, tetapi pilihan worker
workshop idle bersifat transient. Setelah Continue, driver memilih ulang worker
melalui UI assignment lalu melepasnya sebelum Fire. Langsung menekan Fire pada
state tersebut ditolak; iterasi driver awal gagal karena prasyarat ini. Tidak
melonggarkan guard pemecatan atau mengubah schema untuk menyembunyikannya. Perbaikan
persistensi pilihan workshop idle adalah follow-up terpisah.

`normal-paid-confirmation.png` adalah capture viewport 400×225 tanpa modifikasi,
dari window1200×675, GL Compatibility/llvmpipe pada Xvfb cloud. Teks enam baris dan
tombol muat; No membatalkan, Yes baru memecat. Render driver melaporkan keterbatasan
V-Sync Xvfb/llvmpipe; ini bukan klaim pengujian Windows atau Android.

## Bug save yang ditemukan dan diperbaiki

Normal bed pertama melaporkan `validator_rejected: Construction worker missing`:
plot built masih menyimpan ID tim lama, sedangkan worker telah pindah ke archive.
Validator kini mengizinkan ID archived hanya pada phase `empty`/`built`. Phase
`clearing`/`building` tetap harus memakai worker hired. ID tidak dikenal tetap
invalid. Schema tetap6; tidak menghapus histori tim atau mengubah payload lama.
Fixture memeriksa ketiga kasus pada salinan snapshot, tanpa mengubah plot runtime.

Driver awal hanya mencetak PASS karena belum memeriksa status save bed. Warning
tersebut diperlakukan sebagai gagal, bukan bukti PASS. Driver kini menuntut status
`Saved`, lalu proses read membandingkan seluruh snapshot dan memastikan archive.

## Bukti normal final

- `write` headless: PASS exit0 tanpa warning/error. Cancel kemudian Yes dilakukan
  lewat Worker Hub nyata; sisa paid sampai H18 08:00 hangus, dompet6/kas0 tetap.
  Pemain makan24/panen24 dengan kebutuhan aktif, lalu bed menyimpan H12 07:13
  (menit17713), worker archived, bata/bahan workshop tidak berubah.
- `read` proses baru: PASS exit0 tanpa warning/error. Snapshot Continue sama,
  worker tidak hired dan masih archived; keluar rumah dan upkeep sampai H12 07:50
  (menit17750). Tidak mengubah satisfaction/eligibility agar rehire lolos.
- Run berender dihentikan setelah capture dan konfirmasi selesai agar sisa perjalanan
  diuji headless lebih cepat; run visual bukan PASS end-to-end. Screenshot tetap
  berasal dari perjalanan earned-income yang sama sebelum pembatalan/konfirmasi.
  Uji rehire menggunakan fixture eligibility eksplisit, bukan klaim rehire normal
  warga satisfaction0.01 yang belum memenuhi ambang applicant.

## Fixture, regresi, dan batas akhir

**16 proses perilaku PASS** di Godot4.5.1: 4 fixture dismissal, 2 normal journey,
10 regresi. Semua exit0 tanpa runtime warning/error/leak pada run final headless.

| Kelompok | Proses | Bukti |
| --- | ---: | --- |
| Dismissal Continue | 4 | pending/paid dismissal, quote refresh, archive XP, rehire pending → paid sekali, expired dismissal dan funded retry tanpa charge |
| Normal journey | 2 | earned save → UI cancel/confirm → bed save → Continue + kebutuhan aktif |
| Worker Control | 1 | UI buka/tutup/No/Escape/Yes, guard aktif/cargo, alat kembali, no refund |
| Population / construction | 2 | employment dan lifecycle konstruksi |
| Renewal Continue | 4 | paused work/remainder, migrasi v1–v5, resume dan selesai |
| Production Continue | 3 | fee/input/output Shape dan Drying tidak terduplikasi |

Fixture memberi tiga shekel, XP, clock placements, dan eligibility applicant
secara eksplisit. Itu bukan perjalanan ekonomi normal. Strict snapshot comparator
memakai equality numerik tepat dengan satu JSON round-trip pada expected save,
tanpa toleransi atau field exclusion.

Regresi WorkerControl lama awalnya gagal karena API hire dipanggil sesudah jam
Job Board tutup. Fixture diperbarui untuk maju ke pembukaan08 sebelum pemeriksaan
employment, ditambah null guard; aturan runtime Job Board tidak diubah. Run awal
itu bukan PASS. Import pertama juga membuat ulang UID historis mvp dari cache;
noise import project/addon dan UID sampingan tidak dimasukkan commit.

Tidak ada pengujian Android/Windows. Rehire normal warga dengan satisfaction rendah
belum dibuktikan; eligibility existing tetap berlaku. Tarif final dan sistem rumah
masih tahap terpisah. Pilihan workshop idle transient/ASSIGNED sesudah Continue
masih membutuhkan reselect/release lewat UI seperti dijelaskan di atas.

Status: PASSED — NEEDS HUMAN REVIEW. Merge hanya oleh Game Director.

Editor import final exit0 tanpa error/warning; diff check bersih. Review root
meliputi empat file runtime, driver/fixture/regresi, README dan bukti tugas.
Tidak ada file yang dihapus/di-rename atau perubahan project/addon/settings.
