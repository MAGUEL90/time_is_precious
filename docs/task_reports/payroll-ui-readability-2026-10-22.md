# Payroll — keterbacaan UI

Tanggal 2026-10-22 Asia/Jakarta. Branch `fix/economy/payroll-ui-readability`.
Baseline `a0ad8e7d4ca78b7a617e913e2c0e31d58d747219` (#121), working tree awal bersih.
Status **PASSED — NEEDS HUMAN REVIEW**. Risiko LEVEL1, perbaikan presentasi lokal.
Pengguna mengizinkan kelanjutan UI, memakai panah existing yang diputar dan meminta
screenshot untuk review. Tarif tetap sementara. Pengerjaan cloud, tanpa laptop.

## Temuan dan perubahan

1. Angka setoran memakai font besar bawaan meskipun SpinBox memiliki font override.
   Angka sebenarnya dirender child LineEdit. JobBoardUI kini menata font pixel6
   pada child itu dan memusatkan angka. Ikon `right_arrow_icon.png` diputar runtime
   ke atas/bawah; disabled dibuat redup. Aset asli tidak diubah atau digandakan ke
   file baru. Input, batas, transfer dan aturan kas tetap ditangani implementasi lama.
2. Teks periode payroll memperlebar konten detail Worker Hub, sehingga tanggal
   jatuh tempo dan kebutuhan Shelter terpotong. Label Wage kini wrap sesuai lebar
   tersisa; horizontal scrolling dinonaktifkan untuk detail ini. Vertical scrolling
   tetap ada. Tidak menghilangkan informasi payroll/kebutuhan atau mengubah nilainya.

Runtime diff hanya `scenes/ui/job_board_ui/job_board_ui.gd` (17 baris) dan tiga
property scene `scenes/test_scenes/ui_sandbox/worker_control/worker_control.tscn`.
Scene bernama sandbox tersebut memang dipakai Worker Hub gameplay. Tidak ada
perubahan economy, save schema, autoload, fee5/2, filter City Storage, warehouse →
workshop, addon/settings atau sistem rumah. Tidak ada delegasi baru.

## Bukti visual dan save/Continue

Godot4.5.1 resmi, Compatibility llvmpipe, Xvfb cloud window1200×675. PNG adalah
viewport logis400×225 tanpa edit atau pembesaran. Screenshot `before-*` memperlihatkan
masalah sebelum koreksi; `job-board.png`, `deposit-amount.png`, `worker-hub.png`,
`worker-details.png` dan `fire-confirmation.png` memperlihatkan hasil final.

Sumber adalah checkpoint earned H11 15:29 dari validasi #121, dompet6/kas0,
paid H11–H17. SHA256:
`a8b7473beb3319e158c1e2307533dca18fa13d559ed37646b9fe80d614ced872`.
Salinan terisolasi ada di `user://payroll_ui_review/checkpoint.json`. Driver baru
melanjutkan save normal ini, berjalan ke Job Board, dan tidak memberi uang/bahan
atau mengubah kebutuhan, clock, RNG maupun tarif. Ini bukan New Game baru.

Lima proses perilaku final exit0/PASS:

- Rendered capture: Continue cocok penuh; klik panah naik2/turun1/batas minimum1;
  memilih jumlah tidak mentransfer uang; tutup/buka merekreasi panel; detail muat
  tanpa horizontal overflow; Cancel Fire mempertahankan worker/dompet/kas.
- Headless write: alur UI yang sama, dilanjutkan upkeep/panen/makan24 dan bed H12
  07:11 (menit17711). Save berhasil, pekerja tetap hired dan periode tetap paid.
- Headless read: proses baru memulihkan snapshot penuh, keluar rumah H12 07:14.
  Dompet6/kas0, tas5 dry, workshop15 dry+14 wet tetap.
- WorkerControlTest: regresi kontrol pekerja existing PASS (fixture).
- WorkerPayrollFixtureTest: regresi rekrut/setoran/pembayaran existing PASS (fixture).

Capture hanya review UI tanpa save; pasangan write/read yang membuktikan bed dan
Continue. Kebutuhan aktif pada alur normal; dua regresi fixture tidak dianggap
bukti pendanaan normal. Semua log di `evidence/payroll-ui-readability-2026-10-22/`.

Rendered capture memiliki satu warning V-Sync karena driver Xvfb/llvmpipe tidak
mendukung pengaturan tersebut; tidak ada error runtime. Empat proses headless
bersih tanpa warning/error. Import editor exit0 tanpa parse error, dengan warning
UID skrip MVP lama dibuat ulang dari cache; artefak import di luar scope dipulihkan.
UID driver baru disimpan. `git diff --check` dan review diff runtime/test lulus.

Iterasi investigasi tidak dihitung PASS: run awal memakai audio default yang tidak
tersedia di cloud, lalu driver mengakses referensi Job Board yang sudah di-free
saat close. Driver diperbaiki untuk interact/reacquire panel; run final memakai
`--audio-driver Dummy`. Run rendered lain dihentikan setelah screenshot karena
menunggu hari berikutnya mahal dalam software renderer; pengujian penuh bed
kemudian selesai headless. Tidak mengubah runtime demi meloloskan setup pengujian.

## Reproduksi dan batas

Salin checkpoint sumber di atas ke lokasi review pada XDG_DATA_HOME terisolasi.
Set XDG_CONFIG_HOME/XDG_CACHE_HOME terisolasi juga. Jalankan scene baru memakai
`--fixed-fps 60 -- --ui-phase=capture` dengan display cloud dan audio Dummy untuk
screenshot (batas120s). Lanjutkan `--headless -- --ui-phase=write`, lalu `read`,
masing-masing proses baru dengan XDG yang sama (batas180/120s). Capture tidak
menulis checkpoint; write menyimpan lewat bed. Jangan memakai save utama pengguna.

Screenshot final menguji paid state normal. Pending/waiting, daftar kosong dan
angka ekstrem tidak mendapat screenshot baru; bukti tahap sebelumnya tetap
terpisah. Tidak mengklaim semua variasi nama/nilai, Windows/Android, nominal tarif
final atau kenyamanan visual manusia lulus. Tidak merge main atau force-push.
