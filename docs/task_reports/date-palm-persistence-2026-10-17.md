# Persistensi enam pohon kurma — 2026-10-17

Status: PASSED — NEEDS HUMAN REVIEW. Belum di-merge.

## Otorisasi dan baseline

- Repository: `MAGUEL90/time_is_precious`.
- Branch: `fix/save-load/date-palm-persistence`.
- Baseline terverifikasi: `78779c43fd0e542991765afce263b80b8240b688` (setelah PR #114).
- Working tree awal bersih. Checkout cloud awal masih `01fde83`; branch remote
  di-fetch sebelum perubahan. Tidak ada edit laptop yang direkonstruksi.
- Risiko: LEVEL 3, perubahan kompatibilitas checkpoint/global runtime, secara
  eksplisit termasuk dalam tugas persistensi yang diberikan Game Director.
- Aturan AGENTS/control pack, ROADMAP, ARCHITECTURE, sumber save/startup/palm,
  dan laporan integrasi sebelumnya diperiksa. Konfigurasi root Astra tidak dapat
  dipilih ulang dalam sesi ini; tidak ada klaim pergantian model/eskalasi.
  Subagen Luna XHigh mengerjakan tes terbatas; keputusan kompatibilitas,
  implementasi produksi, review diff dan penerimaan tetap oleh root.

## Implementasi dan kompatibilitas

Checkpoint v3 menambah `date_palms`, tanpa mengganti filename slot, lokasi, atau
field lama. Keenam identitas adalah SHA-256 scene path + node path yang sudah
ada, bukan urutan instansiasi, posisi dunia, atau ID runtime sementara.
`city_save_palms.gd` menyimpan bitmap slot, sisa menit, seed dan state RNG masing-masing.
RNG memakai codec integer desimal 64-bit yang sudah ada; seed dipulihkan sebelum
state. Tidak ada pengundian saat load. Interval dan pola refill tetap seperti semula.

Validasi mencakup set identitas lengkap, jumlah/tipe slot, timer dalam batas
0–1080 menit, konsistensi stok penuh/timer nol, serta struktur dan tipe RNG.
Data invalid menolak seluruh checkpoint sebelum perubahan owner mana pun.
Pemulihan mengubah keenam ledger secara sinkron lalu menyegarkan view melalui
spawner. Pickup tetap berada dalam group `date_palm_pickups`, bukan city drops;
Inventory hanya berisi kurma yang sudah dipanen.

Save v1/v2 tidak punya bukti stok pohon historis. Fallback saat **apply**:
semua pohon penuh, timer nol, RNG baru per pohon. Tidak menebak dari Inventory,
dan tidak melakukan fallback ketika hanya membaca/memvalidasi slot untuk Save.
Save berikutnya menulis v3. Build lama tidak bisa membaca v3. Perubahan nama/path
keenam pohon di masa depan membutuhkan migrasi eksplisit.

Di rumah, ledger tetap berada dalam WorkStateRuntime. Sleep menggunakan menit
game yang benar-benar berlalu sebelum autosave; Continue memulihkan ledger dan
clock sebelum transisi rumah yang sudah ada. Waktu proses tertutup tidak dihitung.

## Batas perubahan

Tidak mengubah scene/layout/jumlah pohon, kapasitas pickup, nilai makanan,
interval refill, ekonomi, balance, filter City Storage, jalur warehouse/workshop,
project settings, addons, autoload, atau content/portrait-capture. Komentar palm
menjelaskan kontrak identitas disk. ROADMAP/ARCHITECTURE diperbarui untuk boundary
ini; DEVLOG tetap riwayat merged, tidak mengklaim branch ini sudah merged.

## Validasi

Official Godot `4.5.1.stable.official.f62fdbde1`, Linux cloud, headless.
29 suite unik mencapai PASS/PASSED dan exit 0:

- CitySaveValuesTest, CitySaveFileTest, CitySaveTest, CitySaveEconomyTest,
  CitySleepSaveTest, StartMenuTest.
- DatePickupTest, DateRespawnTest, DateTreeDuplicateTest, DatePickupAccessTest.
- WarehouseTest, InventoryFeedbackLifecycleTest, StatusTabTest,
  InventoryModalPauseTest.
- RaidRegressionTest, RaidCompositionRegressionTest, RaidRecoveryRegressionTest,
  CityProgressionTest.
- CityStorageHaulingTest, CityToolSupplyTest, StorageDestinationTest,
  CityStorageOverflowTest, CityStorageMaterialConsumptionTest,
  CityStorageSupplyFlowTest, ClayWorksiteHaulerTest, HaulerDeliverySetupTest,
  ResourceWorksitesTest, CityStorageRankedRaidLootTest, TravelingMerchantAccessTest.

Mode tambahan memakai proses Godot yang benar-benar berbeda:

1. City Save `--city-save-phase=write`, lalu `read`, lalu Start Menu `--menu-mode=city`.
2. Sleep Save `--sleep-save-phase=write`, lalu Start Menu `--menu-mode=home`,
   lalu Sleep Save `read` (read membersihkan fixture setelah verifikasi).
3. Start Menu `--menu-mode=empty` dan `--menu-mode=corrupt`.

Fixture kota memanen satu slot berbeda pada tiap pohon melalui PickUpItem asli:
12 view tersisa, 6 kurma di Inventory. Snapshot seluruh owner, slot, timer,
RNG 64-bit dan clock sub-menit dibandingkan setelah load/proses baru. Load berulang
mempertahankan jumlah dan identitas slot; pengundian berikutnya mengikuti RNG
tersimpan. Kasus invalid melewati file checkpoint dan membandingkan seluruh
snapshot sebelum/sesudah penolakan. Fallback v1/v2 kota dan v2 rumah diuji;
checkpoint v3 ditulis setelah upgrade legacy. Validasi legacy tanpa apply terbukti
tidak mengubah seluruh state/RNG. Fixture timer 4–9 menit menguji satu menit sebelum
jatuh tempo dan tiap menit berikutnya: hanya pohon yang waktunya habis yang refill,
tidak ada duplikasi view atau tambahan Inventory. Round-trip pohon penuh juga
mempertahankan RNG. Kasus invalid mencakup identitas pengganti dengan jumlah tetap,
timer negatif/float/terlalu besar, RNG hilang/salah tipe/field ekstra, kapasitas/tipe
slot salah, record ekstra, serta stok/timer yang tidak konsisten.

Fixture sleep memulai satu timer pendek dan lima timer berbeda yang masih tersisa
setelah tujuh jam tidur. Pemeriksaan memastikan hanya pohon yang waktunya habis
yang refill, RNG tidak dikonsumsi saat refill, dan timer lainnya berkurang tepat
sebanyak durasi tidur. Kedua arah home/city dan Continue rumah mempertahankan
ledger; pickup pribadi Clay dan stok/cargo worksite juga tetap diverifikasi.

Perintah dasar:

```sh
XDG_DATA_HOME=/tmp/tip-palm/data \
XDG_CONFIG_HOME=/tmp/tip-palm/config \
XDG_CACHE_HOME=/tmp/tip-palm/cache \
/tmp/godot451/Godot_v4.5.1-stable_linux.x86_64 --headless --path . \
  res://scenes/test_scenes/test_scene_city_save.tscn
```

Gunakan scene suite terkait; argumen mode setelah `--`. Demo hauling memakai
`TIP_TEST_HAULER=1 TIP_TEST_HAULER_TARGET=1`. Data test terisolasi di `/tmp/tip-palm`.
Log lengkap sesi cloud berada di `/tmp/tip-palm/logs/`.

Editor import/parse dan startup default terbatas (`--quit-after 20`) selesai.
Percobaan import pertama tanpa izin jaringan menghasilkan error socket dari
plugin MCP yang sudah ada; import akhir dengan izin jaringan selesai bersih.
Tes disk awal menangkap perbandingan versi JSON bertipe float yang terlalu ketat;
pemeriksaan versi diperbaiki dan suite terkait diulang sampai PASS. Warning
checkpoint invalid/read_required/changed pada tes negatif disengaja. Log akhir
regresi tidak memiliki SCRIPT ERROR, error runtime tak terduga, atau leak diagnostic.
Perubahan otomatis editor pada `project.godot` dan metadata import dikembalikan.

## Review dan keterbatasan

- Diff/whitespace diperiksa; tidak ada penghapusan/rename file, perubahan balance,
  scene produksi, settings, addon, atau autoload. Script produksi baru hanya
  adapter palm; perubahan spawner/state berupa komentar/pesan kontrak identitas persistensi.
- Pengujian headless mencakup alur nyata pickup, save, sleep, door, dan menu.
  Review visual manusia, Windows, Android, physical GPU, dan playtest pacing
  belum dilakukan. Tidak ada klaim balance baru atau visual acceptance.
- Keenam path pohon merupakan kontrak identitas save. Menambah/mengganti identitas
  atau kapasitas pada pengembangan berikutnya perlu kebijakan migrasi tersendiri.
- Save legacy sengaja mendapat stok awal penuh; ini fallback data yang tidak
  pernah disimpan, bukan rekonstruksi kondisi historis. Build lama menolak v3.
- Tidak merge ke main, tidak force-push. Keputusan merge tetap Game Director.

File baru: `scenes/new_scenes/save_game/city_save_palms.gd` beserta `.gd.uid`,
dan laporan ini. File diubah: `city_save_state.gd`, komentar pada
`date_palm_state.gd`/`date_palm_spawner.gd`, tiga fixture
`test_scene_city_save.gd`, `test_scene_city_sleep_save.gd`,
`test_scene_start_menu.gd`, serta `ROADMAP.md` dan `ARCHITECTURE.md`.
Tidak ada file dihapus atau di-rename.
