# Tata letak Job Board dan kontrak — 31 Oktober 2026

Status: **sebagian selesai; ikon city gold menunggu identifikasi aset**. Referensi Job Board dan panel kontrak dilihat langsung dari lampiran percakapan. Perubahan ini melanjutkan commit `18fc46b8e315607b0630b73cb12fd764d85fe398` pada branch yang sama.

Judul Job Board diturunkan sedikit, area daftar diperluas sehingga dua kartu pertama terlihat utuh, dan kelompok saldo dipindah ke kanan bawah. Ringkasan permanen di bawah kartu disembunyikan; handle quote lama dipertahankan untuk kompatibilitas, sementara jumlah yang harus dibayar tetap terlihat pada panel konfirmasi. Feedback keberhasilan dan kesalahan tetap tersedia bila diperlukan.

Panel kontrak dipersempit, margin ditata, dan judul menggunakan ukuran 12. Back, Confirm, pilihan 3/6/9, serta penghapusan tooltip dan X yang selesai pada commit sebelumnya dipertahankan. Sumber saldo tetap `Inventory` pemain; tidak ada perubahan transaksi, durasi, produksi, atau posisi E.

Penggantian ikon kantong/loot dengan ikon “city gold” **belum dilakukan**. Kode City Management/City Storage yang diperiksa menampilkan kas kota sebagai teks, sedangkan HUD wallet memakai `small_shekel_8x8.png`; belum ditemukan aset yang secara pasti dapat diidentifikasi sebagai ikon yang dimaksud. Ikon lama dipertahankan sambil menunggu nama/lokasi aset atau referensi visualnya.

## Pengujian

Godot `4.5.1.stable.official.f62fdbde1`, profil XDG terisolasi, viewport logis 400 × 225 dan window 1200 × 675:

- `test_scene_content_prepaid_ui.tscn`: **PASS** headless dan rendered. Mencakup dua kartu utuh, ringkasan tersembunyi, saldo pribadi yang berbeda dari kas kota, saldo dan total besar, nama panjang, tujuh kandidat, fokus, Back/Escape, pembukaan berulang tanpa potongan, perubahan harga, saldo kurang, dan pembayaran batch tepat satu kali.
- `test_scene_prepaid_contracts.tscn` dan `population_employment_integration_test.tscn`: **PASS** headless.
- `test_scene_job_board_closed_feedback.tscn`: **PASS** headless pada 07:59, 08:00, 16:59, dan 17:00, termasuk E dan interaksi berulang.

Renderer X11/llvmpipe melaporkan bahwa perubahan V-Sync tidak didukung. Ini adalah fixture terkontrol, bukan playthrough manual atau uji platform lain.

## Bukti visual

Render viewport 400 × 225 diskalakan nearest-neighbor ke 1200 × 675:

- [Job Board sebelum](evidence/worker-contract-layout-2026-10-31/before-board.png) dan [sesudah](evidence/worker-contract-layout-2026-10-31/after-board.png).
- [Panel kontrak sebelum](evidence/worker-contract-layout-2026-10-31/before-contract.png) dan [sesudah](evidence/worker-contract-layout-2026-10-31/after-contract.png).
- [Panel dengan nama panjang](evidence/worker-contract-layout-2026-10-31/after-long-name.png).
