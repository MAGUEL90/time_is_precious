# Keterbacaan panel kontrak — 31 Oktober 2026

Status: **perubahan modal selesai; pemasangan ikon city gold tertunda**. Nama kandidat di panel kontrak diperbesar, diberi jarak vertikal dan margin sisi yang lebih lega. Tombol 3/6/9 diperkecil untuk mendekatkan centang dan teks, serta Confirm diperkecil sesuai teksnya; ukuran Back tetap. Daftar kandidat yang melebihi tinggi panel dapat digulir, dan posisi gulir dipertahankan saat daftar diperbarui.

Harga, pemilihan, sumber wallet pemain, durasi kontrak, transaksi, produksi, save dan posisi E tidak diubah. Pengujian memakai fixture dengan dana eksplisit, bukan playthrough manual.

## Bukti dan batas

Referensi terbaru dan PNG ikon dikenali oleh Library, tetapi file yang ditunjuk tidak tersedia di executor ini. Percobaan dengan tujuan lokal memberi tautan unduh pada host yang tidak termasuk kebijakan jaringan aktif. Implementasi modal didasarkan pada deskripsi review dan render game dari baseline; gambar referensi terbaru tidak dapat diperiksa langsung di executor. PNG ikon belum dapat diperiksa dimensi, transparansi, atau pikselnya, sehingga belum dipasang dan ikon lama masih tampil.

Render viewport 400 × 225 diskalakan nearest-neighbor ke 1200 × 675:

- [Sebelum](evidence/contract-panel-density-2026-10-31/before.png) dan [sesudah](evidence/contract-panel-density-2026-10-31/after.png).
- [Nama panjang](evidence/contract-panel-density-2026-10-31/after-long-name.png) dan [daftar setelah digulir](evidence/contract-panel-density-2026-10-31/after-scrolled.png).

## Pengujian

Godot `4.5.1.stable.official.f62fdbde1`, XDG terisolasi, satu proses engine pada satu waktu:

- `test_scene_content_prepaid_ui.tscn`: **PASS** headless dan rendered, termasuk ukuran dan jarak nama, ukuran tombol, nama panjang, kandidat terakhir yang dapat digulir, posisi gulir setelah polling, fokus, Back/Escape, buka berulang tanpa pembayaran, perubahan quote, saldo kurang dan pembayaran final sekali.
- `population_employment_integration_test.tscn` dan `test_scene_job_board_closed_feedback.tscn`: **PASS** headless; tes papan mencakup batas jam dan posisi E.
- Peluncuran proyek headless terbatas 180 frame: exit 0; ini bukan playthrough penuh.

Renderer X11/llvmpipe melaporkan perubahan V-Sync tidak didukung. Uji Android, GPU fisik dan review manual oleh pemain belum dilakukan.
