# Kontrak pekerja prabayar — 23 Oktober 2026

Status: implementasi dan QA cloud; menunggu review gameplay manusia sebelum PR/merge.
Branch: `feature/economy/prepaid-worker-contracts`.
Baseline: `914baec1e57d326bd043b7ba704ac656ccded69d` dari remote
`fix/economy/city-storage-treasury-ui`. Tidak memakai commit lokal a8aa5cb.

## Keputusan yang diterapkan

Instruksi terbaru Game Director menggantikan payroll tujuh hari dari kas kota:

- Hire membayar langsung dari dompet pemain, pilihan 3/6/9 hari. Tidak ada pembayaran kelompok, pemotongan otomatis, atau tunggakan.
- Sisa hari pembelian termasuk layanan; durasi paket memberi hari penuh mulai besok. Contoh: hire Day 1 pukul 08.01, paket 3 hari berlaku segera sampai Day 5 pukul 07.00 (hari penuh Day 2–4).
- Worksite tetap shift 07.00–15.00, sesuai jawaban eksplisit. Assignment saat shift mulai pada menit assignment; sebelum shift mulai hari itu pukul 07.00, setelah shift mulai besok pukul 07.00. Tidak ada produksi retroaktif; batas tenaga harian tetap berlaku saat dipindah.
- Job Board tetap buka 08.00–17.00. Tidak ada masa tunggu onboarding semalam.
- Perpanjangan per pekerja di Worker Hub, dengan konfirmasi biaya. Kontrak aktif menambah hari pada batas lama; kontrak kedaluwarsa/pending mulai sekarang. Tarif baru hanya pada pembelian berikutnya. Pemecatan tanpa refund.
- Kontrak baru berakhir pukul 07.00. Kontrak lama yang belum diperpanjang tetap memiliki batas 08.00 yang sudah dibayar. Perpanjangan menggunakan aturan kontrak baru.
- Notifikasi memakai tombol `!` yang sudah ada: pekerja mendekati tempo/kedaluwarsa, merchant, dan raid. Membuka popup mengakui pemberitahuan; perubahan hitungan menit bukan pemberitahuan baru. Status pengakuan tersimpan.
- Kas kota dan setoran fisik City Storage tetap tersimpan. Audit menemukan payroll sebagai konsumen runtime kas; setelah perubahan ini kas tidak lagi membiayai pekerja. Penggunaan kota berikutnya belum dirancang. Management tetap ringkasan kas.
- Hasil workshop/penjualan milik pemain. Fee cetakan/fasilitas, filter City Storage, akses warehouse→workshop, kebutuhan dan housing tidak diubah.

## Tarif sementara untuk pengujian

| Profesi | 3 hari | 6 hari | 9 hari |
| --- | ---: | ---: | ---: |
| Laborer, Hauler, Scavenger | 1 | 2 | 3 |
| Crafter, Farmer | 2 | 4 | 6 |

Nominal Shekel ini belum merupakan validasi balance final. Pembelian kurang dana ditolak tanpa kontrak baru atau pemotongan sebagian.

## Save dan implementasi

Schema naik dari 6 ke 7: durasi paket, menit awal pembayaran, serta pengakuan notifikasi. Pembaca menerima versi 1–6; field kontrak yang belum ada mendapat penanda legacy, bukan pembayaran otomatis. Pending legacy dapat diperpanjang manual. Validasi assignment menerima awal di dalam shift. Transaksi mempublikasikan dompet dan kontrak bersama, menolak reentry; perpanjangan menyelesaikan akuntansi kerja lama sebelum mengubah hak kerja agar jeda tidak dibayar sebagai produksi.

API quote payroll lama dipertahankan untuk kompatibilitas diagnostik, tetapi tidak digunakan untuk penagihan atau UI kontrak baru.

## Pengujian Godot 4.5.1

Semua hasil akhir di [test-results.txt](evidence/prepaid-worker-contracts-2026-10-23/test-results.txt). Exit code diperiksa bersama pesan PASS dan kesalahan script.

**Fixture terkontrol**, memakai grant/clock/setup eksplisit: pembelian/renew, kurang dana meskipun kas kota kaya, paket invalid, batas hari, atomic/reentry, tarif berubah, pekerja independen, legacy 08.00, expiry baru 07.00, pemecatan, assignment parsial/daily cap/hauler, serta notifikasi panjang. Ini bukan bukti perjalanan ekonomi normal.

**Continue fixture pada proses terpisah:** write → read → readrenew → legacy-read → legacy-renew-read, kemudian assignment-write → assignment-read. Meliputi roundtrip v7, migrasi v6 paid/pending, penolakan data invalid, kontrak expired, dan assignment dengan progres parsial.

**Perjalanan normal:** New Game kosong, kebutuhan aktif, tanpa grant, perubahan jam, atau penggantian RNG. Menjual tiga kayu menghasilkan 6 Shekel; hire mengurangi dompet menjadi 5 dan kas tetap 0. Pekerja dibayar dan dipakai pada clearing workshop hari itu. Tidur/simpan lewat kasur nyata, lalu Continue proses lain mengembalikan snapshot. Bukti: [write](evidence/prepaid-worker-contracts-2026-10-23/write-result.json), [read](evidence/prepaid-worker-contracts-2026-10-23/read-result.json).

**UI dari checkpoint hasil perjalanan normal:** berjalan dan menunggu dengan kebutuhan aktif sampai jam buka, menyimpan checkpoint kota untuk pengambilan gambar. Memilih paket tanpa bayar, membatalkan konfirmasi, lalu memperpanjang 6 hari seharga 2 Shekel (dompet 5→3, kas 0). Konfirmasi ulang yang sudah tidak aktif tidak memotong lagi. Fase write kemudian menyimpan lewat kasur nyata; fase read proses terpisah memverifikasi snapshot dan kontrak.

Regresi lulus: population/employment, rehire, tim worksite, content worksites, hauler setup (`TIP_TEST_HAULER_TARGET=1`), raid UI, city save values/file/economy termasuk fee dan konservasi cargo. Ekspektasi satisfaction save-economy disesuaikan ke 0.55 karena produksi kini hari yang sama, bukan tambahan satu hari simulasi.

## Screenshot

Gambar asli viewport 400×225 dari renderer cloud, tidak diedit:

- [Job Board](evidence/prepaid-worker-contracts-2026-10-23/job-board.png)
- [Pilihan perpanjangan](evidence/prepaid-worker-contracts-2026-10-23/worker-renew.png)
- [Konfirmasi](evidence/prepaid-worker-contracts-2026-10-23/renew-confirmation.png)
- [Setelah diperpanjang](evidence/prepaid-worker-contracts-2026-10-23/renewed.png)
- [Notifikasi — fixture](evidence/prepaid-worker-contracts-2026-10-23/contract-notices.png)
- [Nama panjang — fixture](evidence/prepaid-worker-contracts-2026-10-23/long-notices.png)

Renderer llvmpipe memperingatkan VSync tidak didukung; pengujian rendered tetap PASS. Popup panjang memakai scroll dan tetap di dalam viewport. Review artistik warna/teks tetap milik Game Director.

## Batas dan review manual

- Animasi perjalanan worksite masih menghitung commute menuju pukul 07.00. Assignment sebelum shift tetapi setelah waktu keberangkatan terhitung dapat terlihat sudah berada di tengah perjalanan. Hak kerja dan cargo tetap dibatasi menit assignment; penyempurnaan visual commute belum dikerjakan.
- Popover Manage dapat berpindah sisi setelah roster di-refresh oleh perpanjangan; kontrol tetap terlihat dan transaksi lolos uji.
- Fixture payroll tujuh hari dan beberapa fixture departure/commute lama mencerminkan aturan yang diganti; bukan acceptance kontrak baru dan belum semuanya dimigrasikan.
- Balance final belum dinyatakan selesai. Uji manusia: hire paket 3 hari, assign sebelum 15.00, cek biaya/output, renew dan cancel, simpan/Continue, kemudian cek notifikasi mendekati tempo.

Tidak ada merge main, force-push, atau PR baru dalam tugas ini. Tidak ada akses laptop.
