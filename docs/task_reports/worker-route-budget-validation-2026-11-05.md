# Validasi route budget dan skip waktu — 5 November 2026

Status: **PARTIAL — potensi dampak gameplay terkonfirmasi pada fixture; belum ada perbaikan produksi**. Basis cloud yang diuji: commit `4c3a338385c8b716232b589125a0e404e53bf646`, branch `test/gameplay/worker-route-budget-20261105`. Ini bukan salinan perubahan privat atau collider alternatif pada lingkungan induk. SHA-256 file basis untuk dibandingkan: `test_scene_worker_route_budget.gd` `f4d491210611c34cb00b2b7efc0fbfa31daef4f638cad2a3fcafd9df334b59fd`; `workshop_worker_presence.gd` `2c99d7ef92cc54ec492cafe69405082d34d256009166bc839cd80f0229693491`; `worksite_navigation.gd` `48a37d758c7ada32d6eb8e0247e7e9b4fff92d255be605a55cd8ccdde3e8778e`; `worksite_route_search.gd` `c988a115fde1762b27d8cf0ed1484ee5e056a33a3a75ec26db12ffab2d75b94e`; `time_component_manager.gd` `7e4018464b3da4c75c95de32ea5325ba2cf4fcacacb5b5d3fe49f1eccdffad07`; `player.gd` `9a76076ac9817a1d3a1c48771182eefb31def2bdaae5ab0ad383c2278f8f8871`.

## Hasil pada Godot 4.5.1

Godot `4.5.1.stable.official.f62fdbde1`, headless, profil XDG terisolasi dan satu proses engine pada satu waktu. Fixture menggunakan kota, clock, kontrak dan state konstruksi sebenarnya, tetapi menyediakan lima pekerja, dana, bahan, posisi dan collider buatan. Setelah satu hari dan pembukaan gerbang, fixture mengukur **120 menit simulasi berikutnya**:

| Kasus | Hasil | Frame proses selama 120 menit | Rute dan progres konstruksi |
| --- | --- | ---: | --- |
| `test_scene_worker_route_budget.tscn`, sumber asli sebelum instrumentasi, tiga run | **FAIL (4)** setiap run | 0 | Empat assertion kedatangan gagal. Probe terpisah menemukan rute pending saat budget habis. |
| Scene asli setelah instrumentasi, tiga run | **FAIL (4)** setiap run | 0 | Lima rute teramati pending, pekerja belum tiba, `credit_delta=0`, `work_delta=0`. |
| `test_scene_worker_route_budget_multiframe.tscn`, tiga run | **PASS** setiap run | 11 batas frame antara 12 batch | Lima rute found dan tiba, `credit_delta=530`, `work_delta=530` pada sampel ini. |
| `test_scene_worker_route_budget_sleep.tscn`, tiga run | **FAIL (4)** setiap run | 0 | `player.sleep_for_minutes(120)` berhasil memajukan waktu, lima rute tetap pending, `credit_delta=0`, `work_delta=0`. |

Run final setelah penambahan diagnostik posisi mengulangi hasil ketiga mode. Empat kegagalan adalah pemeriksaan asli pada empat worker yang semula terkurung; worker kelima juga terlihat pending pada diagnostik final. Nilai 530 adalah **unit kemajuan konstruksi pada fixture ini**, bukan jumlah barang, patokan balance, atau prediksi semua perangkat. Tidak ditemukan teleportasi dalam pemeriksaan gerak fixture; ini bukan uji bermain alami atau input ranjang/perpindahan rumah. Jalur sleep memanggil langsung metode produksi pada player di fixture kota.

Regresi terdekat `test_scene_time_transaction_guard.tscn` dan `workshop_shift_resignation_test.tscn` masing-masing **PASS** pada 4.5.1. Keduanya tidak membuktikan bahwa skip satu-frame sudah aman; kegagalan kedatangan di atas tetap terbuka.

**Dua belas batch 10 menit dengan jeda frame bukan ekuivalen dengan satu skip 120 menit dalam satu frame.** Tes asli tetap menggunakan `advance_minutes(120)` sinkron dan tetap gagal; varian multi-frame hanya membuktikan liveness ketika planner mendapat budget baru. Tes sleep mempertahankan kegagalan terpisah pada metode player yang nyata. Tidak ada assertion kedatangan yang dihapus atau dibuat lulus secara palsu.

## Temuan dan implikasi

`workshop_worker_presence.gd` berbagi budget pencarian **20.000 mikrodetik dan 40.000 operasi per frame proses**, dibagi lagi antar-worker aktif. `advance_minutes` mengeluarkan tiap menit secara sinkron tanpa frame proses baru. Pada percobaan skip setelah perubahan collider, budget waktu mencapai nol sementara rute belum selesai; sisa operasi masih ada. Akibatnya, pada fixture ini worker tidak bergerak/tiba selama dua jam simulasi dan tidak mendapat kredit kerja. Hasil route yang cepat atau lambat dapat bergantung beban mesin; variasi liveness antar-frame bukan bukti bahwa produksi dalam satu skip benar.

Budget ini mengatur potongan kerja planner, bukan batas keras seluruh durasi frame. Deadline diperiksa sebelum satu operasi planner, sehingga operasi atau penjadwalan OS dapat melewati deadline; salah satu log fixture mencatat `remaining_usec=-1792`. Pemrosesan 1.440 menit dan sistem lain juga memakan waktu di luar budget planner. Perlu profiling terpisah sebelum menjanjikan batas frame nyata yang presisi.

`sleep_for_minutes` memanggil `advance_minutes` secara langsung. Pekerjaan manual di worksite dan clearing plot juga melakukan pemanggilan menit sinkron berulang tanpa yield di dalam loop. Karena itu temuan ini dapat memengaruhi aksi nyata, walaupun frekuensi dan besar dampaknya dalam perjalanan normal belum diukur. Pemeriksaan satu-frame harus tetap menjadi regresi yang diketahui gagal sampai ada perbaikan dan verifikasi lintas jalur.

## Arah solusi untuk review, belum diimplementasikan

Salah satu arah yang perlu dievaluasi adalah **transaksi skip bertahap lintas frame**: ketika pencarian rute yang relevan untuk menit berikutnya masih pending dan budget frame habis, tahan kemajuan menit tersebut, lanjutkan planner pada frame berikutnya, lalu lanjutkan simulasi dengan urutan signal dan transaksi yang sama. Jangan me-reset budget manual berkali-kali di dalam satu frame, karena itu menghilangkan batas yang dimaksud. Alternatif preflight rute perlu memperhitungkan collider atau tugas yang berubah *di tengah* skip; merencanakan hanya sekali di awal tidak cukup.

Ini perubahan lintas sistem dan bukan patch kecil pada fixture. `advance_minutes` dan pemanggilnya kini mengandalkan hasil `bool` sinkron; perubahan ke operasi menunggu memerlukan audit seluruh pemanggil dan kontrak UI. Rancangan harus menjaga kunci transaksi/reentrancy, `is_sleeping`, urutan needs/gaji/arrival/produksi, batas save/Continue, perubahan scene/collapse, pembatalan, serta kondisi rute unreachable/limit agar tidak menunggu selamanya. Jangan memajukan jam terlebih dahulu lalu memberi kerja secara retroaktif. Verifikasi juga kondisi geometri berubah di tengah skip, worker campuran reachable/unreachable, fairness, pelestarian stok, dan batas budget setiap frame pada mesin lambat dan cepat.

## Perubahan cabang dan bukti

Hanya fixture tes, dua scene uji tambahan, dan laporan ini yang diubah. Tes asli tetap default satu-frame; `recovery_mode` hanya dipilih scene tambahan. Log mentah tersimpan di `/workspace/tip-route-budget-evidence/` pada lingkungan pengujian. Tidak ada perubahan produksi, aset privat, atau penggabungan ke branch bersama. Hasil ini perlu direkonsiliasi dengan basis privat yang lebih baru dan di-review sebelum merge.
