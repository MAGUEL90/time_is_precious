# Validasi hasil worker untuk renew — 31 Oktober 2026

Status: **PASS — NEEDS HUMAN REVIEW** untuk sampel ini. Branch `test/economy/payroll-worker-proceeds-20261031`, basis `89c3ae2aa1aceb34aa7464cfa7d6c23cde8d80d7`; working tree awal bersih. Risiko Level 1: hanya fixture, driver tes, dan bukti. Tidak ada perubahan kode gameplay, tarif, harga, kebutuhan, jadwal, permintaan merchant, produksi, currency atau schema save.

## Asal checkpoint dan metode

Perjalanan ini melanjutkan checkpoint yang dihasilkan [validasi normal sebelumnya](payroll-flow-validation-2026-10-31.md): New Game kosong, kebutuhan aktif, pergerakan dan interaksi pemain, penjualan kayu yang dikumpulkan pemain, hire melalui Job Board, assignment WoodSite, expiry, renew dan tidur di kasur. Checkpoint yang sama disalin sebagai [fixture sumber](../../scenes/test_scenes/fixtures/payroll-worker-proceeds-origin.json), SHA-256 `81e0f2e7e48f2e497a416a58f48f9b8f4136a5a783f3f063dfa7ccb5b10f3022`. Ini save buatan tes, bukan save pribadi pemain.

Driver baru membuka salinan itu melalui Continue. Untuk membedakan asal barang dan uang dalam sampel, driver secara sengaja menyetor seluruh saldo lama dan kayu lama ke City Storage melalui UI permainan. Setoran kota bersifat tidak dapat ditarik kembali; tindakan ini dilakukan hanya di save tes terisolasi untuk keperluan pengukuran. Tidak ada pemberian barang/uang, perubahan jam, pengaturan ulang RNG atau penonaktifan kebutuhan. Jalur dan tombol diautomasi pada lokasi yang sudah diketahui; ini bukan sesi manusia atau tes discoverability. `--fixed-fps 60` mempercepat eksekusi tanpa mengubah skala jam atau kecepatan pemain.

## Hasil sampel

| Langkah | Pengamatan |
| --- | --- |
| Pisahkan aset lama | Saldo pribadi 6 Shekel dan 4 kayu milik pemain disetor ke kota: wallet 0, kas kota 6. |
| Saldo kurang | Renew tiga hari melalui Worker Hub ditolak dan menampilkan feedback wallet; tanggal kontrak dan kas kota tidak berubah, walaupun kas kota berisi 6. |
| Ambil hasil worker | Tumpukan bertanda output harian WoodSite diambil melalui interaksi E: 33 kayu masuk inventory kosong dari kayu lama. Untuk menyisakan kapasitas makanan, 27 disetor ke kota dan 6 dibawa. |
| Jual hasil worker | Pada kunjungan alami hari 7, merchant meminta 3 kayu; Sell → Max → Confirm mengurangi 3 kayu dan menambah wallet 0 → 6 Shekel, sesuai harga 2 per kayu. Kas kota tetap 6. |
| Renew dari hasil jual | No pada konfirmasi tidak mengubah saldo/kontrak. Yes memperpanjang kontrak tiga hari dan memotong wallet 6 → 5 sekali; konfirmasi lama yang dikirim ulang tidak memotong lagi. Kas kota tetap 6. Kontrak tercatat dibayar sampai Day 11. |
| Save/Continue | Tidur di kasur menyimpan checkpoint; Continue pada proses Godot terpisah memulihkan snapshot, wallet 5, kas 6, kontrak dan assignment WoodSite. |

Bukti [hasil write](evidence/payroll-worker-proceeds-2026-10-31/write-result.json), [log write](evidence/payroll-worker-proceeds-2026-10-31/write.log), [hasil read](evidence/payroll-worker-proceeds-2026-10-31/read-result.json), [log read](evidence/payroll-worker-proceeds-2026-10-31/read.log), dan [capture Continue 400×225](evidence/payroll-worker-proceeds-2026-10-31/continued-city.png). `payroll_changed` dapat terpanggil untuk refresh waktu; bukti pembayaran di sini adalah selisih saldo dan perubahan kontrak, bukan jumlah sinyal.

Ini adalah penerimaan kotor dari satu penjualan, bukan perhitungan laba bersih atau keharusan bahwa setiap profesi menghasilkan cukup untuk membayar kontraknya. Jika permintaan tidak muncul dalam jendela observasi, atau pendapatan lebih kecil dari harga renew, driver melaporkan **PARTIAL** sebagai observasi, bukan menyebut payroll rusak. Permintaan merchant tetap acak.

## Cakupan payroll lain

- Fixture kontrak prabayar dijalankan ulang pada branch ini: **PASS, 0 checks failed**. Meliputi pembayaran atomik/satu kali, dana kurang, batas expired kontrak baru 07.00 dan legacy 08.00, serta dismiss worker prabayar tanpa refund atau biaya otomatis kemudian. Fixture ini mengatur dana dan jam; [log](evidence/payroll-worker-proceeds-2026-10-31/prepaid.log).
- [Perjalanan normal sebelumnya](payroll-flow-validation-2026-10-31.md) membuktikan cancel hire/renew, expiry alami, berhentinya output saat expired, kerja kembali setelah renew, serta save/Continue. Pengujian tanda seru dan kondisi worker lain/merchant/raid tercatat di [laporan dust dan notifikasi](worker-dust-notification-2026-10-31.md).
- Hasil dismissal melalui UI pada [laporan 22 Oktober](worker-dismissal-payroll-2026-10-22.md) adalah bukti historis sebelum keputusan kontrak prabayar terbaru; jangan memakainya sebagai satu-satunya bukti perilaku prabayar saat ini. Fixture prabayar di atas menguji dismissal saat ini melalui API; perjalanan baru tidak memecat worker setelah renew.

## Cara mengulang

Gunakan Godot 4.5.1 dari root proyek, dengan direktori XDG baru setiap pengulangan. Fase `write` menolak menimpa checkpoint yang sudah ada; fase `read` memakai profil yang sama.

```sh
TIP_RUN_DIR=$(mktemp -d /tmp/tip-worker-proceeds.XXXXXX)
export XDG_DATA_HOME="$TIP_RUN_DIR/data"
export XDG_CONFIG_HOME="$TIP_RUN_DIR/config"
export XDG_CACHE_HOME="$TIP_RUN_DIR/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
godot --headless --fixed-fps 60 --path . --audio-driver Dummy res://scenes/test_scenes/test_scene_worker_proceeds_journey.tscn -- --proceeds-phase=write
godot --headless --fixed-fps 60 --path . --audio-driver Dummy res://scenes/test_scenes/test_scene_worker_proceeds_journey.tscn -- --proceeds-phase=read
```

Fase read pada hasil yang dilampirkan memakai display grafis dan GL Compatibility untuk capture, bukan `--headless`. Tes berjalan di Linux; Windows, Android, sesi manual, profesi lain, dan distribusi hasil pada banyak seed belum diuji. Renderer llvmpipe memberi peringatan bahwa perubahan VSync tidak didukung; tes tetap selesai. Percobaan awal tanpa XDG gagal membuat direktori data di home yang tidak writable; pemeriksaan `--check-only --script` tidak memuat autoload proyek. Keduanya bukan hasil tes gameplay; menjalankan scene proyek dengan XDG terisolasi memuat autoload dan lulus.
