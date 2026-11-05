# Audit Satisfaction dan progres kota — 5 November 2026

Status: **PARTIAL — koreksi ambang diuji; perlu review dan rekonsiliasi dengan pekerjaan laptop**. Pembersihan aset dan ekspresi wajah belum dikerjakan. Basis: commit `4c3a338385c8b716232b589125a0e404e53bf646` dari `feature/gameplay/character-needs-20261101`. Cabang kerja terpisah: `test/gameplay/satisfaction-multiday-20261105`. Salinan cloud bersih saat dibuat; proyek laptop dan perubahan yang belum dikomit tidak tersedia di salinan ini. Setelah instruksi lanjutan, commit audit pertama dipush ke cabang remote terpisah dan hash remote diverifikasi. Tidak ada merge, perubahan pada branch bersama, atau perubahan pada laptop.

Cakupan perubahan kode: koreksi angka floating-point pada aturan progres yang sudah ada, tes batas/settlement/Continue dan laporan audit. Risiko: **LEVEL 2 — limited integration**, karena hasil progres kota terpengaruh pada batas aritmetika; tidak mengubah skema save, aset, setting, autoload, atau angka balance yang telah ada. Penerimaan akhir dan integrasi tetap milik sesi root dan Game Director. Konfigurasi model/reasoning yang disyaratkan control pack tidak dapat diverifikasi dari salinan ini.

## Progres kota yang sudah ada

Rata-rata Satisfaction **hasil settlement** resident pada hari itu sudah memberi **+5 progres** bila mencapai 70%. Warga yang menjadi worker dihitung satu kali sebagai resident; worker lama yang tidak terhubung ke resident tidak termasuk. Semua resident terpenuhi Food memberi +5, semua terpenuhi Clothing memberi +5, dan tembok yang tidak berdiri memberi −5. Progres dibatasi 0–100; pada 100, pemain memilih Level Up secara manual. Ambang 70% adalah bonus harian, bukan syarat mutlak tombol Level Up. Audit ini tidak menambahkan hard gate atau bonus lain.

Ledger kota, termasuk level, progres, `last_daily`, `last_awarded_day`, dan ID breach terakhir, disimpan/dipulihkan oleh checkpoint kota. Komentar lama yang menyebut progres hanya session-only telah dikoreksi. Tidak ada perubahan format save pada pekerjaan ini.

## Koreksi ambang 70%

Pada kode awal, hasil 12%, 99%, 99% memiliki rata-rata matematis 70%, tetapi representasi floating-point dalam dua urutan resident membuat perbandingan gagal sehingga bonus menjadi 0. Sebelum koreksi, tes baru mereproduksi dua kegagalan itu pada Godot 4.5.1. Sesudah koreksi, seluruh permutasi mendapat +5. Toleransi perbandingan `1e-12` pada skala 0–1 hanya mengakomodasi selisih aritmetika sangat kecil; ia tidak membulatkan angka yang ditampilkan dan jauh lebih kecil dari presisi `1e-9` pada settlement kebutuhan. Artinya, nilai hingga `1e-12` di bawah ambang juga diperlakukan sebagai sama dengan 70%; pengujian memastikan bahkan penurunan satu langkah `1e-9` pada satu dari tiga resident tetap tidak mendapat bonus. Tidak ada perubahan angka kebutuhan, target, hadiah, atau aturan Level Up lain.

Tes terarah juga memakai tiga resident nyata dengan worker linked dan worker lama unlinked. Dengan tembok berdiri dan suplai fixture, hari pertama rata-rata tepat 70% memberikan +15 total; hari berikut Food habis dan rata-rata turun sehingga hanya Clothing memberi +5; setelah Food diisi, rata-rata naik dan total kembali +15. Sinyal atau settlement yang diulang pada hari yang sama tidak menggandakan progres. Ini adalah fixture, bukan penilaian balance perjalanan alami.

## Kejelasan angka pada UI

City Hub dan HUD menunjukkan rata-rata resident **saat ini**, dibulatkan ke persen. Perolehan Mood di ledger memakai snapshot settlement; raid atau perubahan resident sesudahnya dapat mengubah rata-rata live tanpa mengubah hadiah hari itu. Selain itu 69,6% ditampilkan 70% tetapi tidak mencapai 70% untuk bonus. Ledger yang ada sudah menampilkan Mood +5 atau 0 dan hari settlement, tetapi tidak menyimpan rata-rata settlement sebagai angka. Usulan untuk rekonsiliasi UI: beri label jelas bahwa rata-rata tersebut nilai saat ini dan bahwa Mood merupakan hasil pemeriksaan pada hari tercatat; bila angka rata-rata settlement ingin ditampilkan juga, pertimbangkan penyimpanan dan kompatibilitas save karena cohort dapat berubah. Perubahan UI ditahan karena UI laptop belum tersinkron.

## Audit aset di basis cloud

Pemeriksaan nama path dan UID dalam resource/scene/script, serta SHA-256 pada 114 file sumber di `assets/characters/`, menemukan dua pasangan byte-identik:

- `shared_assets/beard_assets/idle/brown/brown_01.png` dan `shared_assets/beard_assets/walk/brown/brown_01.png`. Versi idle di-preload oleh `scenes/workshop_plot/keeper/workshop_keeper.gd`; walk tidak ditemukan referensi statis path/UID.
- `merchant/merchant_1/hat_assets/folded_linen_headwrap/idle/idle.png` dan pasangan `walk/walk.png`; tidak ditemukan referensi statis path/UID dalam source/scene/resource yang dipindai.

Tidak ditemukan referensi statis bukan bukti aman dihapus: pemuatan dinamis, kebutuhan kerja artis, dan perubahan yang hanya ada di laptop masih harus dicek. Tidak ada aset yang dihapus, dipindah, atau diubah namanya.

Contoh nama yang membingungkan: `body_assets/work/base/tan/warm.png` dipakai sebagai `work_body_base_tan` di `base_worker_visual.tscn`, dan byte-nya berbeda dari `work/base/warm/warm.png`. Ini kandidat penamaan ulang setelah semua path/UID dan hasil animasi diperiksa, bukan duplikat yang aman dihapus.

Tileset November `assets/temporer/tile_set/tile_set_base_new_02_11_2026_new.png` dipakai `resources/tile_map_resources/map_authoring_tileset_02_11_2026.tres`. Tileset September `assets/tile_set/tile_set_base_new_28_09_2026.png` masih dipakai `scenes/content_scene/ground_tile_set.tres` oleh ContentScene; tileset Agustus `tileset_base_13.08.2026.png` masih dipakai `resources/tile_map_resources/nightmare_tile_map.tres` oleh Nightmare. Tileset Juni dan beberapa tileset lain masih dirujuk fixture; versi Oktober expanded juga diperiksa integritasnya oleh `asset_organization_test`. `tile_set_base_new_24_10_2026.png` dan November tanpa akhiran `_new` tidak ditemukan referensi statis path/UID, tetapi tetap perlu rekonsiliasi dan pengecekan pemuatan dinamis sebelum diputuskan. Tanggal lebih lama saja bukan bukti asset dapat dihapus.

## Integrasi ekspresi yang masih perlu

File wajah happy/sedih/marah yang disebut Hendro belum ada di basis cloud ini; ikon UI Satisfaction yang ada bukan bukti bahwa spritesheet wajah tersebut tersedia. Jangan menebak nama animasi, ukuran frame, warna kulit, atau batas Satisfaction. Aktor dunia utama dikelola `clay_worksite_worker_visuals.gd`, yang menyimpan aktor per ID dan mengambil profil dari resident/worker; `BaseWorkerVisual.play_visual()` sudah menerima `expression`. Integrasi setelah aset tersedia perlu membaca Satisfaction aktual untuk ID yang bersangkutan, menyegarkan saat settlement, setelah raid dan sesudah Continue, menjaga identitas worker-resident, serta memeriksa fallback dan frame untuk idle/walk/work/cart. Jalur cart saat ini memilih animasi kepala `base` secara khusus. Ambang ekspresi belum diputuskan; jangan menyimpannya sebagai fakta desain. Tidak ada implementasi wajah palsu atau placeholder aktif pada branch ini.

## Verifikasi

Godot resmi **4.5.1.stable** dipakai dengan direktori XDG sementara yang berbeda dari data pengguna, satu proses engine pada satu waktu. Import editor selesai tanpa parser error. Pengujian awal di bawah dilakukan secara headless; hasil lanjutan grafis dicatat setelahnya. Tidak ada playtest manusia pada branch ini.

- `test_scene_city_progression`: PASS, termasuk reproduksi ambang, permutasi, nilai di kedua sisi, kebutuhan nyata tiga hari, linked/unlinked dan idempotensi.
- `test_scene_satisfaction_condition`, `test_scene_satisfaction_threshold_transport`, `test_scene_satisfaction_production` (80 order), `test_scene_city_food_daily`, `test_scene_city_clothing_needs`, `population_employment_integration_test`, `test_scene_idle_resignation`, `test_scene_applicant_eligibility`: PASS.
- `test_scene_multi_day_needs_journey`: write/read/verify PASS dalam tiga proses, dengan dana, bahan, serta suplai kebutuhan sebagai fixture dan percepatan waktu; ini bukan permainan alami dari nol.
- Pengujian awal `test_scene_satisfaction_condition_save`: write/read/post-read/home-read PASS pada revisi branch yang sama dalam empat proses. Tes memeriksa ulang sinyal kebutuhan setelah Continue dan memastikan progres, hari terakhir, dan ledger tidak berubah. Pengujian lintas revisi lanjutan dicatat di bawah.
- `test_scene_city_save`: write/read/roundtrip PASS, termasuk progres 35 yang dipulihkan; kasus save yang sengaja invalid menghasilkan warning `unsupported`/`invalid` yang diharapkan. `test_scene_satisfaction_recovery_review`, `test_scene_citizen_live_needs`, `test_scene_raid_ui`, `test_scene_city_residents`, `test_scene_worker_control`, dan `asset_organization_test`: PASS.
- Pada pengujian awal, `test_scene_city_progression_hub` **FAIL** pada Godot 4.5.1 headless: tujuh assertion seputar konstruksi, layout padat, dan breach. Ketujuh pesan error itu juga identik saat scene dijalankan pada commit dasar `4c3a338` tanpa perubahan branch ini. Hasil investigasi dan pengujian ulang dicatat di bawah.
- Startup utama headless selama 120 frame berakhir tanpa error; ini smoke test terbatas, bukan bukti rendering. Dua perintah awal salah menunjuk lokasi scene Food dan Worker Control dan gagal memuat scene; pengujian diulang dengan path yang benar.

Log mentah berada di `/workspace/tip-satisfaction-evidence/` pada lingkungan kerja cloud. Review visual manusia, penggabungan dengan perubahan laptop, penilaian balance alami, dan penerimaan oleh Hendro masih diperlukan.

## Tindak lanjut — fixture City Hub dan checkpoint

- Tujuh kegagalan City Hub pada audit awal direproduksi tanpa perubahan di `4c3a338`. Penyebab utamanya fixture mengisi City Storage untuk konstruksi, padahal aturan yang berlaku membayar dari Inventory pemain. Kegagalan pertama itu menyebabkan beberapa pemeriksaan watchtower dan breach ikut gagal. Fixture sekarang menyediakan Inventory, memeriksa bahwa biayanya dibayar sekali dari Inventory dan City Storage tidak berubah, lalu memulihkan Inventory setelah tes.
- Tes headless mula-mula menggunakan viewport `400×400` tetapi menguji batas 225 piksel; helper screenshot juga tidak menunggu frame ketika headless. Fixture kini menetapkan jendela uji `1200×675`, memverifikasi viewport logis `400×225`, dan menunggu layout sebelum membandingkan posisi. Pemeriksaan tidak dihapus atau dilonggarkan. `test_scene_city_progression_hub` kemudian **PASS** headless dan pada renderer grafis GL Compatibility 4.5.1 dengan software Mesa; tangkapan serangan dan breach diperiksa. Renderer virtual mengeluarkan warning V-Sync yang tidak didukung. Ini memperbaiki fixture, bukan UI produksi; review tampilan oleh Hendro tetap diperlukan.
- Tes tiga hari kini memeriksa kehilangan Satisfaction akibat kode raid yang mengubah rata-rata live dari atas ke bawah 70%, tanpa mengubah ledger hari yang telah selesai atau memberi bonus ulang. Dengan progres fixture 100, Level Up tetap dapat dipilih saat rata-rata live di bawah 70%, sesuai aturan yang ada.
- `test_scene_satisfaction_condition_save` lulus **lintas revisi pada Godot 4.5.1**: writer dari `25f587c`, kemudian read/post-read/home-read pada branch ini dalam proses terpisah dengan profil yang sama. Tes memeriksa bonus +5 sebelum dan setelah Continue, raid tanpa penghitungan ulang, lalu hari offscreen di rumah saat rata-rata turun di bawah 70% dan bonus Mood menjadi 0. Checkpoint dan identitas tetap diuji oleh fixture yang sama.
- Arsip aset privat yang telah diverifikasi secara terpisah oleh lingkungan induk tidak berhasil dimaterialisasi pada lingkungan ini; tidak ada byte aset yang dimasukkan ke cabang. Karena itu validasi maupun integrasi wajah dan pohon tidak diklaim di sini.
