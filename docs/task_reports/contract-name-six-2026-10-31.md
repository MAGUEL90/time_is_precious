# Ukuran nama kontrak — 31 Oktober 2026

Sesuai koreksi pemilik, ukuran font nama kandidat pada modal `CHOOSE CONTRACT` diubah dari 12 menjadi **6 logical**, tanpa skala tambahan. Margin, jarak antarnama, tombol compact, ukuran font elemen lain, dan mekanika kontrak dipertahankan. Nama panjang tetap dipersingkat untuk tampilan tanpa mengubah nama tersimpan.

Godot `4.5.1.stable.official.f62fdbde1`: `test_scene_content_prepaid_ui.tscn` **PASS** headless dan rendered, termasuk nama panjang, fokus, Back, pemilihan durasi, gulir dan pembayaran. Peluncuran headless terbatas 180 frame keluar dengan kode 0; ini bukan playthrough penuh. Render memakai viewport logis 400 × 225 dan window 1200 × 675. Driver X11/llvmpipe melaporkan perubahan V-Sync tidak didukung.

[Sebelum, 12](evidence/contract-name-six-2026-10-31/before-12px.png) · [Sesudah, 400 × 225](evidence/contract-name-six-2026-10-31/after-6px-400.png) · [Sesudah, 1200 × 675](evidence/contract-name-six-2026-10-31/after-6px-1200.png) · [Nama panjang](evidence/contract-name-six-2026-10-31/after-long-name.png). Gambar 1200 × 675 diskalakan nearest-neighbor dari viewport logis.

Ikon city gold tetap menunggu file PNG asli yang dapat dibaca di executor; tidak ada percobaan transfer ulang dalam revisi font ini.
