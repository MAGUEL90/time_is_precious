# Time is Precious: serah terima cloud, 9 November 2026

## Cara memakai snapshot ini

Branch ini adalah snapshot kandidat gabungan yang lengkap untuk dilanjutkan oleh agent baru. Seluruh 3.368 file sumber pada kandidat terverifikasi terhadap `PROJECT_SOURCE_SHA256.json`. Manifest itu tidak mencakup lima file dokumen serah terima di direktori ini. Snapshot ini sengaja mengemas pekerjaan yang sebelumnya belum dikomit sebagai satu checkpoint, bukan sebagai persetujuan merge atau rilis. Git parent sebelum checkpoint adalah `84d63c635118764cfdb96589c4e69d9be9e249c2`.

Mulai dengan membaca `AGENTS.md`, aturan repositori, lalu laporan historis dalam direktori ini. Isi laporan ditulis sebelum snapshot branch ini, sehingga pernyataan lama bahwa belum ada commit atau push hanya berlaku pada saat laporan dibuat. Path absolut dan direktori QA pada laporan lama merujuk ke workspace cloud terdahulu, tidak otomatis tersedia di checkout baru. Ringkasan disertakan, tetapi log dan harness QA eksternal tidak termasuk dalam branch ini.

Jangan menerapkan lagi patch incremental dari workspace lama: snapshot ini sudah memuat hasilnya. Jangan reset atau clean perubahan orang lain, jangan gunakan save atau laptop pengguna, dan jangan merge atau deploy tanpa izin. Arsip Godot `.godot` adalah cache dan tidak masuk Git.

## Isi dan pengujian

Snapshot mencakup pekerjaan map/resource binding, identitas dan konfigurasi awal warga, ekonomi dan lifecycle, save schema18, integrasi aset cart dan `work_2`, serta perbaikan path resource dan resolver pakaian cart. `work_2` belum dipetakan ke aksi gameplay yang diputuskan. Sheet cart asli untuk `plain_worn_wrap` belum tersedia; tekstur sintetis dipakai hanya saat tes.

Pengujian terdahulu pada kandidat sumber memakai Godot `4.5.1.stable.official.f62fdbde1`. Sebanyak 78 eksekusi headless terpilih memenuhi hasil yang diharapkan, termasuk tiga proses yang sengaja keluar nonzero untuk guard. Riset HOME schema17 terpisah mencatat 552 assertion pada 17 proses normal dan dua penolakan profil tidak aman yang diharapkan. Lihat `COMBINED_REVIEW_HISTORICAL.md`, `FINAL_QA_SUMMARY_HISTORICAL.json`, dan `SCHEMA17_RESEARCH_HISTORICAL.md` untuk rincian dan keterbatasannya. Snapshot ini bukan penerimaan penuh proyek: playtest visual/manual, Android, dan uji keseluruhan proyek belum dilakukan.

## Risiko yang harus dijaga

- Startup/reload produksi untuk pohon kurma authored belum ada. Tes menggunakan tampilan sintetis; kota produksi enam-source menolak checkpoint tujuh-source. Diperlukan scene authored tersimpan terbaru dan desain migrasi yang direview.
- Reserialisasi JSON Godot biasa mengubah satu nilai decimal `player.hunger` sebesar satu ULP dan token versi `17` menjadi `17.0` dalam fixture riset. Ini bukti perubahan on-disk, bukan bukti bahwa nilai live setelah load berubah. Jangan anggap kesetaraan setelah parse sebagai preservasi byte yang tepat.
- Adapter penyisipan byte hanya alat riset fixture. Jangan gunakan pada save nyata atau sebut sebagai migrasi produksi siap pakai. Pertahankan validator dan arsip rollback yang independen. Runtime17 menolak schema18; backup yang diputar tidak menggantikan arsip17 independen.
- Fixture genuine16 lama memiliki perbedaan katalog worksite. Jangan melonggarkan validator atau menebak migrasi rename/delete.
- Scene cloud belum tentu sama dengan edit laptop terbaru. Rekonsiliasi laptop, keputusan aksi `work_2`, placement/behavior job-board dan Gabi, dan playtest memerlukan arahan atau masukan pengguna.

## Langkah berikut yang aman

Pilih satu tahap bersama pengguna sebelum mengembangkan: audit baseline dan usulkan fokus yang jelas. Untuk tes, gunakan direktori baru dan profil XDG disposable yang sesuai fixture, jalankan engine secara berurutan pada execution namespace yang sama, dan simpan kegagalan tanpa menimpa bukti. Laporkan hasil dan batas pengujian sebelum memperluas lingkup. Preferensi yang dicatat sebelumnya untuk pekerjaan game adalah Terra 6.1 Max, bukan Luna; bila tidak tersedia, sampaikan keterbatasannya.
