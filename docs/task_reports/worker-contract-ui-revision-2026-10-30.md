# Revisi UI kontrak dan feedback Job Board — 30 Oktober 2026

Status: **PARTIAL — NEEDS HUMAN REVIEW**. Revisi dan pengujian terarah selesai; dua uji tambahan gagal juga pada baseline, sehingga perjalanan normal dan sampel output worksite belum tervalidasi. Branch `feature/ui/worker-contract-polish-20261030`, baseline bersih `7499dfee4d1dac51f64584ef81fad47317002e85`; `main` terverifikasi `126825ae840a153918b96ec06a10c02e11012129`. Pengerjaan memakai checkout cloud terpisah, tidak menyentuh checkout lama yang memiliki perubahan tidak terkait.

## Perubahan

- Hire membuka panel dengan nama kandidat, tombol 3/6/9 hari, dan harga sebelum konfirmasi. Kandidat yang sudah dipilih tetap dibeli sebagai satu transaksi batch melalui API yang ada. Back, Escape, menutup panel, dan memilih durasi tidak membayar. Konfirmasi memeriksa kembali nama, durasi, dan total; harga yang berubah harus ditinjau sebelum konfirmasi berikutnya.
- Label Wallet memakai ikon kantong dari atlas yang sudah ada, dengan ikon mata uang kecil. Harga kontrak dan perpanjangan memakai ikon Shekel dengan tooltip. Nama panjang dipersingkat hanya untuk tampilan; ID dan nama tersimpan tetap utuh. Feedback sisa waktu yang terus tampil di bawah dihapus; kesalahan dan keberhasilan tetap ditampilkan sesuai konteks.
- Menu Job Board tidak lagi menampilkan jam. Percobaan E di luar jadwal membuat satu label merah terpisah di atas papan dengan teks persis `akses job board jam 08.00 -17.00`. Label naik dua detik, shake singkat, turun dan memudar; E berulang memulai ulang satu animasi tanpa menumpuk label. Posisi papan dan prompt E tetap.
- Tidak ada perubahan harga, sumber pembayaran, durasi, shift, produksi, kebutuhan, kedatangan, profesi, save schema, plugin, viewport, atau project settings. Empat backlog gameplay yang disebut Game Director tidak dikerjakan.

## Hasil pengujian

Godot `4.5.1.stable.official.f62fdbde1`, profil XDG terisolasi, viewport logis `400×225`, window `1200×675`. Tes rendered memakai Compatibility/llvmpipe. Exit code dan log error diperiksa.

- **PASS:** `test_scene_content_prepaid_ui` rendered: pilihan kandidat dan batch, 3/6/9, nama panjang, focus keyboard tetap di panel, quote berubah, saldo kurang, Back/Escape, buka/tutup berulang, transaksi atomic dan konfirmasi ulang tanpa pembayaran kedua.
- **PASS:** `test_scene_job_board_closed_feedback` rendered pada peta asli: E dari player, 07:59 tertutup, 08:00 dan 16:59 terbuka, 17:00 tertutup; teks/warna, gerak naik-shake-turun, restart E, cleanup, serta posisi prompt dan papan. GIF di bawah diambil dari 45 frame viewport (15 fps dari simulasi 60 fps), ditampilkan dengan nearest-neighbor 800×450.
- **PASS:** `test_scene_worker_renew_currency` rendered: harga ikon di Manage dan konfirmasi, panel tetap dalam viewport, pembatalan, perubahan harga dengan konfirmasi ulang, pembayaran tepat sekali, serta konfirmasi Fire tanpa baris harga.
- **PASS:** `test_scene_prepaid_contracts`, `population_employment_integration_test`, `test_scene_contract_assignment`, `main_map_worker_hub_test`, `main_map_hauler_start_test`, `initial_workshop_start_test`, peluncuran proyek headless, dan import editor. Fixture Worker Hub dan Hauler diberi dana tepat untuk kontrak yang dipakainya; ini bukan perjalanan ekonomi normal.
- **PASS:** `test_scene_contract_continue` dalam tujuh proses berurutan: `write`, `read`, `readrenew`, `legacy-read`, `legacy-renew-read`, `assignment-write`, `assignment-read`.
- **GAGAL PADA BASELINE DAN HASIL REVISI:** `test_scene_contract_output_sample` menghasilkan 0/20 kasus pada kedua checkout. `test_scene_contract_journey --journey-phase=write` gagal dengan `Physical city stock access` dan `Normal home door` sebelum mencapai Job Board pada kedua checkout. Tidak diubah dalam tugas UI ini; fase Continue perjalanan normal tidak dijalankan. Ini bukan bukti bahwa produksi atau perjalanan normal lulus.
- Warning ObjectDB pada `ContractAssignmentTest` telah ada di baseline. Renderer melaporkan VSync tidak didukung. Tidak ada klaim uji Android atau review visual manusia.

## Bukti visual

Cuplikan viewport 400×225 yang diskalakan nearest-neighbor ke 1200×675; fixture kandidat/dana/jam dibuat khusus untuk pengujian:

- [Job Board sebelum](evidence/worker-contract-ui-revision-2026-10-30/before-job-board.png)
- [Job Board sesudah](evidence/worker-contract-ui-revision-2026-10-30/job-board.png)
- [Panel pilihan kontrak](evidence/worker-contract-ui-revision-2026-10-30/contract-panel.png)
- [Feedback di papan](evidence/worker-contract-ui-revision-2026-10-30/closed-feedback.png)
- [Animasi feedback](evidence/worker-contract-ui-revision-2026-10-30/closed-feedback.gif)
- [Konfirmasi perpanjangan](evidence/worker-contract-ui-revision-2026-10-30/renew-confirmation.png)

Upload ke Library gagal sebelum unggahan dimulai: layanan daftar tool Library tidak dapat dijangkau melalui jaringan lingkungan ini. Bukti di atas disertakan pada branch agar tetap dapat ditinjau. Tidak ada PR, merge ke main, force-push, atau deployment dalam tugas ini.
