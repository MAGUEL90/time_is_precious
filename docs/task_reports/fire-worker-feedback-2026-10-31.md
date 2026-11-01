# Fire: visual worker dan alasan aksi nonaktif — 31 Oktober 2026

Status: **PASS — NEEDS HUMAN REVIEW**. Basis pengujian adalah commit `76a3c4648657d7b6a6885396e2aa1e73e0ae542a` pada branch `test/economy/payroll-worker-proceeds-20261031`. Pekerjaan ini memakai branch perbaikan terpisah; tidak ada perubahan harga, durasi, sumber pembayaran, refund, produksi, schema save, penalti satisfaction, atau aturan assignment.

## Perubahan

- Saat worker di-Fire, controller visual menghapus actor dan state presentasi milik worker tersebut. `CitizenActor` yang sah dan actor worker lain tetap dipertahankan. Cleanup juga terjadi saat game sedang paused, dan koneksi sinyal dilepas saat controller keluar.
- Jika Fire nonaktif, hover menampilkan alasan pendek berwarna merah dengan font 6 px di atas tombol. Alasan mengikuti guard yang sudah ada: bekerja, bepergian, perjalanan hauler, reservasi pekerjaan, atau assignment workshop. Kontrol hover tidak mengaktifkan tombol Fire; label hilang saat pointer keluar, panel ditutup, atau kontrol diperbarui.
- Fixture Worker Control diperbarui untuk mengukur apakah popup dan tombol benar-benar muat, mengikuti teks konfirmasi saat ini, dan menyediakan dana tes untuk hire/rehire. Harga dan perilaku pembayaran tidak diubah.

## Hasil pengujian

Semua pengujian menggunakan Godot 4.5.1 pada Linux dengan direktori data terisolasi. Render memakai viewport logical 400×225 dan window 1200×675. Bukti tersimpan di [direktori evidence](evidence/fire-worker-feedback-2026-10-31/).

| Pemeriksaan | Hasil |
| --- | --- |
| Peta utama: Fire worker idle, save lewat kasur, lalu Continue dalam proses terpisah | **PASS.** Worker diarsipkan, assignment harian dan visualnya hilang, actor warga serta worker dengan ID mirip tetap ada. Saldo wallet 6 dan 95 kayu yang sudah ada tetap sama. [Write/rehire](evidence/fire-worker-feedback-2026-10-31/main-fire-save-rehire.log), [Continue](evidence/fire-worker-feedback-2026-10-31/main-fire-continue.log). |
| Rehire sesudah Fire | **PASS untuk pembuatan actor baru.** Actor yang baru dibuat masih tersembunyi sebelum assignment, sesuai perilaku `ensure_actor`; tampilan otomatis setelah assignment baru tidak diuji pada probe ini. Fixture terpisah memastikan actor baru dapat ditampilkan. |
| Visual lifecycle | **PASS.** Menguji Fire ketika paused, cleanup state, `CitizenActor` dengan ID sama, worker lain dengan ID mirip, rehire, dan disconnect sinyal. [Log](evidence/fire-worker-feedback-2026-10-31/visual-lifecycle.log). |
| Hover Fire | **PASS.** Pointer X11 digerakkan ke tombol; diuji alasan, mouse keluar/masuk ulang, refresh status, tepi viewport, klik ketika disabled, serta alur No/Yes. No/Yes dipicu melalui sinyal tombol dalam fixture. [Log](evidence/fire-worker-feedback-2026-10-31/fire-hover.log). |
| Worker Control dan renew | **PASS.** [Worker Control](evidence/fire-worker-feedback-2026-10-31/worker-control.log), [renew](evidence/fire-worker-feedback-2026-10-31/worker-renew.log). |
| Kontrak prabayar dan rehire | **PASS.** Fixture prabayar meliputi debit, dana kurang, expiry, dan Fire tanpa refund. [Prepaid](evidence/fire-worker-feedback-2026-10-31/prepaid.log), [rehire](evidence/fire-worker-feedback-2026-10-31/worker-rehire.log). |
| Discard assignment workshop | **PASS pada basis sebelum perubahan Fire.** [Log](evidence/fire-worker-feedback-2026-10-31/workshop-discard.log). Perubahan Fire tidak menyentuh alur assignment. |

Reproduksi peta utama berawal dari checkpoint perjalanan payroll yang dibuat oleh tes sebelumnya, kemudian mengatur jam ke 15.05 agar worker dapat di-Fire dan sementara menonaktifkan kebutuhan player selama loncatan waktu. Probe menambahkan satu `CitizenActor` dan satu worker ber-ID mirip untuk memeriksa batas cleanup. Tombol UI dipicu oleh driver tes, bukan sesi manual. [Sebelum perbaikan, sesudah Fire](evidence/fire-worker-feedback-2026-10-31/before-fix-after-fire.png); [sesudah perbaikan, sebelum Fire](evidence/fire-worker-feedback-2026-10-31/after-fix-before-fire.png); [sesudah perbaikan dan Fire](evidence/fire-worker-feedback-2026-10-31/after-fix-after-fire.png); [setelah Continue](evidence/fire-worker-feedback-2026-10-31/after-fix-after-continue.png); [contoh hover](evidence/fire-worker-feedback-2026-10-31/fire-disabled-hover.png). Screenshot lama dan baru tidak identik secara pixel karena probe baru menambahkan actor pembanding.

Pada renderer llvmpipe, Godot melaporkan VSync tidak dapat diubah. Run peta utama fase write juga melaporkan kegagalan perangkat ALSA sebelum fallback ke audio dummy; pengujian tetap selesai. Fixture rehire mengeluarkan warning ObjectDB saat keluar yang juga tercatat pada pengujian sebelumnya. Windows, Android, sesi manual manusia, dan UI konstruksi lama tidak diuji pada perubahan ini.

## Catatan assignment

Pada Build/Clear Workshop, Back dari picker worker kembali ke form dan mempertahankan pilihan selama form induk masih terbuka. Menutup atau membatalkan form induk membuang pilihan yang belum dimulai. Build/Clear yang sudah dimulai tidak batal hanya karena panel ditutup.

Pada Assign Work di workshop yang sudah jadi, memilih worker membentuk assignment sementara. Keluar dengan **Discard** melepas draft yang belum dimulai; **Keep** mempertahankannya. Setelah **Start** membuat work order, menutup panel tidak otomatis membatalkan order yang sudah berjalan. Tidak ada aturan ini yang diubah dalam pekerjaan Fire.
