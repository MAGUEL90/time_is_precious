# Handoff — worker payroll onboarding

Tanggal: 2026-10-22 (Asia/Jakarta). Dokumen keputusan dan rencana, bukan laporan implementasi payroll.

## Branch dan batas sesi setup

- Repository: MAGUEL90/time_is_precious.
- Branch baru: `feature/economy/worker-payroll-onboarding`.
- Parent: `test/gameplay/mvp-first-playthrough`.
- Baseline: `17507b4c66e8adc30f00eb125cdf5011202c8799`; working tree awal bersih.
- Baseline ini membawa fix merchant b449a1e dan audit 17507b4, di atas merge PR #115 d6ea244. Jangan menganggap dua commit audit sudah merged ke main. Periksa ancestry remote sebelum PR.
- Sesi setup hanya membuat branch dan handoff ini; tidak mengimplementasikan gameplay atau mengubah balance. Risiko setup LEVEL 1.
- Push melalui shell cloud gagal karena proxy port 8080 tidak dapat dihubungi. Branch dan handoff kemudian dipublikasikan langsung melalui konektor GitHub. Commit dokumentasi remote berbeda dari commit lokal a8aa5cb; untuk sesi berikutnya gunakan branch GitHub sebagai titik awal, jangan push history lokal yang divergen.

## Bacaan awal sesi berikutnya

1. AGENTS.md dan urutan dokumen kontrol 00–06 dalam docs/agent-control.
2. ROADMAP.md, ARCHITECTURE.md, DEVLOG.md, docs/root-branch-map.md, bagian relevan docs/game-concept.md.
3. docs/task_reports/mvp-first-playthrough-2026-10-18.md serta laporan integrasi gameplay, mudbrick main-map, merchant MVP/shared worksites, date-palm persistence/reusable pickup sources.
4. Cocokkan keputusan terbaru di bawah dengan desain dan kode. Dokumen kontrol lama masih menyebut save pending; jangan perlakukan itu sebagai bukti status implementasi. Schema v4 dan fallback v1/v2/v3 sudah tersedia pada baseline PR #115.

## Keputusan pengguna tentang payroll

- Job Board buka 08.00–17.00. Rekrut hari ini mulai bekerja dan dihitung upahnya besok pukul 08.00; tidak ada prorata jam.
- Perekrutan berkelanjutan, pemain tidak memilih durasi kontrak. Upah dibayar DI MUKA untuk tujuh hari, diperpanjang otomatis.
- Sumber pembayaran kas kota. Pemain menyetor dari dompet secara eksplisit; tidak ada penarikan otomatis dari dompet.
- Hasil workshop dan uang penjualannya milik pemain, bukan kota. Jangan menciptakan dua input workshop atau sistem kepemilikan baru.
- Tanggal pembayaran mengikuti periode masing-masing pekerja, bukan tanggal global 7/14/21. Contoh bayar Hari 6 pukul 08.00 mencakup Hari 6–12; perpanjangan Hari 13 pukul 08.00.
- Setiap pagi kumpulkan SEMUA pekerja yang membutuhkan pembayaran: pekerja baru yang mulai hari itu, yang jatuh tempo, dan yang masih menunggu dari hari sebelumnya. Dana cukup untuk total: bayar semuanya; tidak cukup: jangan potong uang dan jeda semuanya. Tidak ada pemilihan penerima atau pembayaran parsial.
- Pekerja dengan periode berbayar yang belum berakhir tetap bekerja walaupun kas menipis atau kelompok lain dijeda.
- Top-up siang hari tidak langsung mengaktifkan pekerja: coba lagi besok pukul 08.00. Pembayaran berhasil membuka tujuh hari penuh mulai hari tersebut dan menggeser tanggal jatuh tempo berikutnya.
- Tidak ada tunggakan, bunga, atau akumulasi upah selama jeda. Tetap terdaftar sebagai pekerja dengan penugasan, status menunggu pembayaran; tidak otomatis menjadi penganggur. Untuk MVP tidak ada batas jeda otomatis/payroll resignation. Aturan warga pergi karena kondisi hidup tetap terpisah.
- Masa berbayar tetap berjalan saat idle, kehabisan bahan, atau belum diberi pekerjaan.
- Pemecatan tidak mengembalikan sisa pembayaran; UI memperingatkan sisa periode sebelum konfirmasi.
- Profesi berbeda mendapat tarif berbeda. Angka 1 shekel/7 hari untuk pekerja dasar dan 2 untuk terampil masih kandidat, BUKAN tabel balance final yang sudah diuji.
- Tarif dikunci selama periode berbayar. Perubahan tarif akibat profesi/keahlian berlaku pada pembayaran berikutnya tanpa tagihan tengah periode. Memindahkan tugas saja tidak mengubah profesi/tarif.
- Satisfaction diarahkan berbasis rumah dengan ringkasan kota; bukan penalti individual yang dihitung dari tanggal gaji. Implementasi rumah/satisfaction di luar tahap awal payroll. Jangan diam-diam mengubah sistem kebutuhan existing.

## Hal yang harus diverifikasi, bukan diasumsikan

- Fee workshop: audit mencatat Shape fee 5 dan Dry rent 2. Pengguna menjelaskan ada fee penggunaan cetakan. Asisten menarik usulan menghapusnya: pertahankan sampai kode/desain mengungkap tujuan fee. Upah tenaga dan sewa alat/fasilitas bisa berjalan bersamaan.
- Jeda pekerjaan harus menjaga progres, konsumsi bahan, dan barang yang dibawa; cegah konsumsi ganda/duplikasi. Usulan: hentikan kontribusi pekerja, proses pasif seperti pengeringan tetap berjalan jika desain existing memang pasif. Periksa kontrak aktivitas sebelum implementasi.
- Pekerja baru menambah total pembayaran pagi; dapat menunda seluruh kelompok. UI harus menampilkan total, kas, kekurangan dan waktu mulai, bukan hanya tarif satu pekerja.
- Tidak ada rancangan tarif lengkap per profesi/level, termasuk kapan kenaikan profesi terjadi. Jangan menciptakan promosi otomatis baru.
- Pelunasan tidak boleh menghapus hambatan kerja lain dari kebutuhan, alat, atau kondisi existing.

## Rencana bertahap

Fokus branch ini: TAHAP 1 — rekrut dan pembayaran pertama. Definisikan kontrak scope teknis dan dampak save sebelum mengedit sistem terlindungi; gunakan keputusan gameplay yang sudah disetujui, jangan meminta ulang persetujuan yang sama. Keputusan yang belum jelas tetap TBD.

1. Audit alur Job Board, worker/population, jam dunia, dompet/kas kota, dan snapshot save. Reuse sistem existing; tidak menambah autoload atau merombak arsitektur tanpa kebutuhan dan otorisasi yang sesuai.
2. Implementasikan irisan terkecil: setoran kas, jam Job Board, hire pending sampai besok, pembayaran awal atomik, feedback pemain, persistensi state terkait. Jangan memasukkan sistem rumah atau produksi baru ke branch ini.
3. Uji dana cukup/kurang, hire menjelang tutup, tidak bisa bekerja sebelum aktif, potongan tepat sekali, beberapa worker mulai bersamaan, dan save/Continue lintas proses sebelum/sesudah pukul 08.00. Time skip/tidur tidak boleh melewatkan atau menggandakan pembayaran.
4. Tahap berikutnya setelah review: integrasi kerja/produksi dan fee; perpanjangan/jeda/resume; pemecatan/perubahan tarif; kemudian rumah/suplai/satisfaction. Pecah branch lanjutan sesuai scope, jangan mengimplementasikan semuanya sekaligus.

## Validasi dan batas tetap

- Cloud saja; tidak akses laptop/computer use. Folder utama laptop tetap main; jangan rekonstruksi perubahan lokal belum di-push.
- Godot 4.5.1. Kebutuhan pemain dan pekerja aktif. Pisahkan tes fixture dari perjalanan New Game menggunakan uang/material/worker normal; jangan paksa permintaan merchant untuk meloloskan perjalanan.
- Audit baseline membuktikan sampel produksi berulang dan Continue otomatis, bukan kesiapan seluruh ekonomi kota. Ada hambatan sumber pakaian, shelter dan Stone serta variasi permintaan merchant; baca hasil dan kegagalan regresi pada laporan asli.
- Uji save/Continue di SETIAP tahap, termasuk pending hire dan jeda; pertahankan kompatibilitas lama dengan fallback eksplisit. Jangan menjanjikan UI visual atau Windows PASS dari tes headless.
- Jangan ubah filter City Storage atau buka jalur warehouse → workshop. Content/portrait-capture terpisah. Tidak menambah rantai produksi besar.
- Review diff, commit kecil, push branch kerja. Jangan merge main atau force-push. Laporkan dalam bahasa Indonesia.

## Konteks desain lanjutan (bukan implementasi tahap 1)

- Rumah L1: kapasitas tiga; kebutuhan primer makanan/pakaian. Tempat tidur baru kebutuhan L2, bukan L1. Kandidat kapasitas L2 empat.
- Upgrade: tingkat kota lebih tinggi, rumah penuh, kebutuhan/satisfaction terpenuhi; penghuni tetap memiliki rumah selama upgrade. Rumah baru tetap pilihan.
- Imigran berdasarkan statistik kota dan tetap dapat datang saat rumah penuh; homelessness harus tetap terwakili dalam kondisi warga.
- Material rumah L1 kandidat 4 Wood + 8 Clay + 6 Reed; belum hasil balance. Pemain dapat membantu membangun/perbaikan. Perbaikan butuh waktu/bahan; HP bangunan/raid/riot dibahas sebagai arah, detail belum final.
- Furniture produksi/beli merchant untuk kebutuhan tidur L2 merupakan pekerjaan terpisah. Jangan mengimplementasikan dari konteks ini pada branch payroll.
- Pembayaran upah keluar dari simulasi ekonomi; tidak ada wallet belanja kebutuhan per warga. Pajak ditunda. Starter shekel/quest pendanaan masih opsi, bukan implementasi yang disepakati nilainya.
- Kualitas pakaian/FIFO belum final. Jangan menganggap FIFO existing: audit sebelumnya menemukan pemilihan ID garment terurut. Simpan sebagai topik suplai berikutnya.

## Verifikasi sesi setup

Hanya dokumentasi dan branch baru. Review diff dan git diff --check; tidak menjalankan regresi Godot karena tidak ada perubahan runtime. Tidak menandai payroll sebagai selesai atau merged.
