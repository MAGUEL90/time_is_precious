# Audit perjalanan MVP dari nol — 2026-10-18

Status: **PARTIAL untuk penerimaan MVP menyeluruh**. Perjalanan workshop dari nol
dan Continue otomatis PASS pada sampel yang dicatat; UX manusia dan akses
suplai untuk perkembangan kota/pertahanan belum memenuhi gate.

## Kontrak pekerjaan

- Repo `MAGUEL90/time_is_precious`, branch `test/gameplay/mvp-first-playthrough`.
- Baseline `d6ea244cf1a5be4a791977daa57e2806bdbdb134`; working tree baseline bersih.
  Checkout cloud bawaan semula `78779c4`; branch remote di-fetch dan di-switch
  sebelum perubahan. PR #114 (`78779c4`) dan #115 (`d6ea244`) diverifikasi dari Git.
- LEVEL 1: audit, dokumentasi, driver pengujian terisolasi dan perbaikan lifecycle merchant lokal. Tidak mengubah
  balance, ekonomi, aturan, sumber daya, filter City Storage atau jalur warehouse
  → workshop. Tidak memakai laptop, computer use, content/portrait-capture atau
  merekonstruksi edit belum di-push. Tidak merge atau force-push.
- AGENTS dan urutan kontrol 00–06 dibaca; ROADMAP, DEVLOG, bagian relevan
  ARCHITECTURE, game-concept/root-branch-map dan semua laporan yang diminta diperiksa.
  Root runtime tidak diganti menjadi Astra; tidak ada klaim pergantian model.
  Dua subagen Luna XHigh menangani rekonsiliasi dokumen dan regresi serial sesuai
  kebijakan delegasi AGENTS. Keputusan gameplay dan review akhir tetap oleh root.
- Engine resmi `4.5.1.stable.official.f62fdbde1`, Linux cloud headless. Godot bawaan
  4.6.3 tidak dipakai untuk hasil tes. XDG data/config/cache terisolasi di `/tmp`.

## Metode dan batas bukti

Driver `scenes/test_scenes/mvp_first_playthrough.tscn` membuka startup New Game,
berjalan menggunakan Input actions dan collision/pathfinding, memakai pickup/E,
Inventory Use, gathering Hourly 3h, Job Board, workshop dan merchant UI.
Waktu hidup normal; `--fixed-fps 60` mempercepat simulasi offline di host, bukan
mengubah rasio gerak, clock, kebutuhan atau durasi gameplay. Gathering dan tidur
memakai time skip produksi yang memang tersedia bagi pemain.

Tidak ada `Inventory.add_item`, pengisian uang/material/pekerja, reset kondisi,
forced merchant, seed RNG, manipulasi cuaca atau advance_minutes dalam driver.
Driver mengetahui lokasi authored dan memilih menu secara programatis; ini bukan
uji discoverability manusia. Setoran kurma memakai API transaksi City Storage
sesudah berjalan dan memeriksa akses fisik, sehingga belum membuktikan seluruh
UX setoran. Worker tetap linked ke warga dan kebutuhan harian tidak dinonaktifkan.
Dua applicant dan satu Cart city-owned merupakan startup produksi yang sudah
ada, bukan pemberian driver; Cart tidak otomatis dipasang dan rute ini belum
membuktikan onboarding Hauler dari nol.
Kebijakan rute adalah strategi uji, bukan resep optimal atau balance baru.

Regresi existing dipisahkan: modal UI, production chain, merchant accounting,
save economy dan worksite fixtures dapat menyuntik state atau supplies. PASS-nya
membuktikan kontrak sistem yang dituju, bukan perjalanan ekonomi normal.

## Checklist perjalanan pemain

| Langkah | Tindakan normal / bukti yang dicari | Hasil sesi ini |
| --- | --- | --- |
| New Game | Startup menu, inventory/wallet kosong, roster kosong | PASS: inventori/wallet/roster kosong |
| Makan/gathering | Berjalan ke kurma, E, Use; Wood/Clay/Reed/Straw/Water Hourly | PASS: sumber authored, makan dan suplai warga |
| Penjualan pertama | Merchant jadwal normal; hanya jual request aktif | PASS: Wood alami; waktu bergantung request |
| Perekrutan | Job Board → Workshop Laborer | PASS: applicant normal, tanpa worker fixture |
| Clearing | Pilih pekerja, 180 menit, tanpa material | PASS: assignment clearing normal |
| Construction | Inventory: 6 Wood + 12 Clay + 8 Reed; satu builder 3 hari | PASS: bahan gathering, durasi normal |
| Wet bricks | Deposit bahan; Shape (3 Clay + 3 Straw + 3 Water), bayar fee 5 | PASS: beberapa job; fee dibayar dari sales |
| Drying Yard | Level 1: 2 Wood + 4 Reed + 4 Clay | PASS: bahan hasil gathering |
| Dry bricks | Full batch 20 wet; Dry; bayar rent 2 | PASS: 2 × 20 bata kering |
| Penjualan/penggunaan | Withdraw, jual request; yard level 2 memakai 10 dry + 4 Wood + 6 Reed | PASS: jual bata + yard level 2 |
| Produksi berulang | Dua pengeringan tanpa reset resource/kondisi | PASS: tanpa reset kebutuhan/resource |
| Tidur/save | Rumah, E tidur, checkpoint setelah pemulihan | PASS: sleep checkpoint aktual |
| Tutup/Continue | Proses baru, snapshot checkpoint sama, kembali ke kota | PASS: snapshot sama, kembali kota dan upkeep |

## Audit ketersediaan dan hambatan desain

| Domain | Jalur saat ini | Batas yang perlu keputusan Game Director |
| --- | --- | --- |
| Bahan workshop | Lima worksite authored, manual output ke tas, deposit personal ke workshop | Kapasitas tas/stock tetap berlaku; tidak membuka jalur city→workshop |
| Shekel pertama | Wood request 3–6 × 2 Shekel, kunjungan hari 1 lalu tiap 3 hari (08–18) | Merchant dapat meminta hanya dry brick; waktu pendanaan tidak dijamin |
| Pendapatan bata | Dry brick request 10–20 × 3 Shekel | Stok, budget, kuota kunjungan terbatas; membeli kembali tidak memulihkan demand |
| Makanan warga | Kurma hasil panen disetor ke City Storage, 1 food point/date | Dua applicant normal sudah warga/consumer sebelum direkrut; bukan hanya worker |
| Pakaian warga | Storage menerima tujuh jenis garment jadi | Tidak ada source/offer/recipe normal yang menyediakan garment tersebut pada map ini |
| Shelter | Summary membaca CityStockManager.shelter_capacity | Awal 0; pemanggilan penambahan capacity hanya ditemukan dalam fixture, bukan tindakan gameplay normal |
| Pertahanan | Iddin-Sin Build: 10 Stone + 5 Wood dari City Storage | Wood tersedia; Stone tidak ada pada worksite/source/offer normal. Stone Hammer adalah tool, bukan Stone |
| City progression | +5 all-fed, +5 all-clothed, +5 satisfaction ≥70%, −5 missing wall | Dengan makanan saja, +5−5=0; pakaian/shelter tak terpenuhi menurunkan kondisi worker. Level-up kota belum terbukti dapat dicapai dari nol |

Sumber utama: `common_merchant.tres`, `main_map_worksites.tscn`,
`workshop_construction_state.gd`, `mudbrick_make.tres`, `drying_mudbrick.tres`,
`workshop_facility_manager.gd`, `city_tool_storage.gd`, `citizen_needs_manager.gd`,
`city_stock_manager.gd`, `city_progression_state.gd` dan authored ContentScene.
Ini klasifikasi ketersediaan/content dan keputusan desain, bukan izin untuk
menambah toko, pakaian, rumah, Stone atau mengubah kebutuhan.

## Risiko pemahaman dan keputusan berikutnya

- **Pendanaan / keputusan desain:** permintaan hanya bata pada kunjungan awal
  berarti pemain belum punya barang yang bisa dijual. Usulan untuk keputusan
  Game Director: tentukan apakah menunggu kunjungan Wood memang pacing yang
  diinginkan, atau perlu jaminan akses pendanaan pertama. Belum diubah.
- **UI / perlu pemain manusia:** yield wet brick dapat kurang dari batch drying
  20 karena kondisi worker; output masih ditahan sampai fee dibayar. Pemain perlu
  memahami akumulasi beberapa job, pembayaran dan kebutuhan ruang output.
  Driver berhasil memakai menu, tetapi pengetahuan rute dan resep sudah diberikan
  kepada driver; keterbacaan/discoverability belum terbukti.
- **Kapasitas / aturan existing:** menyetor surplus atau menarik seluruh bata
  menghalangi langkah berikutnya. Rute sukses menyetor bahan secukupnya,
  menyisakan ruang makanan dan memakai output untuk upgrade sebelum mengulang.
  Tidak ada usulan otomatis menaikkan capacity.
- **Content / keputusan desain:** pilih cakupan MVP untuk garment, shelter dan
  Stone. Bila city level-up/wall harus tersedia pada perjalanan awal, tentukan
  sumber/cara akses yang disetujui dahulu. Alternatifnya nyatakan secara eksplisit
  bahwa progres awal saat ini adalah workshop/yard, belum perkembangan kota dan
  persiapan wall dari nol. Tidak ada sumber atau rantai baru ditambahkan.

## Koreksi harness selama audit (bukan perbaikan balance)

Run awal sengaja tidak dihitung PASS: iterasi child YSort sempat membaca pickup
yang sudah di-free setelah panen; rencana navigasi lama tidak diperbarui setelah
geometri workshop dibangun; setoran seluruh surplus ditolak kapasitas storage;
dan withdrawal sampai tas penuh menutup ruang makanan. Driver diperbaiki untuk
memeriksa instance, merencanakan ulang collision, menyetor kebutuhan resep dan
menyisakan ruang makanan. Tidak ada kapasitas dinaikkan atau bahan ditambahkan.
Percobaan berikutnya mencapai satu siklus kering, tetapi start shaping berikutnya
ditolak karena ruang output belum cukup. Strategi kemudian memakai 10 bata untuk
upgrade yard sebelum produksi ulang, bukan memperbesar storage. Pesan validasi
start dipertahankan dan dicatat. Ini kegagalan strategi/asumsi otomasi, bukan bukti
bug produksi. Run gagal tetap dicatat terpisah dan tidak masuk hitungan PASS.

Review juga menambahkan gate eksplisit agar batas hari tanpa pendanaan/dua siklus/
penjualan/penggunaan output menghasilkan **PARTIAL exit 2**, bukan PASS palsu.
Snapshot read mempunyai counter driver baru; bukti produksinya selalu berasal
run write yang dipasangkan, sedangkan read menilai restore/kelanjutan tersendiri.

## Bug lokal yang diperbaiki

Run 6 mencapai dua pengeringan, penjualan dan upgrade dengan pendanaan normal,
namun **tidak dihitung PASS** karena saat masuk rumah muncul error
`Cannot call method get_first_node_in_group on a null value` pada
`traveling_merchant.gd::_bind_notification_ui`. View kota lama sudah keluar dari
SceneTree, tetapi ledger merchant yang persistent masih memanggil `_refresh`
melalui sinyal `changed` sebelum view di-free.

Perbaikan hanya memutus subscription ledger pada `_exit_tree`. Stok, budget,
request, timer, harga dan save format tidak berubah. Regression MerchantAccess
sekarang melepaskan kota, memajukan clock fixture saat view detached, memeriksa
subscription dilepas dan ledger transaksi tetap utuh, lalu reload. Uji sebelum
fix menghasilkan error yang sama + FAIL(1); sesudah fix PASS tanpa error.
Perjalanan normal setelah fix diuji ulang terpisah dari fixture reproduksi ini.

## Validasi dan bukti

### Perjalanan normal sesudah fix

| Ukuran | Run 7 | Run 8 |
| --- | --- | --- |
| Write / proses baru Continue | PASS / PASS, exit 0 | PASS / PASS, exit 0 |
| Pendanaan pertama | Hari 1: 6 wood → 12 Shekel | Hari 4: 5 wood → 10 Shekel |
| Request alami per kunjungan | H1 W6; H4 W5+B20; H7 W5+B12 | H1 B18; H4 W5; H7 W5; H10 W5; H13 W4+B17 |
| Job shaping / pengeringan | 3 / 2 | 3 / 2 |
| Bata kering diproduksi | 40 | 40 |
| Dipakai upgrade / dijual / tersimpan | 10 / 7 / 23 | 10 / 12 / 18 |
| Wet brick tersisa | 7 | 11 |
| Total wood dijual | 16 | 19 |
| Pemasukan / fee dibayar / saldo akhir | 53 / 19 / 34 Shekel | 74 / 19 / 55 Shekel |
| Kurma dipanen / dimakan / tidur | 300 / 274 / 6 | 531 / 490 / 10 |
| Checkpoint menit absolut | 11995 (H8 07:55) | 20668 (H14 08:28) |
| Worker satisfaction / reliability akhir | 0.10 / 0.60 | 0.01 / 0.30 |

W = wood request, B = dry brick request. Hari mengikuti counter game yang
berawal pada H0. Setiap kunjungan dicatat tanpa reroll; kedua sampel bukan bukti
statistik atas semua kemungkinan RNG. Run 8 menunggu penjualan bata sampai H13.
Run 2 yang dikecualikan bahkan mengamati H1 dan H4 hanya bata, baru Wood pada H7.
Tidak ada jaminan waktu tunggu maksimum dari dua sampel sukses.

`checkpoint-summary.json` mempertahankan encoding nilai checkpoint untuk field
yang relevan: kedua sampel berakhir city level 1/progress 0, settlement food +5
dan missing wall −5, shelter 0, wall unbuilt, yard level 2, collapse count 0.
Dengan demikian perkembangan yard terbukti, perkembangan kota belum tercapai.

Kedua write selesai dan proses berhenti sebelum read dimulai. Read membandingkan
seluruh payload checkpoint dengan snapshot saat Continue (termasuk inventory,
workshop, fee, worker/warga, clock, progression/raid dan pickup-source state),
lalu benar-benar keluar rumah, makan/panen/setor kurma di kota. Tidak ada offline
progress ditambahkan. Tidak mengklaim siklus produksi ketiga setelah Continue;
yang diuji ialah restore tepat dan kelanjutan aktivitas normal.

Empat invocation final mempunyai named PASS, exit 0, tanpa script/runtime error
atau leak diagnostics. Bukti terstruktur berada di
[`evidence/mvp-first-playthrough-2026-10-18/`](evidence/mvp-first-playthrough-2026-10-18/):
`journey7-write/read.json`, `journey8-write/read.json`,
`excluded-attempts.json`, serta log lifecycle red/green. File JSON menyimpan
pengukuran antara langkah dan katalog asli, bukan hanya ringkasan akhir.

Perintah reproduksi berada di `scenes/test_scenes/README.md`, bagian Normal-start
MVP journey. Audit memakai binary resmi 4.5.1, `--headless --fixed-fps 60`,
`--journey-phase=write` dengan data kosong lalu `--journey-phase=read` dalam proses
baru dengan data yang sama. Batas eksternal 600s write / 120s read. Driver tidak
mengubah production project settings atau main scene.

### Regresi fixture

Sweep awal: **45 dari 48 invocation PASS, 3 FAIL**, mencakup **39 scene suite
unik (36 PASS, 3 FAIL)**; mode write/read/Continue bukan suite unik. Named PASS, exit 0 dan tidak ada runtime/leak error diperlukan.
Suite fixture memiliki supply/debug setup sendiri; tidak digabung sebagai bukti
ekonomi dari nol. Hasil dan argumen setiap invocation ada dalam `regression.json`; perbandingan
baseline dan pengulangan home post-fix ada dalam `followups.json`, dengan log
terpilih pada `regression-logs/`. Invocation 1–27 berjalan sebelum fix merchant;
sweep lanjutan, uji merchant serta journey dan home recheck berjalan sesudah fix.

- PASS meliputi sumber pickup/palm, save values/file/roundtrip/economy, startup,
  inventory/modal, warehouse/supply/hauling, raid, progression ledger, resource
  worksites, merchant randomized/main-map/access, mudbrick chain/player/main-map
  dan wall-work ledger.
- **CityProgressionHub:** dua assertion ukuran/frame panel pada skenario padat
  attack + construction gagal. Pemeriksaan layout headless bukan visual acceptance;
  baseline `d6ea244` yang sudah di-import mereproduksi dua kegagalan yang sama
  (1.83s). Probe **hanya di /tmp**, menunggu tiga process frames sebelum early
  return headless pada capture helper, menghilangkan kegagalan frame tetapi
  assertion viewport tetap gagal (1.92s). Jadi ada pengaruh settling test dan
  masalah fit yang masih terbuka; bukan regresi dari fix merchant. Tidak ada
  perubahan helper/UI produksi untuk meloloskan assertion. Percobaan salinan
  sebelum import gagal setup/class cache dan tidak dihitung sebagai pembanding
  gameplay; hasil valid dilakukan ulang sesudah import.
- **CurrentMapFundedProduction:** fixture lama mengharapkan
  `YSortWorld/Worksites`, sedangkan map saat ini memakai WorkerRuntime. Gagal
  sebelum produksi, menghasilkan error berantai dan shutdown leaks. Tidak
  dihitung sebagai ekonomi normal maupun PASS. Entry point yang sesuai kini
  dijelaskan di test README; fixture tidak diberi supplies tambahan agar lolos.
- **WallBuild dialogue:** fixture yang mendeklarasikan alur caretaker gratis lama
  gagal pada greeting/response/interaksi berikutnya. WallWork ledger PASS tidak
  membuktikan dialog tersebut benar. Kegagalan disimpan, tidak dihapus atau
  dinyatakan sebagai sukses. Pertahanan dari nol tetap terhalang Stone.
- Percobaan awal CityProgression timeout 180s dan wrapper sementara mengalami
  kesalahan bytes/string saat merekam timeout. Wrapper `/tmp` diperbaiki;
  pengulangan non-verbose selesai PASS dalam <1s tanpa error/leak. Timeout awal
  tidak tereproduksi dan penyebabnya belum dipastikan. Run investigasi verbose
  juga mencetak diagnostik orphan StringName; tidak dipakai untuk klaim shutdown
  bersih. Catatan percobaan tetap disimpan terpisah.

Perbaikan merchant diuji dengan red/green reproduksi dan TravelingMerchantAccess
pada sweep, ditambah dua journey write/read bersih setelah fix. Tiga mode tambahan
post-fix sleep-write → startup home Continue → sleep-read dalam proses terpisah
juga PASS tanpa warning, error atau leak. Tidak ada klaim bahwa seluruh
48 invocation sweep lolos.

## Visual, manusia dan platform

Sesi ini headless: tidak ada klaim review visual, layout/clipping, kemudahan
memahami menu oleh pemain baru, pacing manusia, Windows, Android atau export.
Screenshot/visual laporan lama tetap bukti historis pada map/fixture masing-masing.
Konfirmasi pengguna atas manual save/Continue dan PickupSourcesTest di Windows
4.5.1 dicatat sebagai bukti eksternal PR #115, bukan hasil pengujian ulang sesi ini.
