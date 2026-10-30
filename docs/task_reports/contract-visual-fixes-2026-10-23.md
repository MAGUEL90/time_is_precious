# Visual kontrak: Manage dan perjalanan assignment terlambat

Baseline `d536851`, branch `feature/economy/prepaid-worker-contracts`, working tree awal bersih. Permintaan Game Director: rapikan dua temuan visual tanpa perubahan aturan kontrak/tarif. Status **PASSED — NEEDS HUMAN REVIEW** setelah pengujian di cloud Godot 4.5.1. Tidak ada akses laptop, PR, merge main, force-push, atau perubahan settings/plugins.

## Perubahan

- Manage sebelumnya menghitung posisi dari tombol roster yang baru dibuat tetapi belum selesai layout. Reposition sekarang menunggu layout, mencari ulang tombol pekerja yang aktif, dan mengabaikan permintaan bila popup sudah ditutup. Ukuran frame memperhitungkan isi agar tombol Renew tetap di dalam frame setelah feedback berubah.
- Rute visual baru tidak lagi memiliki waktu berangkat sebelum rute itu dibuat. Assignment terlambat berangkat dari spawn atau posisi actor yang terlihat, lalu bergerak ke lokasi kerja. Assignment cukup pagi tetap menargetkan kedatangan pukul 07.00.
- Cache rute terikat pada instance catatan assignment pekerja. Withdraw/reassign membuat rute baru dari posisi terakhir, termasuk ketika anggota tim lain masih mempertahankan job yang sama.
- Uji Continue menemukan validator lama hanya mengizinkan arrival tepat pukul 07.00. Validator sekarang menerima arrival pada/setelah 07.00 dengan pemeriksaan tipe, batas angka, posisi, dan urutan start≤arrival yang sudah ada. Saat restore, identitas rute disambungkan kembali ke assignment agar perjalanan tidak dimulai ulang.

Schema save tetap 7; bentuk empat field rute persisten tidak berubah. Identitas assignment hanya runtime dan tidak ditulis ke disk. Save lama tetap dapat dibaca; kode sebelum perbaikan ini belum mendukung timestamp arrival terlambat yang baru. Tidak ada perubahan saldo, harga, durasi contract, shift, ledger produksi atau formula output.

**Batas yang disengaja:** animasi perjalanan bersifat presentasi; produksi tetap dimulai pada menit assignment selama shift 07–15 sesuai keputusan sebelumnya. Pekerja yang terlambat dapat terlihat berjalan sementara ledger kerja sudah bertambah. Menjadikan perjalanan sebagai penundaan produksi memerlukan keputusan gameplay berbeda dan tidak dilakukan di sini.

## Pengujian

- Fixture `test_scene_late_commute_visual`: 3 skenario, 44 pemeriksaan, PASS. Assignment 06.00 tetap arrival07.00; 06.59/12.00 berangkat dari origin saat ini, bergerak antar-frame, tidak teleport, tiba di target; midshift tetap mendapat satu menit kerja setelah satu menit; reassign menggunakan posisi terbaru. Fixture memakai worker paid eksplisit tanpa citizen, kebutuhan pemain dinonaktifkan, clock/fraction visual dikendalikan.
- UI dari salinan save perjalanan earned dengan kebutuhan aktif: rendered capture, konfirmasi/cancel/renew, posisi popover sebelum/sesudah sama, tombol Renew di dalam frame. Write lewat kasur dan Continue proses terpisah PASS.
- Continue kontrak/legacy serta assignment-write/read: PASS. Read assignment memeriksa exact snapshot, progres tiga menit, dan rute start/arrival/origin/target tetap setelah dipanggil kembali.
- Core prepaid contract, assignment, output sample 20 kasus, save-values/file: PASS. Output resource dan tarif tidak berubah.
- Import editor terakhir diperiksa untuk parse/script errors. Render memakai Compatibility/llvmpipe; warning VSync unsupported tetap ada. Fixture assignment masih mengeluarkan warning ObjectDB saat keluar seperti pengujian sebelumnya.

Satu kegagalan awal yang nyata adalah `Invalid worker commute arrival time` pada save assignment setelah perubahan visual. Log awal disimpan; setelah validator dan restore disesuaikan, assignment-write/read diulang dan PASS. Tidak menonaktifkan validasi save untuk melewatkan uji.

## Bukti

- [Manage sebelum renew](evidence/contract-visual-fixes-2026-10-23/worker-renew.png)
- [Manage sesudah renew](evidence/contract-visual-fixes-2026-10-23/renewed.png)
- [Hasil pemeriksaan posisi/animasi](evidence/contract-visual-fixes-2026-10-23/late-final.log)
- [Continue rute dan progres](evidence/contract-visual-fixes-2026-10-23/continue-assignment-read.log)
- [Log awal validator](evidence/contract-visual-fixes-2026-10-23/continue-assignment-write-initial.log)

Runtime diubah terbatas pada WorkerControl UI, pembentukan rute pada shared worksite script, dan validasi/restore commute di CitySaveWorksites. Tes baru beserta UID/scene, dua driver regresi, README, laporan dan bukti turut diperbarui. Tidak ada file dihapus atau rename. Rumah/satisfaction, tarif final, City Storage filter, akses warehouse→workshop dan fee tidak disentuh.
