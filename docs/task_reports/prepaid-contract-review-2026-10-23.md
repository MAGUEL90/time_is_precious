# Review otomatis kontrak pekerja — 23 Oktober 2026

Status: **PASSED — NEEDS HUMAN REVIEW** untuk matriks fungsi di bawah; balance final dan penilaian rasa bermain belum disahkan.

Baseline `965a814`, branch `feature/economy/prepaid-worker-contracts`, working tree awal bersih. Permintaan: membantu menguji alur selagi Game Director belum bisa standby. Pengerjaan cloud, Godot **4.5.1**, renderer Compatibility untuk screenshot. Tidak mengakses laptop, membuat PR, merge main, atau force-push. Scope LEVEL 1: fixture, koreksi ekspektasi teks tes, dan laporan; tidak mengubah harga, gameplay, save schema atau settings.

32 proses pengujian game lulus setelah dua koreksi pada tes, termasuk 20 kasus pengukuran output dalam satu proses. Import editor akhir lulus tanpa error script. [Ringkasan mesin](evidence/prepaid-contract-review-2026-10-23/review-summary.json).

## Hasil yang perlu dibaca dulu

- Hire langsung mengurangi dompet; kas kota tidak ikut terpotong. Assignment pada shift hari itu tidak perlu menunggu besok.
- Pilihan contract tidak memotong uang sebelum konfirmasi. Cancel renew mempertahankan saldo. Confirm memotong sekali dan menambahkan durasi; konfirmasi usang tidak membayar lagi.
- Batas kontrak baru 07.00, legacy 08.00. Expiry per pekerja; tanpa penagihan otomatis atau pembayaran kelompok. Renew setelah expiry tidak menghasilkan pekerjaan untuk waktu jeda.
- Save/Continue proses terpisah mempertahankan kontrak, saldo, assignment, progres, dan pemberitahuan yang telah dibaca. Pemecatan tanpa refund bertahan setelah Continue.
- Tiga perjalanan New Game berbeda dengan kebutuhan aktif lulus. Tidak ada grant, seed RNG, perubahan jam, teleport atau penghilangan kebutuhan dalam perjalanan ini. Driver mengetahui rute/interaksi: ini bukan uji apakah pemain baru mudah menemukan fitur.

## Matriks pengujian

| Kelompok | Kasus dan hasil |
| --- | --- |
| Kontrak | Durasi 3/6/9, profesi/tarif, cukup/kurang dana, kas kaya tetapi dompet kurang, immediate hire, paket invalid, batas hari, reentry: PASS |
| Perpanjangan | Aktif, expired, invalid ID/durasi, perubahan tarif, jeda kerja, satu pekerja tidak memblokir pekerja lain: PASS |
| Assignment | Sebelum 07.00, saat shift, setelah 15.00, nol output retroaktif, batas 480 menit saat reassign, Hauler hanya mengambil hasil sesudah assignment: PASS |
| Notifikasi | Expiring/expired/pending, nama panjang dan scroll, merchant arrival/departure, raid phase, ack, countdown tidak memicu event baru: PASS |
| Save/Continue fixture | Tujuh proses: write/read/readrenew/legacy-read/legacy-renew-read/assignment-write/assignment-read: PASS |
| UI dari save normal | Prepare, rendered capture, write, read; select tanpa biaya, cancel, confirm, duplikasi confirmation, tidur/kasur dan Continue: PASS |
| Pemecatan normal | Cancel, konfirmasi no refund, arsip XP, tidur dan Continue: PASS setelah ekspektasi teks lama diperbaiki |
| Regresi | Population/employment, rehire, raid UI, save values/file/economy, tim worksite, content worksites, Hauler delivery: PASS |

Fixture memakai setup uang/jam/worker eksplisit dan beberapa fixture menonaktifkan kebutuhan untuk isolasi. Uji normal menggunakan engine headless dengan `--fixed-fps 60`; jam game tetap maju melalui loop gameplay, bukan set-time dari driver. Semua proses diperiksa exit code, penanda PASS, dan pesan ERROR/SCRIPT ERROR. Log awal pemecatan yang gagal tetap disertakan untuk audit; runtime tidak diperbaiki karena perbedaannya hanya literal `Unused pay` vs `Unused payment` pada assertion tes. Setelah koreksi satu baris, kedua proses pemecatan bersih dan PASS. Renderer melaporkan VSync tidak didukung pada llvmpipe; tidak ada error script pada capture yang lulus. Dua fixture (`contract_assignment`, `worker_rehire_regression`) mengeluarkan warning `ObjectDB instances leaked at exit` sesudah PASS; warning teardown ini belum ditelusuri lebih jauh dan tidak dianggap bersih tanpa catatan. Import editor juga membuat ulang UID helper `mvp_first_playthrough.gd` dari cache; file hasil otomatis itu tidak dimasukkan ke perubahan.

## Tiga sampel perjalanan normal

| Sampel | Penjualan manual Wood | Pendapatan | Biaya hire 3 hari | Dompet sesudah hire | Clearing teramati | Continue |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 3 | 6 | 1 | 5 | 180 menit | PASS |
| 2 | 6 | 12 | 1 | 11 | 182 menit | PASS |
| 3 | 5 | 10 | 1 | 9 | 180 menit | PASS |

Selisih observasi clearing berasal dari titik pemeriksaan driver/aktivitas upkeep; bukan perubahan durasi design. Semua hire dan clearing berlangsung hari yang sama. Kebutuhan pemain aktif, worker satisfaction saat hire 0.45, dan kas kota tetap 0. Sampel 1 diteruskan untuk uji UI: perpanjangan 6 hari seharga 2 mengubah dompet 5→3; sisa masa lama tidak hilang. Lalu pekerja dipecat tanpa refund dan di-Continue.

Pendapatan di tabel berasal dari kerja/penjualan **pemain sebelum hire**, bukan laba yang dihasilkan worker. Tiga sampel ini menguji keterjangkauan kontrak awal dan alur normal; tidak membuktikan balance beberapa periode atau seluruh profesi.

## Output worksite terukur (fixture)

Fixture baru `test_scene_contract_output_sample.tscn` memuat scene content asli, membayar contract Laborer melalui API dompet, dan mengukur lima worksite pada empat jam assignment. **20/20 kasus PASS**. Ini fixture: jam ditempatkan eksplisit, dompet diberi biaya contract, stok di-reset ke kapasitas authored 72 antar-kasus, commute dan kebutuhan pemain dinonaktifkan. Tidak mengubah tarif, menit per unit, atau kapasitas runtime. Hasilnya diukur dari ledger dan selisih stok; bukan simulasi laba pemain.

| Worksite | Mulai 07.00 | Mulai 08.01 | Mulai 14.00 | Mulai 15.00 (hari itu) |
| --- | ---: | ---: | ---: | ---: |
| Clay | 48 | 41 | 6 | 0 |
| Wood | 24 | 20 | 3 | 0 |
| Reed | 64 | 55 | 8 | 0 |
| Straw | 48 | 41 | 6 | 0 |
| Water | 72 | 72 | 12 | 0 |

Satuan: unit barang. Mulai 08.01 memberi 419 menit shift tersisa; pukul 14.00 memberi 60 menit. Water sudah mencapai stok 72 setelah 360 menit kerja. Kasus 15.00 diuji lagi mulai besok 07.00: unit pertama muncul sesudah durasi unit worksite (Clay/Straw 10, Wood 20, Reed 8 menit diskret, Water 5). Tidak ada hasil retroaktif. Batas ledger 480 menit, stok nonnegatif, dan kesesuaian output/stok diperiksa.

Run pertama fixture gagal pada assertion metadata Clay: Clay mewarisi default stok schedule, sedangkan marker lainnya menyimpan 72 secara eksplisit. Assertion disesuaikan untuk membaca fallback yang benar, tanpa mengubah runtime atau mengendurkan batas 72. Run ulang bersih PASS; log awal juga disimpan. JSON lengkap: [output-sample.json](evidence/prepaid-contract-review-2026-10-23/output-sample.json).

## Temuan balance untuk review

1. **Durasi lebih panjang belum memberi diskon.** Laborer/Hauler/Scavenger 1/2/3 Shekel untuk 3/6/9 hari; Crafter/Farmer 2/4/6. Kontrak panjang memberi kemudahan tidak sering renew, tetapi mengikat kas lebih awal. Sisa hari pembelian juga termasuk sesuai keputusan sebelumnya.
2. **Pendapatan dibatasi pembeli.** Wood dihargai 2 Shekel, tetapi merchant meminta 3–6 unit bila permintaan Wood muncul; kunjungan tiap tiga hari, permintaan acak. Hasil produksi tidak otomatis bisa dijual semuanya. Barang perlu diambil/diangkut dahulu.
3. **Harga antarprofesi belum bisa disahkan.** Resource worksite memakai waktu tetap per unit tanpa multiplier profesi/satisfaction/reliability. Workshop memakai satisfaction dan reliability. Belum ditemukan keunggulan output runtime Crafter/Farmer yang membenarkan biaya dua kali lipat pada pekerjaan yang tersedia. Tarif tetap sementara, tidak saya ubah.
4. **Fee workshop masih signifikan.** Shape nominal 20 wet brick memerlukan 3 Clay+3 Straw+3 Water, durasi dasar 30 menit, fee 5 Shekel. Drying 20 wet→20 dry berbiaya 2. Output Shape dapat berkurang karena kondisi worker; jangan menyebut pendapatan kotor sebagai laba, atau menghapus fee berdasarkan murahnya contract. Regresi save-economy tetap menguji fee dan konservasi hasil.
5. **Jam worksite berbeda dari workshop saat ini.** Shift 07–15 berlaku pada daily resource worksites. Resep WorkManager tidak memakai pemeriksaan jam shift yang sama. Ini perilaku yang sudah ada dan tidak diubah; jika nantinya workshop juga harus tunduk ke shift, perlu keputusan desain terpisah.

Dasar angka: `worker_database.gd`, `clay_worksite_daily.gd`, `main_map_worksites.tscn`, `resource_site_marker.gd`, `common_merchant.tres`, `mudbrick_make.tres`, `drying_mudbrick.tres`. Audit baca kode dibantu agent Luna XHigh; hasil dan diff direview root. Bukti payroll tujuh hari lama tidak dihitung sebagai hasil kontrak baru.

## Screenshot untuk review nanti

Screenshot terbaru 400×225, diambil dari checkpoint perjalanan normal dengan renderer cloud:

- [Job Board — Contract](evidence/prepaid-contract-review-2026-10-23/job-board.png)
- [Worker Hub — renew](evidence/prepaid-contract-review-2026-10-23/worker-renew.png)
- [Konfirmasi biaya](evidence/prepaid-contract-review-2026-10-23/renew-confirmation.png)
- [Setelah renew](evidence/prepaid-contract-review-2026-10-23/renewed.png)
- [Notifikasi singkat — fixture dari pemeriksaan sebelumnya](evidence/prepaid-worker-contracts-2026-10-23/contract-notices.png)

Popover Manage berpindah sisi setelah refresh roster; masih bisa dipakai tetapi layak dirapikan saat review visual. Animasi commute masih memakai perhitungan menuju pukul 07.00; assignment terlambat dapat terlihat sudah di tengah perjalanan. Tidak ada klaim pengujian Android, discoverability manusia, atau semua regresi historis repository.

## Bukti dan reproduksi

Folder [evidence](evidence/prepaid-contract-review-2026-10-23/) berisi log setiap proses, JSON hasil tes, dan pengukuran normal. `suite-results.json` mencatat 21 proses awal; `ui-results.json` menyimpan fase UI dan kegagalan teks awal; `dismissal-results.json` mencatat retest yang lulus; `normal-samples-results.json` mencatat dua pasang sampel tambahan. Render capture dinilai dari `ui-capture.log` dan inspeksi gambar.

Perintah per scene mengikuti `scenes/test_scenes/README.md`. Gunakan folder XDG terpisah untuk setiap kelompok; fase Continue kelompok yang sama berbagi folder. UI review memakai salinan checkpoint earned `contract_journey/checkpoint.json` ke `contract_ui/checkpoint.json`, kemudian prepare/capture/write/read. Pemecatan memakai salinan hasil UI write ke `dismissal_journey/checkpoint.json`, kemudian write/read. Jangan memakai save pribadi.

Perubahan yang diperlukan: fixture pengukuran output beserta scene/UID, entrypoint README, assertion pemecatan (`Unused payment is not refunded.`), laporan, dan bukti. Tidak ada file dihapus/rename atau harga gameplay diganti. Final human review tetap diperlukan sebelum PR/merge.
