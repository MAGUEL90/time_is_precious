# Sumber pickup bersama — 2026-10-18

Status: PASSED — NEEDS HUMAN REVIEW. Belum di-merge.

## Tujuan dan otorisasi

User menyetujui penerapan perilaku sumber pickup yang bisa digunakan ulang untuk
kurma, apel atau sumber sejenis, lalu meminta hasilnya dilaporkan. Pekerjaan cloud
melanjutkan branch `fix/save-load/date-palm-persistence`, baseline bersih
`1ae99c828660a8173e57036db6829fd2f68167a0`. Risiko LEVEL 3: refactor sumber pickup
dan kompatibilitas save yang secara eksplisit termasuk tugas. Tidak memakai laptop,
computer use, atau edit belum di-push. Aturan repo/control pack yang sudah dibaca
pada sesi ini tetap berlaku. Subagen Luna XHigh memperbarui tiga fixture save/menu;
root menangani arsitektur, produksi, fixture sumber generik dan review akhir.

## Hasil implementasi

- `pickup_source.gd` adalah komponen Node2D bersama, juga bisa dipasang pada Sprite2D.
  Export mengatur item, jumlah per pickup, kapasitas/posisi slot, tekstur, refill
  aktif/nonaktif, rentang jam refill dan opsional `persistence_id`.
- `pickup_source_state.gd` memiliki bitmap slot, timer menit dan RNG independen.
  Tanpa refill, slot yang dipanen tetap kosong. Dengan refill, aturan yang sama
  seperti kurma berlaku: panen pertama mengundi timer; saat timer selesai semua
  slot kembali penuh. Panen berikutnya tidak mereset timer yang sedang berjalan.
- `date_palm_spawner.gd` dan `date_palm_state.gd` tetap ada sebagai wrapper kompatibel.
  Item kurma, quantity 1, kapasitas 3, rentang 1–18 jam, nama pickup, group debug,
  path node dan identitas `DatePalm_<hash>` dipertahankan. Tidak menambah apel
  atau mengubah content, layout, ekonomi maupun balance.
- Semua view dari sumber memakai group `source_pickups`. CitySave mengecualikannya
  dari barang jatuhan pribadi. `PickUpItem` tetap menangani pengambilan ke Inventory;
  tidak ada implementasi interaksi baru per jenis sumber.
- Ledger mendaftarkan diri pada `pickup_source_states` dan tetap hidup di
  WorkStateRuntime saat map unload. Adapter checkpoint mengambil sumber terdaftar
  milik scene kota, termasuk ketika pemain berada di rumah. Tidak ada lagi daftar
  enam pohon pada penulis checkpoint aktif.
- Dua instance prefab yang sama mendapat identitas dari path masing-masing di
  scene pemiliknya. `persistence_id` opsional bisa menjaga identitas saat node
  dipindah/diubah namanya; nilainya harus unik dalam scene. Duplikasi identitas
  aktif dan konfigurasi yang berubah saat sesi ditolak, bukan berbagi stok diam-diam.

## Kompatibilitas

Schema v4 memakai `pickup_sources`, setiap record berisi `available`,
`remaining_minutes`, `rng` dan `config`. Config tidak diterapkan dari file;
validator membandingkannya dengan konfigurasi authored, termasuk tipe nilainya.
Set identitas, kapasitas, slot boolean, timer, aturan one-shot/refill dan RNG
semua divalidasi sebelum owner mana pun dimutasi. Integer RNG tetap lossless.
Tidak ada progres offline, pengundian baru saat load, atau penambahan Inventory.

- v1/v2: sumber belum pernah disimpan; semua sumber terdaftar mendapat stok awal
  penuh, timer nol dan RNG baru ketika apply, bukan ketika validasi.
- v3: enam kurma lama dipulihkan persis; sumber tambahan yang belum ada riwayatnya
  mendapat fallback awal tersebut. Daftar enam identitas hanya dipertahankan dalam
  adapter migrasi `city_save_palms.gd`, bukan jalur save v4.
- v4: set sumber dan konfigurasi wajib cocok. Data sumber hilang/asing atau
  konfigurasi berubah menolak checkpoint atomik. Menambah/menghapus sumber pada
  versi content berikutnya memerlukan migrasi yang eksplisit; jangan menyamarkan
  save rusak sebagai sumber baru. Build lama tidak membaca v4.

## Cara memakai untuk sumber baru

1. Pada scene kota, pasang `pickup_source.gd` ke Node2D/Sprite2D atau instance prefab
   yang memakai script tersebut. Bisa juga membuat wrapper turunan untuk default
   suatu jenis sumber, seperti wrapper kurma.
2. Isi `item_id` dari ItemDatabase yang benar-benar terdaftar, `quantity`,
   `max_pickups`, `pickup_positions` (minimal sebanyak kapasitas) dan tekstur opsional.
3. Tentukan `refill_enabled`; jika aktif, isi rentang jam sesuai desain yang disetujui.
   Sumber sekali panen memakai `false`, bukan timer khusus.
4. Pertahankan path scene/node. Jika memakai `persistence_id`, tetapkan nilai authored
   yang unik sebelum save pertama. Mengubah identitas lama memerlukan migrasi.
5. Tidak perlu menambah handler save, daftar ID, atau script pickup baru per jenis.
   Registrasi dan pengecualian barang jatuhan terjadi otomatis.

`scenes/test_scenes/pickup_source_fixture.tscn` adalah contoh runnable dengan item
existing. Tes menginstansiasikannya dua kali: Stone x2 dengan refill dua jam dan
Clay x3 sekali panen. Ini fixture terisolasi, bukan content/balance game baru.

## Batas yang disengaja

Sistem checkpoint tetap milik skenario kota/rumah yang sudah ada. Sumber authored
di kota otomatis ikut, walaupun ledger sedang offscreen saat di rumah. Ini bukan
save seluruh map arbitrer dan tidak membuat kembali pohon prosedural dari data
file; source definitions harus sudah tersedia/terdaftar sebelum load. Pickup biasa
hanya punya interaksi mengambil barang, bukan otomatis menjadi sumber persisten.
Barang jatuhan pribadi tetap memakai jalur CitySave yang sudah ada. Jalur warehouse
ke workshop, filter City Storage, player, autoload, settings/addons dan portrait
capture tidak diubah.

## Validasi

Engine resmi `4.5.1.stable.official.f62fdbde1`, Linux cloud headless.
30 suite unik PASS/PASSED dengan exit 0 dan tanpa error runtime pada run akhir:

- PickupSourcesTest (baru): dua instance satu prefab, item/quantity berbeda,
  refill vs one-shot, slot/RNG independen, load berulang, timer tepat, pengecualian
  personal drops, map recreation, explicit ID bertahan setelah rename node,
  konfigurasi invalid dan timer one-shot invalid tanpa mutasi parsial, serta
  fallback v3 hanya untuk sumber yang belum mempunyai riwayat.
- CitySaveValuesTest, CitySaveFileTest, CitySaveTest, CitySaveEconomyTest,
  CitySleepSaveTest, StartMenuTest.
- DatePickupTest, DateRespawnTest, DateTreeDuplicateTest, DatePickupAccessTest.
- WarehouseTest, InventoryFeedbackLifecycleTest, StatusTabTest, InventoryModalPauseTest.
- RaidRegressionTest, RaidCompositionRegressionTest, RaidRecoveryRegressionTest,
  CityProgressionTest.
- CityStorageHaulingTest, CityToolSupplyTest, StorageDestinationTest,
  CityStorageOverflowTest, CityStorageMaterialConsumptionTest,
  CityStorageSupplyFlowTest, ClayWorksiteHaulerTest, HaulerDeliverySetupTest,
  ResourceWorksitesTest, CityStorageRankedRaidLootTest, TravelingMerchantAccessTest.

Proses terpisah juga PASS: generic source write/read (`--sources-phase=write/read`),
city write/read + StartMenu city, home write + StartMenu home + home read.
StartMenu empty/corrupt PASS. Save v1/v2 dan v3 kota serta v2/v3 rumah diuji.
Migrasi v3 mempertahankan stok/timer/RNG lama; validasi tanpa apply tidak mengubah
live state. Schema v4 menangkap config dan menghasilkan snapshot identik saat load.
Tidak ada offline gain atau replay sleep pada Continue.

Import/parse editor dan startup default (`--quit-after 20`) PASS. Perubahan
metadata import/project yang dibuat editor dikembalikan. Satu run awal menangkap
referensi preload salah ketika variabel internal dirapikan; referensi diperbaiki
lalu seluruh regresi diulang. Run yang mempunyai SCRIPT ERROR tidak dihitung
sebagai PASS meskipun fixture mencetak PASS. Log akhir bersih dari SCRIPT ERROR,
error runtime tak terduga dan leak diagnostics. Warning invalid/read_required/changed
pada kasus negatif merupakan hasil yang diharapkan.

Perintah dasar:

```sh
XDG_DATA_HOME=/tmp/tip-sources/data \
XDG_CONFIG_HOME=/tmp/tip-sources/config \
XDG_CACHE_HOME=/tmp/tip-sources/cache \
/tmp/godot451/Godot_v4.5.1-stable_linux.x86_64 --headless --path . \
  res://scenes/test_scenes/test_scene_pickup_sources.tscn
```

Tambahkan mode setelah `--`. Gunakan scene suite terkait untuk regresi lainnya.
Hauler memakai `TIP_TEST_HAULER=1 TIP_TEST_HAULER_TARGET=1`. XDG data/config/cache
terisolasi di `/tmp/tip-sources/`, log di subfolder `logs`.

## Review akhir

Diff dan whitespace diperiksa. Tidak ada file dihapus/rename, scene produksi,
setting, addon, autoload, item/balance atau warehouse logic diubah. File baru:
komponen `pickup_source.gd`, `pickup_source_state.gd`, adapter
`city_save_pickup_sources.gd` beserta UID, fixture prefab/source test beserta UID,
dan laporan ini. Perubahan lain terbatas pada wrapper kurma, komentar adapter v3,
integrasi CitySave, tiga fixture save/menu, ROADMAP dan ARCHITECTURE.

## Konfirmasi QA Windows oleh Game Director

Pengujian dilakukan pengguna pada worktree terpisah `time_is_precious_pickup_test`,
commit `4b2ba11475fd97b11cfe8dead7df17dfc2d55366`, dengan Godot 4.5.1 Windows.
Agent hanya memandu melalui chat dan membaca screenshot, tanpa mengakses laptop.

- Pengguna melaporkan pengujian manual sudah oke: panen sebagian, masuk rumah,
  tidur hingga checkpoint tersimpan, tutup proses, Continue dan kembali ke kota.
- Screenshot memperlihatkan stok tetap: pohon pertama 2/3, pohon ketiga 0/3,
  empat pohon lain penuh. Timer sebelum penutupan 4h27m/3h16m dan setelah Continue
  4h28m/3h17m konsisten dengan kembali ke checkpoint tidur yang lebih awal daripada
  screenshot setelah berjalan ke kota; bukan bukti timer diundi ulang atau offline gain.
  Ketepatan timer dan tidak adanya offline gain juga tercakup tes otomatis cloud.
- Setelah membuka scene `test_scene_pickup_sources.tscn` dan menjalankan F6,
  pengguna secara eksplisit mengonfirmasi output `PickupSourcesTest: PASS`.
  Ini bukan klaim seluruh 30 suite dijalankan ulang di Windows.
- Folder utama telah diverifikasi pengguna pada `main` dengan working tree bersih;
  pekerjaan content dan pickup test berada di worktree terpisah. Edit lokal content
  tetap terpisah dan tidak dimasukkan ke branch ini.

Pembaruan QA ini hanya dokumentasi; kode tidak berubah setelah commit yang diuji.
Android, export build dan pengujian pacing menyeluruh belum dilakukan.
Tidak ada merge ke main atau force-push. Identitas/konfigurasi content di antara
rilis tetap merupakan kontrak save; migrasi content lintas versi bukan otomatis
menganggap semua record hilang sebagai sumber baru.
