# Portrait capture — laporan implementasi dan QA

## Pengamanan konten dan integrasi startup/save — 2026-10-16

Branch: `content/portrait-capture`. Baseline lokal: `696da34`.
Scope: pengamanan konten dan integrasi terbatas LEVEL 2, sesuai permintaan
Game Director untuk commit, fetch, integrasi `d901018`, verifikasi, dan push.

- `19d1da9` menyimpan tepat 11 file capture, tes, dan dokumentasi yang sebelumnya
  untracked. Seluruh file cocok dengan SHA-256 backup awal sebelum commit.
- Fetch origin mengonfirmasi `origin/fix/gameplay-hud/ui-consistency` di `d901018`.
- Merge `11a6d13` memiliki parent `19d1da9` dan `d901018`; tidak ada konflik.
  Seluruh perubahan startup/save diterima utuh. Script, scene, preset, dan tes
  capture tetap identik dengan pekerjaan konten semula.
- Perubahan daftar dialog otomatis pada `project.godot` dan metadata
  `scenes/raid/wall_stone_tile_set.tres` dikeluarkan dari commit konten/merge.
  Keduanya dikembalikan sebagai perubahan lokal. TileSet cocok byte-per-byte
  dengan backup; project settings mempertahankan perubahan lokal dan main scene
  start menu dari `d901018`.
- Backup 13 file awal, manifest SHA-256, patch, dan log QA berada di
  `.git/codex-backups/portrait-capture-20261016-120648/` pada checkout lokal.
  Stash pengaman `93d0ff317b7d7edfa67de00bf9b0500c7b7e56af` tetap disimpan setelah
  diterapkan; stash lama tidak diubah.

Godot **4.5.1**, Windows, GL Compatibility. APPDATA/LOCALAPPDATA QA diarahkan ke
`.godot/portrait-integration-qa/profile/`; probe runtime memverifikasi lokasi
`user://` tersebut sebelum pengujian. Save gameplay pengguna tidak digunakan.

| Pemeriksaan setelah integrasi | Hasil |
| --- | --- |
| Import/parser editor | PASS, exit 0. |
| PortraitCaptureTest headless dan grafis | PASS pada kedua mode, exit 0. |
| PNG dan tampilan capture | PNG 1080×1920; opening dan Worker Progress diperiksa. |
| MainMapHaulerStartTest | PASS, exit 0. |
| StartMenuTest empty / corrupt | PASS; New Game dan preservasi/arsip save diuji. |
| CitySaveTest write + StartMenuTest city | PASS; Continue kota dalam proses baru. |
| CitySleepSaveTest write + StartMenuTest home | PASS; autosave sleep dan Continue rumah dalam proses baru. |
| TravelingMerchantAccessTest | PASS, exit 0. |
| Main scene dari project settings | Smoke test headless, exit 0. |
| Empat sentinel slot normal QA | Primary/.bak/.tmp/.pending tetap identik. |
| Diff, whitespace, scope | PASS; delta terhadap `d901018` hanya file konten terkait. |

Satu warning `City checkpoint: invalid` memang dipicu oleh pengujian save rusak;
tidak ditemukan script/parser error pada run akhir. Tampilan start menu juga
diperiksa dari renderer grafis. Tombol restart R, audio, export/mobile, dan
acceptance pengguna tidak diuji ulang pada pekerjaan integrasi ini.

Bagian berikut merupakan riwayat pengembangan/QA sebelumnya. Pernyataan tentang
branch, engine yang belum diuji, atau belum adanya commit berlaku pada tahap
historis masing-masing, bukan hasil integrasi di atas.

## Revisi font dan rumah capture lokal

Font capture diseragamkan ke `res://assets/font/pixel_rpg.ttf`, ukuran logis 6.
Override diterapkan pada instance Control/Window, termasuk popup, RichTextLabel
dan UI yang dibuat kemudian; resource theme gameplay tidak dimutasi. Label dunia
mengimbangi zoom kamera agar ukuran tampil konsisten dengan UI dan muatan cart
tidak menumpuk dengan label Clay. Preview lokal kini 360x640 (`preview_scale=1`).

Rumah yang diperiksa pada frame runtime adalah `YSortWorld/HomeDoor/House`,
berlabel Home / Sleep. Parent HomeDoor tetap ada tetapi visual, label dan trigger
masuknya dinonaktifkan dalam proses capture. Area ini bukan collider fisik;
menonaktifkannya menghindari transisi home yang tidak terlihat. Definisi rumah
pada ContentScene asli tetap visible/monitoring; asset dan scene utama tidak diubah.

Tes Godot 4.5.1 headless dan grafis Windows/OpenGL Compatibility lulus. Run akhir
memeriksa font 6 pada tree dan panel konten, batas UI, rumah capture/main-map,
manual work, assignment, F4 sleep/day settlement, produksi, hauling/delivery,
konservasi output, player movement, PNG 1080x1920 dan empat sentinel save QA.
Frame opening, Worker Hub, manual preview/result, Inventory, worker selection,
Hauler Delivery, assignment, next day, loaded cart, worker/player dan progress
diperiksa langsung. Log run akhir tidak memuat ERROR/WARNING/FAIL.

Run awal menemukan callback styling tertunda terhadap row UI yang sudah dibebaskan.
Callback kini membawa instance ID dan memeriksa objek masih hidup sebelum styling;
run headless/grafis sesudah perbaikan lulus tanpa error tersebut.

File revisi: `portrait_capture.gd`, `manual_vs_delegation.tres`,
`portrait_capture_test.gd`, panduan capture dan laporan ini. Branch dan perubahan
user tetap; tidak ada commit/push/merge. Screenshot dipakai sebagai bukti QA internal.
Log: `capture-qa/font-house-final-graphical-4.5.1.log` pada workspace task lokal.

## Verifikasi lokal Hendro - Godot 4.5.1

Paket ZIP lokal berukuran 19563 byte, SHA-256
`f2238a9de6b984eac93e004b5a5137318654d2453b6af8cff15840c81b5967d3`.
CRC dan traversal diperiksa; tepat 11 file, revisi satu Clay Site dengan
`focus_site_only=true`. Semua target belum ada saat pemasangan.

Project: `C:\Users\Hendro\OneDrive\Documents\Project\Github\time_is_precious`.
Branch tetap `fix/gameplay-hud/ui-consistency`, HEAD `696da34972444189317e2605fc9472d11de46485`.
Perubahan user pada `project.godot` dan `scenes/raid/wall_stone_tile_set.tres`
dipertahankan; ContentScene dan checkpoint store asli tetap identik.
Tidak ada pull, checkout, commit, push atau merge.

Adaptasi hanya pada capture: panggil `refresh_checkpoint_slot()` jika method tersedia.
Store lokal belum memiliki method itu, tetapi instance fresh mengamati path capture
pada save pertama. Sistem save utama tidak diubah.

- Import editor 4.5.1 selesai tanpa parse/script error.
- `PortraitCaptureTest: PASS`, exit 0, headless Godot 4.5.1.
- `MainMapHaulerStartTest: PASS`, exit 0, headless Godot 4.5.1.
- Capture: viewport 360x640, satu site/stockpile visible, lima session terdaftar,
  manual/assignment/next-day/hauling, movement, konservasi output, input angka,
  bounds UI dan capture checkpoint terverifikasi.
- APPDATA/LOCALAPPDATA QA terisolasi di workspace; empat sentinel slot normal
  QA (primary/.bak/.tmp/.pending) tidak berubah. Save pengguna tidak dipakai.
- Grafis/pixel clipping, F8 PNG dan tombol R secara langsung belum diuji lokal.
  Headless menguji bounds UI dan argumen restart, bukan hasil grafis atau proses R.

Log lokal berada di `C:\Users\Hendro\Documents\Codex\2026-10-12\task\capture-qa`.
Laporan berikut adalah bukti cloud 4.6.3; jangan menyamakannya dengan review visual lokal.

Tanggal: 2026-10-11 UTC. Status: **PASSED — NEEDS HUMAN REVIEW** setelah pemeriksaan
yang dicatat di bawah; belum ada persetujuan merge.

## Dasar dan batas kerja

- Branch kerja: `feature/content-scene/portrait-capture`.
- Baseline: `d901018f0fca495d4ca70e671cfde0e4defb01e2`,
  `fix/gameplay-hud/ui-consistency`, tanggal commit 2026-10-11 05:41:56 UTC.
- Pemeriksaan remote menjelang penyerahan tetap menunjukkan baseline tersebut;
  remote `main` masih `01fde83fc1a0a0a0464e32461bed15c5c11c55a6`.
- Salinan awal `/workspace/time_is_precious` pada branch `work` / commit `01fde83`
  tetap bersih. Implementasi berada di worktree `/workspace/time_is_precious_capture`.
- Scope diperluas dari audit baca-saja setelah pengguna menyetujui penataan di
  salinan/branch terpisah (“oke anda bisa atur”). Risiko LEVEL 2, integrasi terbatas
  untuk presentasi/fixture capture. Tidak ada perubahan aturan gameplay atau save schema.
- AGENTS.md, control pack, dokumen proyek dan sumber terkait diperiksa.
  `.agents/skills` tidak tersedia pada snapshot ini.
- Tidak ada commit, push, PR, merge, edit branch sumber atau publikasi. Perubahan
  lokal pengguna di luar snapshot remote tidak terlihat dan tidak diklaim tercakup.

## Hasil dan hubungan dengan gameplay

`portrait_capture.tscn` menjadi satu entrypoint capture reusable. Ia menginstansiasi
ContentScene asli sebagai `current_scene`, lalu mempertahankan rig operator sebagai
sibling. Kamera dan ukuran Window hanya berubah pada proses capture, 360×640 logical
/ 720×1280 preview. `project.godot` tetap identik dengan baseline.

Resource `manual_vs_delegation.tres` menyiapkan jam 14:00, supply fisik awal, dua
applicant yang direkrut melalui API asli dan satu cart kota yang benar-benar equipped.
Perubahan preset memberi pilihan site/framing/supply tanpa menduplikasi scene/map.
Fixture ini masih khusus dua peran laborer/hauler; belum merupakan editor storyboard umum.

Manual work, modal Hourly/Daily, Worker Hub, pemilihan worker, konfirmasi destination
dan target, shift besok 07:00, hasil di ground, hauling dan Worker Progress tetap
menggunakan implementasi native. Sumber pokok:

- `scenes/content_scene/content_scene.tscn`
- `scenes/content_scene/worksites/main_map_worksites.tscn`
- `scenes/content_scene/startup/initial_worksites.gd`
- `scenes/test_scenes/clay_worksite_test/test_scene_clay_worksite.gd`
- `scenes/test_scenes/clay_worksite_test/clay_worksite_daily.gd`
- `scenes/test_scenes/clay_worksite_test/clay_worksite_hauling.gd`
- `scenes/test_scenes/ui_sandbox/clay_worksite_inspector/clay_worksite_inspector.gd`

F4 adalah persiapan antar-shot menggunakan sleep native, tiga makanan Inventory
fisik dan elapsed-minute signals. Tidak ada kebutuhan pemain yang dimatikan.
Pergantian hari tampak pada clock lokal. HOLD menghentikan clock otomatis sambil
membiarkan tint waktu native, animasi dan movement berjalan. Rate x10 memakai
TimeDebugOverlay asli; penunjuk rate/HOLD tidak menyembunyikan time compression.

Slot disk diarahkan ke folder unik `user://content_capture/session-*` sebelum sleep
atau save. Slot normal tidak dimuat, diarsipkan atau ditimpa. R membuka proses baru
agar take tidak me-reset sebagian state singleton dan meninggalkan state tersembunyi.

## Revisi fokus satu worksite

Masukan pengguna menyebut banyak worksite membuat portrait terlalu padat. Revisi
ini menambah `focus_site_only` pada resource preset dan filter visibility pada rig
capture. Default menampilkan Clay Site dan stockpile Clay; empat marker worksite
lain, empat stockpile lain dan City Storage disembunyikan dalam proses capture.
Tidak ada node, asset, registrasi session, delivery endpoint atau collision yang
dihapus/diubah. Framing, posisi dunia, zoom 2.0 dan scene map dasar tetap sama.

Tes grafis revisi `portrait_capture_test.tscn` PASS, lalu diulang headless dan PASS.
Tes membuktikan satu site dan satu stockpile terlihat, lima session native tetap
ada, semua endpoint masih available dengan collision aktif, dan hanya satu Daily
plan dijadwalkan. Manual output/fatigue, shift besok, cart loaded, movement pemain,
delivery ke Clay, konservasi output, bounds UI, PNG dan empat sentinel save normal
juga lulus pada revisi. `main_map_hauler_start_test.tscn` diulang headless dan PASS
untuk hiring, equipment, reload dan dismissal pada map biasa.

Screenshot revisi diperiksa langsung: opening, workers-and-player, loaded-cart,
Hauler Delivery dan Worker Progress. Opening serta shot worker kini menampilkan
satu worksite dan satu stockpile. Hauler Delivery tetap memilih Clay; Worker
Progress menampilkan output laborer 10 dan delivered hauler 9 pada frame bukti.
Jam dan hasil frame bergantung timing runtime, bukan angka output yang dipaksakan.
Log revisi: `capture-focused-output.log`, `capture-focused-headless-output.log`,
`hauler-focused-regression-output.log` di folder QA. Warning grafis tetap hanya
V-Sync unsupported dari dummy display; tidak ada script/resource error pada run akhir.

Filter visibility tidak membatasi interaksi native pada site yang tersembunyi;
take ini tetap berada di jalur Clay menuju workshop. Screenshot dan paket awal
diganti dengan hasil revisi, bukan dipakai ulang sebagai bukti revisi. Video final,
engine 4.5.x, audio dan acceptance visual pengguna tetap belum diverifikasi.

## File baru

| File | Tujuan |
| --- | --- |
| `scenes/content_scene/capture/capture_preset.gd` | Resource parameter capture. |
| `scenes/content_scene/capture/capture_preset.gd.uid` | Identitas script Godot. |
| `scenes/content_scene/capture/manual_vs_delegation.tres` | Preset take pertama. |
| `scenes/content_scene/capture/portrait_capture.gd` | Rig lokal, startup native, clock/camera, slot save, PNG, restart. |
| `scenes/content_scene/capture/portrait_capture.gd.uid` | Identitas script Godot. |
| `scenes/content_scene/capture/portrait_capture.tscn` | Entry scene F6. |
| `scenes/test_scenes/portrait_capture_test.gd` | Tes integrasi dan pengambilan bukti grafis. |
| `scenes/test_scenes/portrait_capture_test.gd.uid` | Identitas script Godot. |
| `scenes/test_scenes/portrait_capture_test.tscn` | Entry tes. |
| `docs/content-portrait-capture.md` | Panduan operasional/shot dan batas penggunaan. |
| `docs/task_reports/2026-10-11-portrait-capture.md` | Laporan ini. |

Tidak ada file lama, asset, addon, autoload, player, konfigurasi, AGENTS atau control
pack yang termasuk perubahan. Import editor 4.6.3 sempat menghasilkan migrasi otomatis
di project.godot dan tiga SVG import addon; noise tersebut ditinjau dan dipulihkan
hanya di worktree capture sebelum penyerahan.

## Verifikasi yang dilakukan

Engine tersedia: **Godot 4.6.3**, Linux, GL Compatibility, Mesa llvmpipe.
Baseline proyek: **4.5.x**. Xorg dummy digunakan untuk renderer grafis; user-data,
config dan cache QA dipisahkan di `/tmp/tip-portrait-qa`.

| Pemeriksaan | Hasil |
| --- | --- |
| Project editor import/parser (`--headless --editor --import`) | PASS, tidak ada parse/script error. |
| Direct graphical launch capture | PASS, scene dan rig siap. |
| `portrait_capture_test.tscn` dengan renderer grafis dan headless | PASS pada kedua mode. |
| Ukuran viewport dan PNG | 360×640 logical; gambar 1080×1920, 9:16 penuh. |
| E → Hourly → 3h → Next → Start Work | PASS, menit +180, hasil nyata, fatigue meningkat. |
| Daily native UI dan setup hauler ke Clay / target 20 | PASS, assignment mulai hari berikutnya 07:00. |
| Input angka di target saat shortcut capture aktif | PASS, kolom menerima angka tanpa mengubah kamera. |
| F4 sebelum committed plan | Ditolak tanpa perubahan menit. |
| F4 setelah committed plan | PASS, sleep/food/day settlement; Day 1 06:45, makanan tersisa satu, movement/needs guard aktif. |
| Player bergerak meninggalkan worksite saat x10 | PASS, clock/produksi berjalan; route cart loaded dan delivery nyata. |
| Konservasi output laborer | PASS, ground + cargo + stockpile sama dengan output tercatat. |
| Bounds dan review screenshot UI penting | Worksite, Hourly, Inventory, assignment, hauler setup, Worker Hub dan Worker Progress muat; judul/aksi/target terlihat. |
| F8 transaction | PASS, file PNG penuh tersimpan di folder sesi capture. |
| Save capture + empat sentinel slot normal | PASS, checkpoint capture tertulis; normal primary/.bak/.tmp/.pending tetap identik byte per byte. |
| Input R melalui runtime bridge | PASS, proses lama keluar; proses baru kembali Day 0 14:00, dua hire, slot sesi berbeda. |
| `main_map_hauler_start_test.tscn` | PASS, hiring/equipment/map reload/dismissal asli. |
| `test_scene_start_menu.tscn`, mode empty | PASS, New Game membuka ContentScene dengan kebutuhan normal. |
| Diff review / whitespace / scope | PASS, hanya sebelas file baru di atas; file sumber/protected tidak berubah. |
| Patch pada index sementara dari baseline (`git apply --cached --check`) | PASS; tidak menerapkan patch pada checkout awal pengguna. |

Log dan screenshot bukti disertakan di paket QA di luar source project. Tes baru
juga dapat dijalankan dengan:

```sh
godot --headless --path . --scene res://scenes/test_scenes/portrait_capture_test.tscn
```

Untuk bukti gambar, jalankan dengan renderer grafis dan set `TIP_CAPTURE_EVIDENCE`
ke direktori output yang sudah tersedia. Tes tidak menulis slot normal; harness QA
menanam sentinel hanya pada user-data terisolasi di `/tmp`.

## Temuan selama pengembangan dan batas akhir

- Percobaan `--check-only --script` standalone menghasilkan identifier autoload
  yang tidak terdaftar pada dependency native. Diganti dengan import dan launch
  proyek penuh; tidak dipakai sebagai bukti parser gagal/lulus proyek.
- Tes integrasi awal gagal karena path stockpile pada harness salah. Path diperbaiki
  ke child native `ClayStorage`; run akhir lulus.
- Satu run mengalami konflik port 9877 addon MCP karena child probe restart masih
  hidup. Child uji milik sesi ini dihentikan, kemudian run akhir diulang secara tunggal.
  Addon tidak diedit. Konflik ini tidak mengubah hasil gameplay, tetapi tetap dicatat.
- Xorg dummy memberi warning V-Sync unsupported. Audio device tidak tersedia;
  tes grafis utama memakai `--audio-driver Dummy`. Probe R membuktikan restart,
  tetapi child mengalami fallback ALSA → Dummy. Kualitas audio belum diuji.
- Visual runtime benar-benar diuji lewat renderer grafis dan screenshot, bukan
  hanya pembacaan kode. Timing/edit hasil video, encoding, kualitas di layar ponsel,
  export mobile, perjalanan ke home/nightmare, dan Godot 4.5.x belum diuji.
- Manual work masih fade/time skip. Shift delegation baru bekerja esok hari.
  Panduan mempertahankan bukti dua hal ini; tidak ada animasi/hasil palsu.
- Tidak ada klaim fitur roadmap selesai. Snapshot branch ini berbeda dari main;
  setup tidak menggabungkan fitur lain atau perubahan lokal yang belum di-push.

Review manusia diperlukan untuk framing, pace hasil edit, engine 4.5.x dan
persetujuan integrasi. Tidak ada blocker implementasi pada lingkungan yang diuji.
