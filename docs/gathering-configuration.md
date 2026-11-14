# Pengaturan gathering

Tahap 14 November 2026 hanya merapikan sumber konfigurasi; nilai balancing tetap.
Ini panduan teknis, bukan persetujuan untuk mengubah aturan permainan.

## Durasi dan stok

`scenes/content_scene/worksites/gathering_config.gd` menjadi sumber bersama:

| Pengaturan | Nilai saat ini | Pengguna |
| --- | --- | --- |
| `HOURLY_DURATIONS` | `[180, 360, 540]` menit | Pilihan kerja player, validasi sesi, label tombol dan konfirmasi |
| `DEFAULT_MINUTES_PER_UNIT` | 10 | Fallback sesi clay/marker tanpa override |
| `DEFAULT_STOCK` | 72 | Fallback fixture lama; bukan kapasitas deposit scene awal |
| `RESOURCE_CAPACITY` | clay 36, wood 24, reed 40, water 48 | Deposit finite saat inisialisasi dan pengisian ulang |
| `RESPAWN_MIN_MINUTES` / `RESPAWN_MAX_MINUTES` | 2880 / 4320 | Rentang jeda respawn yang sudah berlaku |

Durasi harus tidak kosong, positif, unik, dan berurutan. Satuan menit game.
Contoh perubahan yang **belum diterapkan**: `[60, 120, 180]` untuk 1/2/3 jam.
Menu dan validasi otomatis membaca daftar yang sama. Label tersimpan pada scene
UI hanya tampilan awal editor; runtime menggantinya dari konfigurasi.
Jumlah tombol mengikuti daftar, tetapi perubahan jumlah/panjang label tetap
memerlukan pemeriksaan visual agar muat pada viewport 400x225.

## Kecepatan hasil per sumber

Override per lokasi tetap pada `WorksiteMarkers` dalam
`scenes/content_scene/worksites/main_map_worksites.tscn`:

- `WoodSite` sampai `WoodSiteE`: `minutes_per_unit = 20`.
- `ReedSite`: `minutes_per_unit = 7.5`.
- `ClaySiteA/B`: memakai fallback 10 dari konfigurasi bersama.

Marker dengan script `resource_site_marker.gd` menampilkan `minutes_per_unit`
di Inspector Godot. Nilai marker mengalahkan fallback; duplikasi lokasi tidak
otomatis mengikuti perubahan override lokasi lain. Jangan mengubah posisi atau
marker visual `new_map_authoring` untuk mengubah hasil kerja.

Nilai ini adalah menit produktif untuk satu barang, bukan jaminan jumlah hasil
per sesi. Energi player memengaruhi produktivitas; stok dapat habis dan fatigue
dapat menghentikan kerja lebih awal. Formula tidak diubah dalam tahap ini.
Kecepatan sumber juga digunakan worker Daily, jadi perubahan bukan khusus player.
Tas penuh tetap mengirim hasil selesai ke tanah; kapasitas/bobot item terpisah.
Mengubah durasi gathering tidak mengubah durasi sesi konstruksi atau timer Nightmare.

## Save dan pengujian

Konfigurasi bukan data progres dan tidak menambahkan field atau versi save.
Jangan mengisi ulang stok atau mengganti deadline respawn hanya karena Continue.
Perubahan nilai di masa depan perlu meninjau save yang memuat progres worker,
kapasitas deposit atau deadline lama. Terutama, progres worker divalidasi terhadap
`minutes_per_unit`; memperkecil nilai dapat membuat progres lama tidak valid.

Sebelum perubahan angka: catat baseline, gunakan profil QA baru/salinan save,
dan uji UI -> preview -> eksekusi, hasil tas/tanah, stok, waktu, pingsan bila relevan,
tidur serta Continue. Assertion konservasi barang dan batas tas harus tetap berlaku
walaupun angka output berubah. Helper QA lama yang masih menggunakan durasi tetap
perlu diperiksa saat durasi benar-benar diganti; tahap ini tidak menulis ulang semua
tes historis.
