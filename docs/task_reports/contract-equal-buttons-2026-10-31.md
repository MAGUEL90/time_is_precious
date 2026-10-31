# Ukuran tombol kontrak — 31 Oktober 2026

Tombol Back dan Confirm pada modal `CHOOSE CONTRACT` disamakan dan tetap ringkas. Keduanya memiliki ukuran minimum 42 × 17 dan terukur **42 × 18 logical** pada render. Teks Confirm muat dengan padding, sementara font nama 6, ikon city gold, jarak kandidat, tombol durasi dan mekanika tetap.

Godot `4.5.1.stable.official.f62fdbde1`: `test_scene_content_prepaid_ui.tscn` **PASS** headless dan rendered, mencakup ukuran tombol, fokus keyboard, Back tanpa potongan saldo, Confirm sekali, gulir dan nama panjang. Peluncuran headless terbatas 180 frame keluar dengan kode 0; ini bukan playthrough penuh. Render memakai viewport logis 400 × 225 dan window 1200 × 675; driver X11/llvmpipe melaporkan perubahan V-Sync tidak didukung.

[Sebelum](evidence/contract-equal-buttons-2026-10-31/before.png) · [Sesudah, 400 × 225](evidence/contract-equal-buttons-2026-10-31/after-400.png) · [Sesudah, 1200 × 675](evidence/contract-equal-buttons-2026-10-31/after-1200.png). Gambar 1200 × 675 diskalakan nearest-neighbor dari viewport logis.
