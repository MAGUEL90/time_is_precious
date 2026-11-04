# Integrasi logistik, worker, animasi dan kebutuhan — 2026-11-04

Status: **PARTIAL — NEEDS HUMAN REVIEW**. Semua hasil final tim sudah digabung
di branch integrasi cloud, tetapi perjalanan kebutuhan standar belum lulus karena
aturan hasil kerja Hourly dan kepemilikan barang kota memerlukan keputusan.

## Baseline dan penggabungan

- Branch lokal: `feature/gameplay/integration-worker-animations-20261104`.
- Baseline bersama: `13a6c0725a08c91bfcbc2606646e8ebf0f668968`.
- Commit final yang digabung: worker `7b78214144d1f9a65c1c5de41c5ee452dd032404`,
  animasi `9c196b92d1962a1f0858a46887d676508c47f3cc`, kebutuhan
  `dc24efb48def073e1be4a5d7891c6f18c2fc5e73`, dan logistik
  `c338c6c8a06be184a4b3edf66b8bd549e33bddd3`.
- Merge logistik `297329df4e4c51bec9886aed48de82447737a34e` mempunyai satu
  konflik teks di `test_scene_pickup_sources.gd`. Resolusi mempertahankan
  encoder legacy dari kedua sisi, komentar alasan, serta pemeriksaan dan
  penghentian aman bila persiapan migrasi gagal. Gabungan otomatis pada
  worker, animasi, player, merchant dan worksite telah ditinjau.
- Sesudah merge, perbaikan visual dan fixture serta tes tambahan dijalankan pada
  working tree yang sama. Laporan, dua GIF dan metadata UID hanya menambahkan
  bukti, bukan mengubah perilaku permainan.
- Checkout asal sudah kotor dan dibiarkan utuh. Pengujian memakai data Godot
  terisolasi. Tidak ada push dan laptop tidak diakses.

## Perbedaan Hourly yang masih terbuka

Produksi **Daily oleh worker** diterima langsung City Storage. Kerja **Hourly
oleh pemain** masih menaruh hasil di Inventory pribadi dan membuat pickup
pribadi untuk kelebihan yang tidak muat. City Storage mempertahankan aturan
sebelumnya: barang yang sudah menjadi milik kota tidak dapat ditarik ke
Inventory pemain. Konstruksi baru menggunakan Inventory pribadi.

Tes `PlayableNeedsJourney` dijalankan tanpa opsi worksite lama dan **FAIL** pada
assertion pertama yang meminta hasil Hourly masuk City Storage dengan tas tetap
kosong. Fase Continue tidak dijalankan setelah write gagal. Bila arahan “hasil
worksite” hanya dimaksudkan untuk produksi worker, tes tersebut perlu
diselaraskan dengan keputusan itu. Bila juga mencakup kerja pemain, diperlukan
keputusan tentang cara memperoleh material pribadi untuk konstruksi tanpa diam-
diam melanggar aturan kepemilikan City Storage. Tidak ada perubahan kepemilikan
atau pengalihan Hourly yang dibuat dalam integrasi ini.

## Hasil pengujian

Godot 4.5.2 stable, Linux cloud, profil XDG sekali pakai dan proses berurutan.
Editor import dan start-menu launch lulus. Run grafis memakai GL Compatibility,
Mesa llvmpipe, serta audio dummy; driver virtual memberi peringatan V-Sync.

| Area | Hasil dan cakupan |
| --- | --- |
| Produksi Daily dan save | `NoStockpileFlow` write/read/verify **PASS**: produksi worker masuk kota, lima item worksite lewat receipt, penolakan stock penuh, retry, migrasi v14 dan handoff rumah tanpa duplikasi. |
| Dua worker dan shift | `MultiWorkerNavigation` write/read/hire **PASS** (347/340/435 pemeriksaan). Tes baru `MultiWorkerCitySupply` write/read **PASS** (214/16): kedua worker menghasilkan ke kota, jumlah dan statistik dipulihkan persis pada proses baru, reload berulang aman, dan output berhenti pada akhir shift. Stok 1000 pada bagian shift adalah grant fixture agar stok tidak habis sebelum batas waktu. |
| Hauler antar-storage | `CityStorageTransportFlow` write/read dan `CityStorageTransportHomeContinue` write/read **PASS**: muatan, rute balik, pembatalan, tujuan penuh, resignation dan Continue. Tes baru `CityStorageTransportInterruption` **PASS**: hambatan baru menghentikan muatan di titik aman; setelah bebas rute berjalan lagi; muatan tetap utuh saat kontrak berakhir, save/load, perpanjangan setelah habis maupun perpanjangan kontrak aktif. Jam, dana, stok dan hambatan adalah setup fixture. |
| Konstruksi pribadi | `WorkshopConstruction`, `MultiHouseRuntime`, `DefenseImprovements`, `WallWork`, `StonePurchase`, `MudbrickProductionChainIntegration`, `MudbrickPlayerFlow` dan `FacilityContributionContinue` write/read **PASS**. Cakupan meliputi rumah, workshop, wall build/repair/upgrade, Watchtower, Drying Yard dan kontribusi/refund bertahap. |
| Kebutuhan dan merchant | `MultiDayNeedsJourney` write/read/verify, `CityFoodDaily`, `CityClothingNeeds`, `PopulationEmploymentIntegration`, `MerchantRandomRequests` dan `TravelingMerchant` **PASS**. Multi-day menggunakan bahan, dana dan pengaturan fixture; ini bukan perjalanan normal tanpa bantuan. Checkpoint merchant yang dibuat pada `13a6c07` juga lulus Continue di gabungan ini. |
| Save dan perlindungan | `ReviewDefaultSave` write/read/restart, `CitySleepSave`, `CityStorageOverflow`, `TimeTransactionGuard` dan `PickupSources` **PASS**. Warning checkpoint pada tes tidur dan panen adalah penolakan yang sengaja diuji untuk file rusak/interaksi aktif. |
| Navigasi, pause, scene, animasi | `ReviewResourcePaths`, `ContentActualArrival`, `WorksiteMidnightContinue` write/read, `InventoryModalPause`, `SceneTransitionTiming`, `CityResident`, `WorkerVisualLifecycle`, `WorkerCartAnimation`, `WorkerWorkAnimation`, `PalmGather` dan `WorldLifeAnimation` **PASS**. Dua animasi juga lulus run grafis dan menghasilkan 130 frame. |

## Regresi yang ditangani dan kegagalan baseline

Pembatalan angkutan semula mengembalikan barang dengan benar tetapi meninggalkan
label muatan pada visual worker yang sudah kosong. Label kini dibersihkan saat
worker kembali idle atau mendapat pekerjaan lain; tes baru membuktikan label
muncul ketika membawa barang dan hilang setelah pembatalan. Pengujian hauling,
dua worker, animasi dan lifecycle diulang setelah perbaikan.

`ContentActualArrival` semula gagal karena fixture melompatkan jam secara
langsung tanpa menyelaraskan cursor transport yang sedang kosong. Fixture kini
memastikan tidak ada rute aktif lalu menyinkronkan cursor; tes lulus. Dua driver
berjalan diperbarui agar menghitung setiap slot kurma yang benar-benar
terkumpul, karena satu interaksi sekarang dapat mengambil lebih dari satu buah.

Setelah pembaruan fixture tersebut, `FoodWalkingPlaytest` tetap **FAIL** di
`(111.6672, -109.402)` menuju `(112, -108)` dan `ContractJourney` tetap **FAIL**
di `(-103.8726, -64.34082)` menuju `(-112, -64)`. Keduanya diulang pada checkout
`7755168` sebelum logistik dengan **perubahan fixture yang sama** dan gagal pada
koordinat yang persis sama. Ini kegagalan baseline, bukan regresi logistik yang
terbukti; `ContractJourney` juga mengeluarkan warning ObjectDB saat keluar.
Pengujian berjalan kaki lengkap dan playthrough manusia belum dinyatakan lulus.

## Review visual dan keputusan lanjutan

- [Pohon kurma, 5 detik](evidence/full-integration-2026-11-04/palm-sway.gif)
- [Langkah warga, 8 detik](evidence/full-integration-2026-11-04/resident-footsteps.gif)

GIF direkam pada viewport logis 400×225; beberapa HUD, aktor dan papan termasuk
Annex disembunyikan hanya untuk capture agar animasi terlihat. Diperlukan
penilaian visual manusia; tidak ada klaim pengujian Windows atau Android.

Logistik saat ini mendukung satu pengiriman aktif; kurir mulai di storage asal
tanpa perjalanan dari posisi idle sebelumnya. Laborer idle ber-cart atau Hauler
legacy dapat menjadi kurir. Penawaran sementara merchant sebesar 12 Stone pada
2 Shekel per buah adalah pilihan balance dari branch logistik yang masih perlu
review Game Director. City Storage tidak memakai batas berat/slot sementara,
tetapi tetap menolak integer overflow.

Log dan profil uji sementara berada di
`/tmp/tip-full-integration-20261104-6eUFMf/` dalam sesi cloud ini.
