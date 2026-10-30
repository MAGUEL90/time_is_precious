# Payroll tahap 1 — tarif sementara dan perjalanan normal

Tanggal: 2026-10-22 (Asia/Jakarta). Baseline bersih `f378620`, branch
`feature/economy/worker-payroll-onboarding`, draft PR #116. Cloud saja,
Godot resmi 4.5.1; tidak mengakses laptop/computer use.

## Otorisasi dan scope

Pengguna menyetujui tabel tarif sementara untuk pengujian, serta meminta screenshot
jika perlu review UI. Tabel produksi kini Laborer/Hauler/Scavenger 1 Shekel dan
Crafter/Farmer 2 Shekel per tujuh hari. Ini harga uji, **bukan balance final**.
Profesi NONE/tidak terdaftar tetap ditolak. Tidak ada autoload/dependency baru di
repository atau perubahan fee, kebutuhan, filter City Storage maupun akses
warehouse → workshop. Perubahan produksi hanya tabel tarif; pekerjaan lain adalah
driver pengujian, bukti dan dokumentasi.

Ini tetap tahap pembayaran pertama. Expiry/renewal dan jeda/resume produksi aktif
belum diimplementasikan; tanggal paid-until bukan bukti perpanjangan otomatis.
Tidak memvalidasi hari setelah periode pertama berakhir. PR tetap draft.

## Metode perjalanan normal

Driver `test_scene_payroll_first_playthrough` memakai navigation, Input actions,
food upkeep, gathering, merchant dan home helper dari audit MVP. Rute baru memakai
Job Board UI untuk setoran eksplisit dan perekrutan, menunggu pembayaran pertama,
memilih assignment clearing melalui UI workshop, tidur lalu Continue proses baru.

Mulai dari New Game dengan tas/dompet/kas/roster kosong. Tidak ada grant uang,
material atau pekerja, override harga, forced request/seed/cuaca, pengubahan clock,
kapasitas, kecepatan atau bypass kondisi. Kebutuhan player dan warga tetap aktif.
`--fixed-fps 60` mempercepat eksekusi offline, bukan durasi dunia/gerak. Pilihan
rute mengetahui lokasi authored, sehingga bukan uji discoverability manusia.
Setoran makanan memakai transaksi City Storage setelah berjalan ke area yang benar
(seperti audit sebelumnya); tidak mengklaim seluruh interaksi supply UI diuji.

Checkpoint ditulis oleh bed sebenarnya, bukan dibuat driver. Continue membandingkan
seluruh snapshot owner dengan checkpoint sebelum clock maju; lalu pemain keluar
rumah, makan/panen dan memasok kebutuhan secara normal. Read memiliki counter
pengujian baru, sehingga earned/deposited nol pada read bukan rollback saldo.

## Sampel pertama

- Kunjungan hari 1 hanya meminta dry bricks, sehingga tidak ada penjualan awal.
- Hari 4: merchant normal membeli 3 Wood seharga 6 Shekel.
- Hari 4 sekitar 08:18: UI menyetor 1 Shekel; hire Laborer tercatat pending mulai
  hari 5. Kas masih 1, dompet 5; hire tidak menagih segera.
- Hari 5: pembayaran pertama 1 Shekel, periode hari 5–11; kas menjadi 0.
  Driver mengamati sesudah upkeep, bukan mengklaim timestamp observasi sama dengan
  boundary pembayaran. Sampel berikutnya menambahkan observer sinyal read-only.
- Worker berbayar menyelesaikan clearing 180 menit melalui assignment normal.
- Checkpoint rumah hari 6 07:07: dompet 5, kas 0, paid days 5–11, needs aktif.
- Write dan Continue proses baru keduanya PASS, exit 0, tanpa runtime error/leak.
  Setelah Continue pemain kembali ke kota dan melanjutkan upkeep.

Pakaian/shelter tetap tidak tersedia pada map awal; worker satisfaction turun
sampai 0.20 dan reliability 0.70 pada checkpoint, tidak di-reset agar tes lolos.
Menunggu permintaan Wood merupakan variasi merchant existing; satu sampel tidak
membuktikan distribusi RNG atau batas maksimal waktu pendanaan.

## Sampel kedua dan regresi final

Driver final menambahkan observer sinyal payroll yang hanya mencatat state, tanpa
mengubah saldo/waktu. Pendanaan alami kali ini lebih cepat: hari 1 menjual 4 Wood
seharga 8 Shekel; deposit 1 dan hire sekitar 08:57. Bed menghasilkan checkpoint
pending pada hari 2 pukul 07:53. Observer mencatat tepat **hari 2 pukul 08:00**
(menit absolut 3360), satu pembayaran 1 Shekel, kas 0, paid days 2–8. Tidak ada
attempt/potongan kedua. Worker menyelesaikan clearing; checkpoint paid terakhir
hari 3 pukul 07:49 dengan dompet 7, kas 0, satisfaction 0.35/reliability 0.85.

Write/read driver final keduanya PASS dan fixture atomik yang ada diuji ulang PASS.
Total sesi ini **dua pasangan normal write/read dan satu fixture PASS**, semuanya
exit 0 tanpa runtime error/leak. Sampel pertama mendahului penambahan observer
read-only; sampel kedua memakai file driver final. Callback exact 08:00 divalidasi
pada sampel kedua, bukan disimpulkan dari waktu observasi UI sampel pertama.
Tidak ada klaim semua kemungkinan merchant atau balance ekonomi kota tervalidasi.

## Bukti dan reproduksi

Folder `evidence/worker-payroll-normal-start-2026-10-22/` menyimpan log dan JSON
hasil. Jalankan dengan XDG data/config/cache terisolasi, kosong sebelum write,
dan sama untuk proses read:

```sh
godot --headless --fixed-fps 60 --path . scenes/test_scenes/test_scene_payroll_first_playthrough.tscn -- --journey-phase=write
godot --headless --fixed-fps 60 --path . scenes/test_scenes/test_scene_payroll_first_playthrough.tscn -- --journey-phase=read
```

Batas 600s write / 120s read. Tanpa pendanaan sebelum batas hari, atau tanpa
pembayaran/assignment/checkpoint, driver mengembalikan PARTIAL (exit 2), bukan PASS.

## Screenshot untuk review manusia

Dua PNG asli pada folder bukti di-render oleh Godot 4.5.1 GL Compatibility/llvmpipe,
display Xvfb cloud 1200×675. PNG adalah capture viewport logis 400×225 tanpa edit
atau upscale. Xvfb/dependency hanya di /tmp, tidak ditambahkan ke repository.
Subagen Luna XHigh menyiapkan fixture visual sementara; root memeriksa kedua PNG.
Script/scene capture sementara sudah dihapus, bukan bagian perubahan produksi.

- `fixture-funded-selected-hire.png`: kas 1, calon Laborer tarif 1, kekurangan 0.
- `fixture-pending-group-shortfall.png`: tiga worker sudah pending, kas 2, calon
  Crafter dipilih; proyeksi jika merekrut menjadi total 5 untuk empat worker,
  kekurangan 3. Angka ini adalah fixture UI, bukan uang perjalanan normal.

Window, deposit dan Hire/Close terlihat muat. Nama panjang di daftar memakai
ellipsis; lima kandidat menampilkan empat baris penuh dan sebagian baris kelima,
dengan scrollbar. Penilaian manusia yang diminta: apakah pemisahan dompet/kas,
jumlah yang disetor, serta total/kekurangan **termasuk calon terpilih** cukup jelas.
Tidak mengklaim persetujuan UI pengguna atau validasi Windows/Android.

## Review akhir

Perubahan runtime hanya tabel tarif sementara yang disetujui. Driver normal baru
beserta UID, petunjuk, laporan dan bukti ditambahkan; tidak mengubah produksi,
fee atau kebutuhan untuk meloloskan rute. Import editor final exit 0 tanpa parse
error; satu warning UID driver MVP lama yang belum tracked berasal dari cache.
Perubahan otomatis addon/project import dipulihkan, tidak masuk commit.
`git diff --check` diperiksa. Tidak merge main atau force-push.
