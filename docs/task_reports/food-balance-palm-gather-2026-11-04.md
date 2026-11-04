# Food balance dan pengumpulan satu pohon — 2026-11-04

Tindak lanjut review `917a8d13fb58c838efbdd61063f4df1f3bdf79c4`. Peningkatan
nilai Date Cluster pada commit tersebut mengungguli Fresh Loaf per item: Belly
sama, Energy lebih besar, dan berat lebih kecil. Keputusan akhirnya adalah
**mengembalikan kedua efek kurma ke nilai asli**, sambil mengurangi tindakan
panen tanpa menambah buah atau mengubah harga dan ekonomi. Permintaan kayu yang
dijamin merchant tetap seperti yang dijelaskan di laporan grind sebelumnya.

| Per item | Date Cluster asli dan final | Fresh Loaf |
| --- | ---: | ---: |
| Belly | 4% | 10% |
| Energy | 1% | 1% |
| Berat | 0,1 | 0,3 |
| Poin makanan City Storage | 1 | 1 |

Nilai final ini mempertahankan keunggulan roti pada Belly per item. Namun tiga
cluster mempunyai berat total yang sama dengan satu roti, dengan jumlah 12%
Belly, 3% Energy dan tiga poin makanan warga. Jadi kurma tetap lebih unggul
per berat dan untuk stok warga; perbandingan ini tidak membuktikan seluruh
ekonomi makanan sudah seimbang. Nilai aktual dapat terpotong ketika meter
hampir penuh. Pemeriksaan kode belum menemukan perolehan Fresh Loaf dari peta
utama, merchant, atau produksi normal, sehingga keunggulan per item tersebut
belum berarti bahwa roti sudah tersedia dalam perjalanan New Game. Tidak ada
industri atau penawaran roti baru dalam perubahan ini.

## Interaksi yang dipilih

Menekan E pada satu buah kurma kini mengumpulkan hingga tiga buah **yang masih
tersedia pada pohon itu sendiri**, sejauh muat di tas. Pohon lain tidak ikut;
stok kosong atau yang tidak muat tetap berada dalam ledger yang sama. Setiap
buah tetap memakai transaksi Inventory dan slot/pengisian ulang aslinya;
tidak ada resource, slot, kapasitas, timer, RNG atau format save baru. Pemain
melihat satu popup dengan jumlah yang benar. Aksi ini sengaja mengumpulkan
semua buah yang muat dari pohon terpilih, termasuk buah di posisi lain yang
dekat pada pohon yang sama; pemain tidak lagi memilih hanya satu slot saat ada
ruang untuk lebih banyak. Ini keputusan aksesibilitas sementara yang perlu
dicoba manusia. Benda pickup lain tetap satu per interaksi.

Animasi mengunci gerakan sebelum perubahan Inventory, sehingga save yang dipicu
pengamat sinkron tidak menangkap transaksi setengah jalan. Guard pickup dan
pohon mencegah pemanggilan ulang menambah buah dua kali. Fixture memeriksa tas
penuh, tas yang muat dua, popup, pohon lain, refill, re-entry, save/load parsial
dan load berulang. Fixture juga memeriksa view yang masih muncul sesaat setelah
slot pada ledger dinyatakan habis, agar tidak menghasilkan buah tambahan, serta
E pada pickup biasa dan pickup stok lama yang hanya muat sebagian. Peringatan
checkpoint sibuk pada fixture itu memang disengaja. Fixture tersebut
membekukan waktu dan memakai pengaturan debug kebutuhan untuk mengisolasi
invariant pickup; pengukuran perjalanan di bawah menggunakan kebutuhan normal
tanpa debug.

## Pengukuran perjalanan

Godot 4.5.2 headless; driver membuka New Game, memakai E pada pickup, UI
merchant, penyimpanan, rumah, makan dan tidur. Ia memindahkan pemain langsung
ke jarak interaksi dan memajukan waktu menganggur. Deposit memanggil API yang
dipakai UI. Oleh karena itu angka berikut mengukur tindakan dalam strategi
driver, bukan waktu berjalan manusia atau bukti pemain menemukan jalurnya.
Output worksite pada branch ini masih mengikuti perilaku lama masuk tas; setiap
baris **hanya baseline sebelum integrasi logistik**.

| Skenario | Hari pulih | Buah diperoleh | Aksi panen | Catatan |
| --- | ---: | ---: | ---: | --- |
| Kurma asli, ambil satu per E; merchant 2 / food 1 | 6 | 242 | 242 | Baseline terkontrol: jaminan kayu sama, nilai makanan asli. |
| Kurma asli, satu pohon per E; merchant 2 / food 1 | 6 | 246 | 82 | Sekitar 66% lebih sedikit aksi; pembulatan ke isi pohon mengubah jumlah yang diambil. |
| Merchant 937 / food 2 | 6 | 246 | 82 | Pulih, save dan Continue lulus. |
| Merchant 20261004 / food 3 | 6 | 240 | 80 | Pulih, save dan Continue lulus. |
| Merchant 2 / food 1, lewatkan kunjungan hari 1 | 8 | 312 | 104 | Transaksi mulai kunjungan hari 4. |
| Merchant 2 / food 1, lewatkan hari 1, 4, 7 dan 10 | 23 | 888 | 296 | Warga mencapai 0%, lalu pulih; kasus sengaja terlambat tetap sangat panjang. |

Setiap sampel akhir memakai dua warga awal, menghasilkan pakaian dari jual
kayu dan pembelian normal, membangun shelter melalui 17 sesi kerja pemain,
menyetor makanan dan pakaian, mencapai Satisfaction 50% serta applicant aktif,
menyimpan lewat tidur, dan membuka Continue di proses Godot baru. Hunger
tertinggi tersampel sekitar 43,9% dan Fatigue 73% pada strategi ini; angka tidak
memasukkan biaya berjalan. Keterlambatan empat kunjungan bukan target waktu
yang dijanjikan atau bukti bahwa 296 aksi menyenangkan.

## Verifikasi dan batas integrasi

`test_scene_palm_gather.tscn` menguji efek makanan melalui Inventory UI nyata,
termasuk perbandingan 4/1 dan 10/1, beserta invariant pickup di atas. Tes
regresi terkait pickup, sumber, checkpoint, inventory, merchant dan kebutuhan
warga dijalankan terpisah. Tes `PickupSources` gagal pada commit `917a8d1`
sebelum revisi ini karena fixture versi 3 belum memakai encoder Reliability
legacy seperti `CitySaveTest`; fixture diperbaiki, lalu uji migrasinya lulus.
Perubahan ini tidak menyentuh encoder produksi. Checkpoint merchant yang
ditulis commit `13a6c07` dan checkpoint perjalanan dari `9eba1d2` berhasil
dibuka ulang pada revisi ini; ledger slot dan konfigurasi sumber tidak berubah.

**Belum ada pembuktian end-to-end aturan logistik baru pada branch ini.** Tes
perjalanan mode standar menuntut hasil worksite langsung masuk City Storage dan
tetap gagal sampai implementasi tim logistik digabung. Mode
`--allow-legacy-player-worksite` hanya berguna untuk perbandingan ekonomi di
atas. Setelah integrasi, jalankan ulang mode standar tanpa opsi tersebut, cek
pemain mengambil material bangunan dari City Storage, lalu uji akses/berjalan
dan UI dengan manusia. Perubahan `player.gd` dan `pickup_item.gd` perlu ditinjau
saat penggabungan karena juga mengatur pickup non-kurma.

Contoh pengulangan dengan slot `XDG_DATA_HOME` kosong dan terisolasi:

```sh
godot --headless --path . --fixed-fps 60 res://scenes/test_scenes/test_scene_palm_gather.tscn
godot --headless --path . --fixed-fps 60 res://scenes/test_scenes/test_scene_playable_needs_journey.tscn -- --journey-phase=write --allow-legacy-player-worksite --merchant-request-seed=2 --food-seed=1
godot --headless --path . --fixed-fps 60 res://scenes/test_scenes/test_scene_playable_needs_journey.tscn -- --journey-phase=read
```
