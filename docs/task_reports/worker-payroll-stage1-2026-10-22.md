# Payroll tahap 1 — 2026-10-22 (Asia/Jakarta)

Status: **PARTIAL — fondasi pembayaran pertama teruji, belum siap merge/aktivasi normal**.

## Kontrak scope dan asal branch

- Repository MAGUEL90/time_is_precious, branch `feature/economy/worker-payroll-onboarding`.
- Baseline kerja bersih: remote `19b98575bc62a2530d4a76679b935eb16ef01cd9`.
  Commit lokal `a8aa5cb` tidak dipakai. Parent audit `17507b4` tersedia remote.
- Remote main masih `d6ea244`; parent `test/gameplay/mvp-first-playthrough`
  masih `17507b4`. Audit/merchant fix parent belum merged ke main.
- LEVEL 3 untuk integrasi employment, kas, waktu dan save, dalam otorisasi tahap 1
  pengguna/handoff. Tidak menetapkan balance baru. Root tidak berpindah model;
  subagen Luna XHigh hanya menulis fixture payroll/populasi, lalu diff dan hasil
  diuji ulang oleh root. AGENTS dan kontrol 00–06 dibaca.
- Tujuan: setoran eksplisit, jam Job Board, hire pending, pembayaran awal atomik,
  feedback dan save/Continue. Tidak menambah autoload, mengubah kebutuhan, atau
  mengerjakan rumah/satisfaction, production pause/resume, renewal dan UI pemecatan.
- Godot resmi 4.5.1 `f62fdbde1`, cloud Linux. Tidak mengakses laptop/computer use.

## Implementasi dan keputusan yang masih terbuka

`CityStockManager.deposit_wallet_shekel` memindahkan jumlah pilihan pemain dari
Inventory ke kas, menolak nol/negatif/kekurangan/overflow tanpa kehilangan uang.
Kedua saldo berubah sebelum notifikasi inventory. Payroll hanya membaca kas.

Job Board fisik buka 08:00–17:00 (17:00 sudah tutup). UI menampilkan saldo dompet,
kas, total kelompok besok termasuk calon yang dipilih, kekurangan dan waktu mulai.
Hire dicatat untuk hari berikutnya; sebelum pembayaran pertama pekerja tidak dapat
ditugaskan melalui workshop, construction, worksite atau start WorkManager.

WorkerDatabase menangani elapsed `hour_changed(8)`, bukan snapshot `time_changed`.
Semua hire yang mulai/juga masih menunggu dikumpulkan. Kas cukup: bayar seluruhnya,
catat tarif periode dan hari bayar sampai hari bayar +6. Kas kurang: tidak ada
potongan, worker tetap HIRED/pending, retry besok. Deposit sesudah attempt tidak
mengulang pembayaran hari itu. Callback berulang dan restore tidak menagih ulang.
Pekerja yang sudah menerima pembayaran pertama tidak masuk batch initial berikutnya.

**Tarif produksi masih kosong (`onboarding_period_rates = {}`).** Handoff menyebut
1/2 Shekel sebagai kandidat, bukan tabel final. Tidak ada persetujuan angka pada
sesi ini. UI menampilkan `Rate TBD` dan Hire dinonaktifkan untuk profesi tanpa tarif;
API juga menolak. Karena itu **New Game belum bisa menyelesaikan rekrutmen normal**
pada branch draft ini. Jangan menganggap fixture sebagai validasi balance atau
perjalanan normal. Pertanyaan tarif sudah diajukan; perlu tabel untuk Laborer,
Hauler, Crafter, Farmer dan Scavenger (atau scope profesi yang diaktifkan).

Batas irisan: tanggal akhir periode dicatat, tetapi **expiry/renewal dan penghentian
kontribusi pekerjaan aktif setelah periode berakhir belum diterapkan**. Sesuai
handoff itu tahap selanjutnya; jangan mengklaim payroll berulang tujuh hari sudah
berfungsi atau melepas branch ini sebagai ekonomi lengkap. Rekrut sebelum aktif
belum menyediakan preassignment; worker baru boleh ditugaskan setelah dibayar.
Legacy worker/save mempertahankan perilaku lama tanpa tagihan retroaktif. Field
`wage_shekel_per_day` dipertahankan untuk kompatibilitas, bukan sumber tarif payroll.

## Fee, kepemilikan, dan batas tetap

`mudbrick_make.tres.workshop_fee_amount = 5` dipakai sebagai fee job/output workshop.
`drying_mudbrick.tres.station_fee_per_batch = 2` adalah fee fasilitas per batch.
Regresi production chain membuktikan ledger fee/output masih bekerja. Fungsi ini
berbeda dari payroll; tidak ada fee dihapus. Tidak ada keputusan baru bahwa fee
tersebut harus diganti upah. Hasil workshop dan penjualan tetap milik pemain.
Filter City Storage, jalur warehouse → workshop, recipe dan kebutuhan tidak berubah.

## Save

Writer schema **v5** menambah lima field WorkerData: start day, paid-from day,
paid-until day, period rate, last-attempt day. Saldo kas/dompet sudah memiliki owner
save existing. Codec v5 wajib menerima field lengkap bertipe benar; validator
menolak periode bukan tujuh hari, tarif paid nol, dan pending worker yang reserved.

Reader v1/v2/v3/v4 memakai schema WorkerData lama secara eksplisit, menghasilkan
sentinel `start_day=-1` tanpa menagih ulang. Migrasi pickup-source lama tetap berjalan.
Build lama tidak membaca v5. Save prototype clay-worksite yang terisolasi tidak
menjadi jalur save gameplay dan tidak dinaikkan versinya pada pekerjaan ini.

## Validasi

Semua run final pada `evidence/worker-payroll-stage1-2026-10-22/results.json`:

- Payroll fixture: uang/rate/warga buatan, dana nol/kurang/cukup, transfer invalid dan
  overflow, 16:59/17:00, kelompok campuran hire baru/pending, replay dan paid worker
  tetap assignable saat kelompok lain gagal. Profesi tanpa tarif ditolak.
- Enam proses checkpoint: `write → pending → waiting → paid`, lalu
  `sleep-write → sleep-read`. New Game/Continue melalui startup menu sebenarnya.
  Semua owner snapshot dibandingkan persis sebelum clock maju. Pending dan attempt
  gagal bertahan; pembayaran tidak terlewat atau ganda. Input dana/tarif dan
  penempatan clock adalah fixture. Player needs/fatigue tidak dimatikan.
- Tidur sungguhan di rumah memakai bed/fade dan time skip tujuh jam dari 01:00 ke
  08:00, menghasilkan pembayaran pertama dan autosave. Continue proses baru
  kembali ke rumah dengan checkpoint yang sama dan tanpa potongan tambahan.
- Reader fixture v1/v2/v3/v4 lolos prepare dengan field legacy asli; v5 kehilangan
  field payroll dan durasi corrupt ditolak. Ini bukan klaim semua save historis diuji.
- PopulationEmploymentIntegration, CitySaveValues, ClockStateBroadcast dan
  MudbrickProductionChainIntegration lolos. Tes populasi memakai rate/funding milik
  fixture dan benar-benar menunggu boundary pembayaran sebelum assignment.
- Total **11 invocation final PASS**, exit 0, tanpa SCRIPT ERROR/runtime error/leak.
  Import editor final exit 0 tanpa parse error; warning UID driver MVP lama yang
  tidak tracked berasal dari cache, bukan runtime payroll. Noise import dibuang.
  Job Board diuji batas window/actions headless pada viewport logis, bukan visual
  acceptance manusia. Tidak mengklaim Windows/Android atau pacing/balance PASS.

Percobaan investigasi: listener addon awal ditolak sandbox; menjalankan dengan izin
jaringan executor memulihkan listener loopback tanpa mengubah addon/settings.
Fixture pertama meloncat 24 jam dengan kebutuhan aktif dan gagal save karena
interaksi/kondisi pemain; tidak dihitung PASS. Fixture diganti penempatan boundary
07:59, sedangkan skip nyata diuji terpisah lewat bed. Populasi fixture lama gagal
karena mengharapkan hire langsung aktif, kemudian diperbarui ke kontrak baru.
Suite lama lain yang mengasumsikan immediate hire/daily wage belum dimigrasikan
semuanya. Perjalanan normal lama belum diulang karena tarif produksi masih TBD.

## Reproduksi

Gunakan binary Godot 4.5.1 dan XDG_DATA_HOME/XDG_CONFIG_HOME/XDG_CACHE_HOME terisolasi
serta kosong pada awal pasangan write/read. Jangan gunakan save pengguna.

```sh
godot --headless --path . scenes/test_scenes/test_scene_worker_payroll.tscn
godot --headless --path . scenes/test_scenes/test_scene_payroll_continue.tscn -- --payroll-phase=write
# Lanjutkan proses baru dengan data directory yang sama:
# --payroll-phase=pending, waiting, paid, sleep-write, sleep-read
```

## Review dan tindak lanjut

Perubahan produksi terbatas pada WorkerData/WorkerDatabase, CityStockManager,
JobBoard/UI/Worker Hub formatter, empat guard assignment/start, dan save codec.
Dua scene test baru, adaptasi fixture populasi, laporan/bukti dan petunjuk test.
Tidak ada penghapusan/rename, perubahan AGENTS/control, project settings, addon,
filter City Storage atau alur kepemilikan. Noise import editor dipulihkan ke HEAD.

Sebelum aktivasi normal: tetapkan tarif uji per profesi, ulangi perjalanan normal
mendapat Shekel → deposit → hire → tidur/bayar → assignment → save/Continue dengan
kebutuhan aktif; review UI manusia. Renewal/jeda/resume/progres/cargo dan dismissal
warning tetap pekerjaan tahap berikutnya. Jangan merge atau force-push.
