# Tab status — 5 Oktober 2026

Baseline `6263a4f`, branch `feature/item/food-mvp`, working tree awal bersih. Scope LEVEL 1: memperbaiki visibilitas UI status yang dilaporkan pengguna; tidak mengubah binding atau mekanik gameplay.

ContentScene menyimpan BottomHUD dengan `visible = false`. Script menghubungkan sinyal Nightmare tetapi belum menerapkan state awal ketika NightmareWorld ditemukan. Karena itu Tab menggerakkan drawer di dalam CanvasLayer yang tetap tersembunyi. Rumah tidak memiliki override tersembunyi tersebut. Pemeriksaan food sebelumnya tidak mencakup shortcut status; ini celah cakupan QA.

Perbaikan satu baris memanggil handler visibilitas existing dengan `nightmare_world_ref.is_active` setelah koneksi sinyal. HUD normal langsung terlihat; drawer tetap tertutup sampai Tab ditahan, lalu menutup ketika Tab dilepas. Nightmare tetap menyembunyikan HUD dan mematikan inputnya. Tidak ada perubahan scene, project settings, InputMap, atau nilai kebutuhan pemain.

`StatusTabTest` memakai InputEventKey dengan keycode/physical_keycode KEY_TAB melalui viewport, bukan memanggil handler langsung. Pengujian meliputi map utama, rumah, reload map, dua siklus tahan/lepas per scene, nilai satiety aktual, modal inventory, serta sinyal visibilitas Nightmare aktif/nonaktif. Pengujian sinyal ini tidak diklaim sebagai playtest Nightmare penuh.

- Sebelum perbaikan: FAIL, enam assertion visibilitas gagal pada dua pemuatan ContentScene; input dan animasi drawer sendiri bekerja.
- Sesudah perbaikan: headless PASS, exit 0, tanpa ERROR/WARNING.
- Render GL Compatibility/llvmpipe: PASS pada viewport 400×225/window 1200×675; screenshot diperiksa. Hanya warning V-Sync display virtual yang tidak didukung. Modal inventory ditambahkan sebagai assertion headless final setelah run grafis.

```sh
godot --headless --path . scenes/test_scenes/status_tab_test.tscn
# Untuk screenshot: sediakan folder yang sudah ada dan display grafis.
TIP_STATUS_CAPTURE_DIR=/tmp/status-tab-captures godot --audio-driver Dummy --path . scenes/test_scenes/status_tab_test.tscn
```

[Status pada map](status-tab-visuals/ContentScene.png) · [Status dalam rumah](status-tab-visuals/PlayerHomeInterior.png)

Godot 4.6.3/Linux diuji; Godot 4.5.x/Windows/Android belum diuji. File produksi berubah hanya `scenes/ui/bottom_hud/bottom_hud.gd`; file baru adalah fixture (.gd/.tscn beserta UID), laporan dan screenshot. Tidak ada file existing dihapus/diganti nama. Status: **PASSED — NEEDS HUMAN REVIEW**.
