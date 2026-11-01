# Validasi alur kontrak pekerja — 31 Oktober 2026

Basis `4145e1f92566bcb3e93437b7108887a1c0bab0c7` dari branch polish; pekerjaan dilakukan pada `test/payroll-flow-validation-20261031`. Perubahan dibatasi pada driver tes, fixture output, dan laporan/bukti ini. Tidak ada perubahan tarif, sumber pembayaran, jadwal, kebutuhan, produksi, data save, atau aturan gameplay.

## Diagnosis fixture

- Fixture output lama mematikan perjalanan fisik pekerja. Setelah produksi mensyaratkan kedatangan fisik, hal itu membuat pekerja tidak pernah dianggap tiba: [hasil baseline](evidence/payroll-flow-validation-2026-10-31/baseline-output-fail.log) gagal 0/20. Fixture baru mempertahankan commute, menggerakkan visual native dalam langkah terkontrol, mencatat waktu kedatangan, lalu menghitung output dari kedatangan sampai shift berakhir. Ini fixture terkontrol dengan jam/stok/dana yang disiapkan dan kebutuhan pemain dinonaktifkan; bukan playthrough atau kesimpulan balance.
- Driver normal lama berjalan ke titik City Storage di luar area akses aktual. Karena itu ia gagal sebelum hire; pesan pintu rumah setelahnya adalah kegagalan berantai dari driver yang sudah berhenti ([log baseline](evidence/payroll-flow-validation-2026-10-31/baseline-journey-fail.log)). Driver baru berjalan ke papan dan melakukan deposit melalui UI. Probe awal berikutnya menemukan target keeper lama juga terhalang ([log](evidence/payroll-flow-validation-2026-10-31/normal-probe1.log)); validasi ini memakai penugasan Daily WoodSite, bukan menyimpulkan penyebab tabrakan keeper.

## Perjalanan normal: probe awal

Godot 4.5.1 Linux, profil XDG terisolasi, New Game kosong, kebutuhan aktif, tanpa grant, perubahan jam oleh driver, atau pengaturan ulang RNG merchant. Driver menggerakkan pemain dan mengirim input E/K serta sinyal tombol UI; ini automasi pada rute yang diketahui, bukan uji discoverability atau sesi manusia. `--fixed-fps 60` mempercepat eksekusi simulasi; skala waktu game dan kecepatan berjalan tidak diubah.

Pada probe awal, merchant hari 1 dan 4 hanya meminta bata, lalu pada hari 7 meminta kayu. Pemain menjual 6 kayu dan memperoleh 12 Shekel; hire mengurangi dompet 12→11 dan kas kota tetap 0. Laborer ditugaskan melalui UI Daily WoodSite, tiba, lalu menghasilkan pickup kayu. Kontrak tercatat habis hari 11 sekitar 07.00; pembatalan renew tidak mengurangi dompet dan konfirmasi menguranginya 11→10. Pekerja kembali menghasilkan kayu, lalu karakter tidur melalui kasur untuk menyimpan. Fase Continue pada proses terpisah memulihkan snapshot, kontrak, dompet, assignment dan statistik output. [Write](evidence/payroll-flow-validation-2026-10-31/normal-probe2-write-result.json), [read](evidence/payroll-flow-validation-2026-10-31/normal-probe2-read-result.json), [log write](evidence/payroll-flow-validation-2026-10-31/normal-probe2-write.log), [log read](evidence/payroll-flow-validation-2026-10-31/normal-probe2-read.log).

Probe tersebut masih memakai helper merchant lama yang memanggil beberapa handler secara langsung. Driver setelahnya diubah memakai tombol Sell, kartu barang, Max, Confirm, dan Back; hasil akhir driver yang dirapikan dicatat terpisah di bawah. Array `settlements` pada hasil probe adalah riwayat sinyal `payroll_changed` termasuk refresh rutin 07.00/08.00, bukan daftar transaksi; biaya dibuktikan dengan selisih dompet.

Capture dari Continue probe awal: [dunia](evidence/payroll-flow-validation-2026-10-31/normal-probe2-continued-city.png) dan [Worker Hub](evidence/payroll-flow-validation-2026-10-31/normal-probe2-continued-worker-hub.png). Keduanya merupakan viewport logis 400×225; window proses berukuran 1200×675. Renderer Compatibility/llvmpipe memberi peringatan VSync tidak didukung.

## Pengulangan driver akhir

**PASS write dan PASS read**, pada proses terpisah dan profil baru. Penjualan lewat tombol UI menghasilkan 8 Shekel dari 4 kayu; membuka lalu membatalkan hire tidak membayar atau merekrut, dan konfirmasi hire mengubah dompet 8→7. Penugasan UI menghasilkan pickup WoodSite. Setelah kontrak terdeteksi habis pada hari 5 pukul 12.12, selama 15 menit pengamatan di dalam shift output tidak bertambah. Membatalkan renew tidak mengubah saldo; konfirmasi mengubah dompet 7→6 sekali, dan output kumulatif kemudian bertambah lagi. Tidur melalui kasur menyimpan state dan Continue memulihkannya. Ini satu sampel acak, bukan pengujian semua kemungkinan.

Bukti: [hasil write](evidence/payroll-flow-validation-2026-10-31/normal-final-write-result.json), [log write](evidence/payroll-flow-validation-2026-10-31/normal-final-write.log), [hasil read](evidence/payroll-flow-validation-2026-10-31/normal-final-read-result.json), [log read](evidence/payroll-flow-validation-2026-10-31/normal-final-read.log). Capture aktual pada fase Continue: [dunia 400×225](evidence/payroll-flow-validation-2026-10-31/normal-final-continued-city-400.png), [Worker Hub 400×225](evidence/payroll-flow-validation-2026-10-31/normal-final-continued-hub-400.png), dan [window X11 1200×675](evidence/payroll-flow-validation-2026-10-31/normal-final-window-1200.png). Capture window diambil saat gameplay Continue berjalan dan bukan pembesaran file viewport.

## Regresi akhir

Seluruhnya dijalankan berurutan pada Godot 4.5.1 Linux dan profil XDG terisolasi; setiap proses exit 0 dengan penanda PASS dan tanpa ERROR. Peringatan VSync hanya muncul pada proses Continue bergambar yang disebut di atas.

| Tes | Hasil |
| --- | --- |
| Fixture output: lima worksite × empat waktu assignment | **PASS 20/20**, termasuk arrival, output, delta stok, dan batas menit kerja ([hasil](evidence/payroll-flow-validation-2026-10-31/fixture-output-results.json), [log](evidence/payroll-flow-validation-2026-10-31/regression-output.log)) |
| Kontrak prepaid dan UI Job Board | **PASS**, 0 pemeriksaan gagal ([prepaid](evidence/payroll-flow-validation-2026-10-31/regression-prepaid.log), [UI](evidence/payroll-flow-validation-2026-10-31/regression-prepaid_ui.log)) |
| Notifikasi kontrak/merchant/raid | **PASS**, termasuk acknowledgment dan ancaman raid aktif ([log](evidence/payroll-flow-validation-2026-10-31/regression-notifications.log)) |
| Save/Continue fixture | **PASS** untuk `write`, `read`, `readrenew`, `legacy-read`, `legacy-renew-read`, `assignment-write`, dan `assignment-read`; masing-masing memiliki log `regression-continue-*.log` di folder bukti |

Fixture output menggunakan stok dan jam yang disiapkan. Sebagai contoh, WaterSite berhenti mencatat 360 menit saat stok 72 unit habis meski masih ada waktu shift; pemeriksaan baru membandingkan menit aktual dengan batas lebih awal antara habisnya stok dan berakhirnya shift.

Untuk mengulang perjalanan akhir dari root proyek dengan Godot 4.5.1, gunakan folder XDG baru dan jalankan kedua fase secara berurutan, tanpa menghapus save pengguna:

```sh
export XDG_DATA_HOME=/tmp/tip-payroll-recheck/data
export XDG_CONFIG_HOME=/tmp/tip-payroll-recheck/config
export XDG_CACHE_HOME=/tmp/tip-payroll-recheck/cache
godot --headless --fixed-fps 60 --path . --audio-driver Dummy res://scenes/test_scenes/test_scene_contract_journey.tscn -- --journey-phase=write
godot --headless --fixed-fps 60 --path . --audio-driver Dummy res://scenes/test_scenes/test_scene_contract_journey.tscn -- --journey-phase=read
```

Karena permintaan merchant acak, lamanya fase write bervariasi. Untuk capture, fase read dapat dijalankan dengan display dan renderer Compatibility menggantikan `--headless`.

## Hal yang belum dibuktikan

Windows dan rasa bermain manual belum diuji. Permintaan merchant acak dan kebutuhan warga bisa menunda penghasilan awal; sampel ini tidak membuktikan balance semua profesi atau semua seed. Untuk backlog debu di bangunan selesai, inspeksi kode menemukan area emisi dan artwork dapat bertumpang tindih dengan z-index debu lebih tinggi, tetapi belum ada render yang membuktikan tampilan pada frame tertentu. Tanda seru merah belum dapat diidentifikasi dengan pasti dari deskripsi backlog; notifikasi kontrak/merchant/raid adalah alur tersendiri dan tidak disamakan otomatis dengan bug yang dilaporkan.
