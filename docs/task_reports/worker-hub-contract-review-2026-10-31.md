# Worker Hub: panel Contract dan feedback Fire — 31 Oktober 2026

Status: **PASS — NEEDS HUMAN REVIEW**. Basis pekerjaan adalah commit `66cd6c2b811f485ab7a79d8946a5ae3d5fc6f27c` pada branch `fix/ui/fire-worker-feedback-20261031`.

## Perubahan

Menu Manage sekarang berisi Fire, Go To, Details, dan Contract. Contract membuka panel dengan status kontrak, pilihan 3/6/9 hari, harga dan ikon mata uang, Back, serta Renew. Membuka panel, memilih durasi, dan Back tidak memotong saldo. Renew memakai harga worker terkini dan memproses satu transaksi; apabila harga berubah setelah ditampilkan, pemain perlu meninjau harga baru dan menekan Renew lagi. Tarif, sumber dana wallet, aturan durasi, produksi, satisfaction, dan schema save tidak diubah.

Alasan Fire nonaktif muncul ketika pointer mengarah ke Fire, tanpa klik. Teks memakai font pixel UI yang sama, ukuran 6, warna merah, dan diberi jarak dari bingkai. [Manage sebelum revisi](evidence/worker-hub-contract-review-2026-10-31/manage-before.png), [empat aksi Manage](evidence/worker-hub-contract-review-2026-10-31/manage-actions.png), [panel Contract](evidence/worker-hub-contract-review-2026-10-31/contract-panel.png), dan [hover Fire](evidence/worker-hub-contract-review-2026-10-31/fire-hover.png).

Nama pada screenshot dan fixture review menggunakan `Naram` dan `Lugal`, yang ada di daftar nama `CitizenGenerator`. Kandidat awal pada kode produksi memang memiliki nama tampilan `Workshop Laborer` dan `Worksite Hauler`; nama awal itu tidak diubah. Untuk screenshot perjalanan, nama Naram/Lugal hanya dipasang pada memori profil tes terisolasi setelah checkpoint dipulihkan.

## Pengujian

Godot 4.5.1 di Linux; render memakai logical viewport 400×225 dan window 1200×675. Semua save pengujian terisolasi.

| Pemeriksaan | Hasil dan bukti |
| --- | --- |
| Review UI dari checkpoint perjalanan | **PASS:** fase [prepare](evidence/worker-hub-contract-review-2026-10-31/ui-review-prepare.log) dan [capture](evidence/worker-hub-contract-review-2026-10-31/ui-review-capture.log). Waktu dan kebutuhan berjalan normal; nama review diatur hanya pada profil tes. Ini melanjutkan checkpoint yang sudah ada, bukan perjalanan New Game lengkap yang baru dijalankan. |
| Hover Fire | **PASS dua kali:** pointer X11, masuk/keluar tanpa klik, font/warna, jarak dari bingkai, perubahan status dan batas viewport. [Run pertama](evidence/worker-hub-contract-review-2026-10-31/hover-first.log), [ulang](evidence/worker-hub-contract-review-2026-10-31/hover-repeat.log). |
| Contract dan Worker Control | **PASS:** 3/6/9, Back, Escape/fokus keyboard, harga berubah, profesi berubah, dana kurang, pengulangan Renew, dan Fire cancel. [Contract](evidence/worker-hub-contract-review-2026-10-31/renewal-ui.log), [Worker Control](evidence/worker-hub-contract-review-2026-10-31/worker-control.log). |
| Kontrak, sprite, rehire | **PASS:** [prepaid](evidence/worker-hub-contract-review-2026-10-31/prepaid-contracts.log), [visual lifecycle](evidence/worker-hub-contract-review-2026-10-31/worker-visual-lifecycle.log), [rehire](evidence/worker-hub-contract-review-2026-10-31/worker-rehire.log). |
| Expired → renew → Continue | **PASS:** mode single [write](evidence/worker-hub-contract-review-2026-10-31/expiry-write.log), [renew](evidence/worker-hub-contract-review-2026-10-31/expiry-renew.log), [read](evidence/worker-hub-contract-review-2026-10-31/expiry-continue.log). |
| Peta utama terkontrol | **PASS:** Contract → Back tidak membayar; Renew memotong wallet sekali; Fire dan save diikuti rehire serta assignment baru yang menghasilkan actor terlihat, berjalan, dan beranimasi kerja. Proses terpisah kemudian Continue dari save setelah Fire. [Write](evidence/worker-hub-contract-review-2026-10-31/main-map-write-controlled.log), [read](evidence/worker-hub-contract-review-2026-10-31/main-map-continue-controlled.log). Tes ini mengatur jam, satisfaction untuk reapply, dan kebutuhan player; bukan playthrough normal tanpa kontrol. |

## Diagnosis City Storage

Fase prepare fixture UI lama gagal pada baseline maupun revisi karena helper lama berjalan ke koordinat lokal `(0,8)`, sementara batas X area akses yang diperiksa adalah `[2,42)`. Helper itu tidak membuka menu fisik. [Baseline gagal](evidence/worker-hub-contract-review-2026-10-31/city-storage-baseline-failure.log), [revisi sebelum koreksi fixture gagal](evidence/worker-hub-contract-review-2026-10-31/city-storage-revision-failure.log). Fixture review kini memakai helper perjalanan yang sudah ada: mendekati papan pada `(5,29)`, menekan E, dan memeriksa menu. Prepare dan capture kemudian lulus; kode produk City Storage tidak diubah.

Screenshot pemilik ditinjau oleh parent; executor ini tidak berhasil mematerialisasi file sumber tersebut. Render hasil game di atas diperiksa langsung pada executor. Windows, Android, sesi manual manusia, dan perjalanan penuh New Game hingga akhir tidak diuji pada revisi ini. Renderer llvmpipe melaporkan V-Sync tidak dapat diubah; fixture rehire memiliki warning ObjectDB saat keluar yang sudah tercatat sebelumnya.
