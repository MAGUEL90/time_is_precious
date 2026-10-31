# Ikon city gold pada Job Board — 31 Oktober 2026

PNG kiriman pemilik dipasang pada `WalletIcon` di Job Board, menggantikan ikon kantong sebelumnya. Aset asli berukuran 16 × 16 RGBA, memiliki latar transparan dan SHA-256 `98bf56669a2d5ed001584ec4a3a3a8142ba6c8d1dab6ee325ea8aef9f3216a19`. Ikon ditampilkan pada ukuran aslinya dengan filter pixel yang sudah digunakan UI; aset tidak digambar ulang atau dipotong.

Saldo tetap membaca `Inventory` pemain. Harga, kontrak 3/6/9, transaksi, font nama ukuran 6, produksi, save dan posisi E tidak berubah.

## Pengujian

Godot `4.5.1.stable.official.f62fdbde1`, XDG terisolasi:

- `test_scene_content_prepaid_ui.tscn`: **PASS** headless dan rendered, termasuk ukuran dan alpha ikon, kesamaan piksel terlihat terhadap PNG asli, saldo besar, saldo pribadi yang berbeda dari kas kota, fokus, Back dan pembayaran.
- `population_employment_integration_test.tscn`, `test_scene_job_board_closed_feedback.tscn`, dan `test_scene_prepaid_contracts.tscn`: **PASS** headless. Peluncuran headless terbatas 180 frame keluar dengan kode 0; ini bukan playthrough penuh.
- Pemindaian editor pertama sempat melaporkan aset belum dapat dimuat sebelum impor PNG selesai. Pemindaian kedua selesai tanpa error; enam file UID fixture dibuat ulang dari cache dan dibersihkan sebagai hasil editor yang tidak terkait. Pengaturan proyek dan plugin tidak disertakan dalam perubahan.

Render X11/llvmpipe memakai viewport logis 400 × 225 dan window 1200 × 675; driver melaporkan perubahan V-Sync tidak didukung. Gambar 1200 × 675 diskalakan nearest-neighbor dari viewport logis.

[Sebelum](evidence/city-wallet-icon-2026-10-31/before-board.png) · [Sesudah, 400 × 225](evidence/city-wallet-icon-2026-10-31/after-board-400.png) · [Sesudah, 1200 × 675](evidence/city-wallet-icon-2026-10-31/after-board-1200.png) · [Saldo besar](evidence/city-wallet-icon-2026-10-31/after-large-wallet.png).
