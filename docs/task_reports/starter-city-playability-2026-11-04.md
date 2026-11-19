# Jalur awal kota dan perekrutan — 2026-11-04

Status: **PASSED — NEEDS HUMAN REVIEW** untuk perubahan sementara dan cakupan
uji di bawah. Branch kerja ini berawal dari integrasi
`8fb366ad7452daf5ef7d4cc77f2710ab7bc9be5a`; belum ada push ke branch bersama.

## Temuan dan perubahan sementara

Kedua warga awal sebelumnya mulai pada Satisfaction 50%, tepat pada ambang
Job Board. Setelah satu hari tanpa semua kebutuhan, keduanya turun ke 45% dan
hilang dari daftar sebelum kunjungan merchant pertama dapat digunakan oleh
rute yang diuji. Ini bukan softlock permanen: pemain masih dapat bekerja
sendiri, memperoleh makanan/pakaian, membangun rumah dan memulihkan mereka.
Namun rute itu panjang dan alasannya tidak jelas pada Job Board.

Untuk review Game Director, **hanya dua warga awal yang baru dibuat** kini
mulai pada 55%. Satu hari kebutuhan tidak lengkap menurunkan mereka ke ambang
50%; satu hari berikutnya tetap menurunkan mereka ke 45% dan menghapusnya dari
daftar. Ambang, perubahan Satisfaction harian, harga, kontrak dan kebutuhan
tidak berubah. Registrasi tidak mengubah warga yang sudah ada, sehingga save
lama tidak otomatis mendapat buffer. Ini memberi kesempatan saat kunjungan
merchant pertama, bukan jaminan bila kunjungan terlewat. Nilai dan tempo tetap
perlu review balance manusia.

Saat Job Board kosong karena calon yang dapat kembali memiliki Satisfaction
di bawah ambang, panel menjelaskan Food, Clothing, Shelter, pemulihan harian
dan ambang 50%. Kota kosong, Hauler legacy yang tidak direkrut, dan warga yang
sudah dipekerjakan tetap mendapat pesan kosong umum; pengujian mencakup kondisi
tersebut. [Board awal](evidence/starter-city-playability-2026-11-04/job-board-initial.png)
dan [petunjuk saat pelamar tidak memenuhi syarat](evidence/starter-city-playability-2026-11-04/job-board-needs-hint.png)
direkam pada viewport logis 400×225 dengan GL Compatibility/llvmpipe.

## Perjalanan dari New Game

`WalkedCityJourney` **PASS write/read** dari slot baru tanpa grant barang,
uang, tenaga kerja, teleport, proteksi debug, perubahan kecepatan jalan atau
perubahan aturan kebutuhan. Driver memakai input gerak dan collision normal,
interaksi E, dialog penjaga, dan kontrol UI. Driver mengetahui lokasi tujuan;
pengujian ini bukan pengganti penilaian apakah manusia dapat menemukan langkah
tersebut tanpa petunjuk.

- Pemain memanen kurma, menjual kayu, membeli dan menyetor pakaian, memenuhi
  makanan warga, lalu membangun rumah dengan material dari Inventory. Kedua
  warga kembali memenuhi kebutuhan dan memenuhi syarat rekrut pada hari 5;
  rumah memerlukan 17 sesi kerja pada rute ini.
- Setelah perdagangan berikutnya, pemain merekrut worker melalui Job Board,
  membayar kontrak sembilan hari, memilih worker pada UI plot, dan membersihkan
  lahan. Workshop dimulai hanya setelah biaya Wood, Clay dan Reed dipotong dari
  Inventory pemain. Worker memakai shift dan kedatangan yang sebenarnya.
- Worker diperpanjang sekali dengan uang hasil perdagangan. Workshop selesai
  pada hari 18, setelah sekitar 72.162 pixel berjalan pada rute penguji. Ini
  hasil satu perjalanan, bukan waktu minimum atau penilaian balance final.
- Tidur membuat checkpoint. Pada proses baru, Continue memulihkan snapshot,
  rumah dan workshop; pemain berjalan ke workshop, mengumpulkan Straw dan Water,
  lalu memasukkan satu batch Clay/Straw/Water ke workshop melalui UI. Debit tas
  dan penerimaan workshop diperiksa masing-masing tepat sekali.

Perjalanan dimulai dengan waktu nyata permainan untuk gerak dan menunggu.
Penguji sempat dihentikan saat memperbaiki driver, kemudian melanjutkan dari
checkpoint tidur asli pada hari 5, 7 dan 9. Sidecar hanya menyimpan penghitung
penguji dan hash checkpoint; tidak mengubah state permainan. Dari hari 9,
10.110 menit **diam** dipercepat satu per satu melalui sinyal waktu dan
perjalanan worker yang sudah ada. Pekerjaan, tidur, kebutuhan, biaya dan semua
pergerakan pemain tetap memakai mekanisme permainan. Run ini menunjukkan jalur
state yang dapat dicapai, bukan playthrough manusia atau verifikasi wall-clock
untuk setiap menit menunggu.

Pengujian juga menemukan dua masalah pada *driver*: titik Reed pertama berada
dalam area City Storage, dan setelah menyelesaikan rumah player perlu bergerak
keluar dari overlap collision sebelum planner menghitung rute. Titik alternatif
dan input gerak bawah yang sebenarnya lulus; tidak ada teleport atau perubahan
collision produksi untuk mengatasi keduanya. Driver juga kini menjawab sapaan
penjaga workshop sebelum membuka menu, seperti alur permainan.

## Deposit bahan dan hauler

Pembatasan deposit manual tidak menghalangi alur yang diminta untuk produksi
**Daily worker → City Storage → storage kota lain**. Receipt produksi menerima
Wood, Clay, Reed, Straw dan Water; transport kota memeriksa jenis cargo-nya
sendiri. `CityStorageTransportFlow` write/read **PASS**, termasuk pengiriman
keempat bahan selain Wood, pembatalan dan Continue. `MultiWorkerCitySupply`
write/read **PASS** dengan pemeriksaan dua worker dan akhir shift.

Pembatasan tetap berarti pemain **tidak dapat menyetor Clay, Reed, Straw atau
Water pribadinya langsung** ke City Storage. Hasil Hourly tetap dapat dipakai
untuk konstruksi pribadi, tetapi tidak dapat masuk rute hauler lewat deposit
manual itu. Tidak ada perluasan filter pada perubahan ini: City Storage tidak
menyediakan penarikan pribadi, sehingga mengizinkan transfer satu arah baru
memerlukan keputusan kepemilikan/UX tersendiri bila alur tersebut diinginkan.

## Regresi dan batasan

- `StarterRecruitmentTest` **PASS** untuk 55% → 50% → 45%, eligibility,
  registrasi ulang, dan save/load tanpa reset nilai.
- Run `ContractJourney` baru dari New Game, tanpa grant atau seed paksa,
  berhasil menjual tiga Wood pada hari 1, merekrut pada tepat 50%, membayar satu
  Shekel, menugaskan Daily dan menerima output pertama. Run tersebut sengaja
  dihentikan sebelum tahap kontrak penuh agar perjalanan workshop dapat diuji;
  jangan membacanya sebagai PASS keseluruhan tes kontrak itu.
- `CityResidentTest` headless dan grafis, `DebugResidentNeedsTest`,
  `ApplicantEligibilityTest`, `PopulationEmploymentIntegrationTest`,
  `CityStorageMaterialConsumptionTest`, `CityStorageOverflowTest`,
  `WorldLifeAnimationTest`, dan perjalanan kebutuhan write/read **PASS**.
  Fixture DebugResidentNeeds secara eksplisit memakai 50% untuk mempertahankan
  pemeriksaan lama tentang pemulihan dari 45%; ia bukan grant di New Game.
- Checkpoint perjalanan kebutuhan yang dibuat pada commit integrasi sebelumnya
  juga **PASS Continue**, termasuk perbandingan snapshot, tanpa migrasi schema.
- `InitialWorkshopStartTest` **FAIL** pada dua assertion: penyelesaian workshop
  lewat satu lompatan tiga hari dan satu pelamar yang diharapkan tetap eligible.
  Pengulangan pada commit `8fb366a` sebelum perubahan ini menghasilkan dua
  kegagalan yang sama. Fixture lama tidak mengikuti shift/arrival dan penurunan
  kebutuhan yang sekarang berlaku; ini bukan regresi baru yang terbukti.
- Mayoritas regresi cepat dijalankan pada salinan proyek sementara yang hanya
  menghilangkan autoload bridge debug Godot agar dapat berjalan bersamaan;
  `project.godot` pada repository tidak berubah. Perjalanan berjalan kaki utama
  memakai proyek asli dengan data XDG terisolasi.

Uji Windows/Android, penilaian manusia atas kemudahan menemukan alur, dan
persetujuan akhir nilai 55% masih diperlukan.
