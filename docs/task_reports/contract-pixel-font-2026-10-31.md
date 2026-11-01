# Ukuran font nama kontrak — 31 Oktober 2026

Nama kandidat pada panel kontrak memakai font pixel pada ukuran **12 logical**, menggantikan ukuran 8. Label dan container tidak diskalakan untuk membesarkan teks. Kolom nama diperlebar dan tombol durasi digeser sedikit agar nama contoh `Workshop Laborer` dan `Worksite Hauler` muat utuh; margin, jarak antarnama, dan ukuran tombol compact tetap. Nama yang lebih panjang memakai ellipsis seperti sebelumnya, tanpa mengubah nama atau ID tersimpan.

Tidak ada perubahan pada wallet, pilihan 3/6/9, pembayaran, produksi, save, posisi E atau pengaturan proyek. Ikon city gold belum dipasang: PNG yang diterima belum tersedia sebagai file yang dapat dibaca di executor ini melalui jalur Library yang didukung.

## Pengujian

Godot `4.5.1.stable.official.f62fdbde1`, profil XDG terisolasi:

- `test_scene_content_prepaid_ui.tscn`: **PASS** headless dan rendered, termasuk ukuran font 12 tanpa skala Control, kedua nama contoh utuh, nama panjang, kolom dan tombol tidak bertabrakan, gulir/polling, fokus, Back dan pembayaran tepat sekali.
- `population_employment_integration_test.tscn`, `test_scene_job_board_closed_feedback.tscn`, dan `test_scene_prepaid_contracts.tscn`: **PASS** headless.
- Peluncuran proyek headless terbatas 180 frame: exit 0; bukan playthrough penuh.

Renderer X11/llvmpipe memakai viewport logis 400 × 225 dan window 1200 × 675; driver memperingatkan bahwa perubahan V-Sync tidak didukung. Nama contoh pada fixture sebelum dan sesudah berbeda. Gambar 1200 × 675 diskalakan nearest-neighbor dari viewport logis.

- [Sebelum, ukuran 8](evidence/contract-pixel-font-2026-10-31/before-8px.png).
- [Sesudah, ukuran 12 pada 400 × 225](evidence/contract-pixel-font-2026-10-31/after-12px-400.png) dan [pada 1200 × 675](evidence/contract-pixel-font-2026-10-31/after-12px-1200.png).
- [Nama panjang](evidence/contract-pixel-font-2026-10-31/after-long-name.png).
