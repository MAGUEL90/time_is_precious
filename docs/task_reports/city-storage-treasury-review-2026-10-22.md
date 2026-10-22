# Koreksi review: setoran kas melalui City Storage

Run: TIP-20261022-STORAGE-TREASURY. Tanggal: 2026-10-22 UTC.
Branch: `fix/economy/city-storage-treasury-ui`.
Baseline: `6544d94ae7c1df5f870279a2190be4649191a5d9`; working tree awal bersih.
Risiko LEVEL 2 terbatas, sesuai instruksi pengguna untuk memindahkan setoran ke
interaksi fisik dan menjadikan City Management ringkasan saja. Review manusia
masih pending. Tidak membuat PR baru sebelum pengguna menguji fitur.

## Hasil perubahan

- Job Board tidak lagi memiliki kontrol Deposit. Pelamar menampilkan nama,
  profesi dan tarif; ringkasan pembayaran berikutnya dan jam rekrut dibuat singkat.
- Pemain mendatangi City Storage, membuka Deposit, memilih shekel lalu konfirmasi.
  Membuka dialog atau membatalkan pilihan tidak memindahkan uang.
- Shekel pilihan masuk ke treasury; barang lain tetap menjadi stok fisik.
  Pilihan campuran divalidasi seluruhnya sebelum saldo berubah. Kas penuh,
  saldo dompet kurang atau pilihan invalid menolak seluruh transaksi.
- City Storage menampilkan saldo kas; City Management/Supply hanya menampilkan
  ringkasan saldo. Feedback sukses disingkat menjadi `Deposited.`.
- Filter barang, warehouse/workshop, tarif, fee, aturan payroll dan format save
  tidak berubah. Tidak ada migrasi otomatis untuk tumpukan shekel fisik dari
  save/API lama. API deposit generik tetap kompatibel; hanya setoran UI fisik
  memilih tujuan treasury secara eksplisit.

## Validasi Godot 4.5.1 di cloud

Semua skenario terfokus di bawah lulus. Satu entrypoint legacy yang gagal
dijelaskan terpisah pada bagian keterbatasan. Import akhir dan diff check bersih.

Fixture (grant/penempatan waktu eksplisit, bukan perjalanan normal):

- `test_scene_storage_treasury`: transaksi campuran, batas kas, saldo kurang,
  pilihan invalid, seluruh saldo sudah final saat signal, penolakan reentry,
  serta kompatibilitas shekel fisik lama.
- `test_scene_city_storage_supply_flow`: selector fisik, jumlah tepat, stale
  confirmation, kehilangan akses, equip/reload, dan filter lama.
- `test_scene_city_tool_supply`, `test_scene_raid_ui`.
- `test_scene_payroll_continue`: write/pending/waiting/paid/sleep-write/sleep-read,
  termasuk kelompok pembayaran, tujuh hari, dan tidak membayar ulang saat Continue.

Perjalanan normal (kebutuhan aktif; tanpa grant, teleport, clock edit, atau seed):

- New Game → pendapatan alami 12 shekel pada H4 → setoran fisik 1 → rekrut →
  pembayaran 1 pada H5 08:00 (paid H5–H11) → clearing → tidur/save → proses
  Continue terpisah. Dompet 11, kas 0; snapshot dipulihkan tepat.
- UI review menggunakan checkpoint v6 hasil perjalanan renewal sebelumnya,
  SHA256 `a8b7473beb3319e158c1e2307533dca18fa13d559ed37646b9fe80d614ced872`.
  Cancel tidak mengubah saldo; confirm menurunkan dompet 6→5 dan menaikkan kas
  0→1. Membuka management dan membatalkan pemecatan tidak mengubah saldo.
  Tidur nyata/save lalu Continue memulihkan snapshot tepat.
- Driver renewal juga disesuaikan agar pendanaan ulang melalui City Storage.

Gunakan folder XDG terisolasi dan `--headless --fixed-fps 60` untuk perjalanan,
`-- --journey-phase=write/read`, `-- --ui-phase=write/read`, atau
`-- --renewal-phase=write/fund/read` sesuai scene. `--fixed-fps` mempercepat
simulasi offline tanpa mengubah detik-per-menit dunia atau kecepatan pemain.
Screenshot memakai display virtual cloud, audio Dummy, dan viewport asli 400×225.

## Keterbatasan yang ditemukan

Tes lama `test_scene_city_food_ui` gagal: mengharapkan panel City Supply fisik
terlihat, padahal baseline sudah menyembunyikannya; juga mengharapkan dua
konsumen walaupun fixture memunculkan dua pelamar awal tambahan. Diagnosis
kode baseline dan fixture dicatat; tidak mengaktifkan kembali panel atau mengubah
kebutuhan agar tes lama menjadi hijau. Tes ini bukan bukti penerimaan UI saat ini.

Root meninjau diff implementasi dan adaptasi tes; helper Luna XHigh hanya
mengadaptasi test driver dalam file yang ditugaskan. Konfigurasi model root
mengikuti sesi yang tersedia, tidak diklaim sebagai Astra Medium.

## Review manual sebelum PR

Checkout branch ini, buka project dengan Godot 4.5.1 dan tekan F5. Dengan uang
hasil penjualan, datangi City Storage → Deposit → pilih shekel → Back (saldo
harus tetap) → ulangi dan Deposit (dompet turun, kas naik). Job Board tidak punya
setoran; City Management hanya ringkasan. Tidur/save lalu Continue dan pastikan
saldo tetap serta pembayaran pagi tidak terjadi dua kali. Tarif masih sementara.

Bukti viewport dan hasil New Game disimpan di
[evidence/city-storage-treasury-2026-10-22](evidence/city-storage-treasury-2026-10-22).
Renewal normal write/fund/read juga lulus: pekerja jeda saat kas kosong,
setoran fisik mendanai periode berikutnya, lalu save/Continue tidak menarik ulang.
