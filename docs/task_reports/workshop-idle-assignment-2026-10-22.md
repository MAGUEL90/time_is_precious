# Workshop idle assignment setelah Continue

Tanggal 2026-10-22, Asia/Jakarta. Branch `fix/economy/workshop-idle-assignment-continue`,
baseline `52db252d1f25d47f7033d8f062b5fd901ed8e83b` (#119), tree awal bersih.
Cloud saja, Godot4.5.1; tidak akses laptop, merge main atau force-push.

## Kontrak dan akar masalah

Pengguna mengizinkan lanjut untuk memperbaiki batas yang dilaporkan #119: setelah
Continue, worker idle kadang perlu dipilih ulang di workshop lalu dilepas sebelum
Fire. Risiko LEVEL3 karena persistensi status employment; otorisasi mencakup fix
ini, bukan perubahan desain worker, balance, tarif, fee, filter atau ownership.

`WorkShop.assigned_worker_ids` adalah pilihan scene/UI, tidak diserialisasi oleh
CitySave. Akan tetapi CitizenData.employment_status ikut disimpan. Kombinasi worker
IDLE tanpa current_order_id dan citizen ASSIGNED dapat dipulihkan tanpa pemilik
penugasan. Guard Worker Hub lalu menolak Fire karena mengira pilihan workshop ada.
Tidak ada alasan untuk melonggarkan guard pada pekerjaan aktif.

## Perbaikan terbatas

Satu file runtime berubah: `scenes/new_scenes/save_game/city_save_state.gd`.
Snapshot baru dan prepare save lama menormalkan hanya worker hired yang:

- memiliki citizen berstatus ASSIGNED;
- tidak memiliki reservasi (`current_order_id` kosong);
- memiliki WorkStatus.IDLE.

Status citizen pada payload menjadi HIRED. Resource citizen yang terpengaruh dan
mapping-nya disalin; capture/prepare tidak mengubah draft atau Resource runtime.
WorkerData, payroll, uang, kebutuhan, tools, input/output dan timestamp tidak diubah.
Worker reserved, working, travelling maupun standing assignment tetap utuh, termasuk
pekerjaan yang dijeda payroll. Dismissed citizen tidak masuk normalisasi ini.

Schema tetap6, format/field unchanged, v1–v5 tetap melalui migrasi eksplisit yang
sudah ada. Reader memperbaiki status transient setelah validasi; file lama tetap
utuh sampai save eksplisit. Ini tidak memulihkan pilihan UI workshop yang memang
tidak disimpan, dan tidak melepas pilihan aktif saat pemain masih berada di scene.

Root menangani keputusan dan review. Subagen Luna XHigh sesuai AGENTS menulis
fixture terisolasi. Keterbatasan root tidak dapat berganti ke Astra telah disampaikan
pada tahap sebelumnya; tidak mengklaim pergantian model/reasoning.

## Perjalanan normal

Driver dismissal diperbarui untuk langsung membuka Worker Hub setelah Continue;
workaround membuka workshop/pilih ulang/lepas telah dihapus. Expected snapshot
mengizinkan hanya koreksi eksplisit citizen idle tersebut; field lain tetap sama.
Driver renewal juga mengenali koreksi tersebut untuk source earned v5/v6 lama.

Sumber adalah checkpoint earned H11 15:29 dari tahap renewal (dompet6/kas0,
paid H11–H17), SHA256
`2cb6d49aaf0257ec32e7a239ecbfea408e1d939a1aba9806e873929d947b908f`.
Tidak ada grant, teleport, perubahan clock/needs/RNG/rates. Kebutuhan tetap aktif.

- write: Continue memperbaiki status, Worker Hub No lalu Yes berhasil langsung,
  dompet6/kas0 tetap. Bed menyimpan H12 07:11 (menit17711), worker archived.
- read: proses baru memulihkan checkpoint dismissed, lalu keluar rumah dan upkeep
  sampai H12 07:48 (menit17748). Barang workshop tetap15 dry+14 wet, tas5 dry.

Kedua proses final exit0, PASS, tanpa warning/error/leak. Bukan New Game baru pada
perjalanan normal ini; fixture terpisah memakai New Game dan grant eksplisit.
Tidak ada perubahan UI visual sehingga screenshot konfirmasi #119 tetap relevan.

## QA final dan review

Status: **PASSED — NEEDS HUMAN REVIEW**. Total 21 proses perilaku PASS, exit0,
tanpa warning/error pada log perilaku, memakai Godot4.5.1:

- 2 perjalanan normal dismissal write/read, kebutuhan aktif, seperti di atas;
- 2 fixture idle-assignment write/read: New Game, capture murni, prepare v6 lama,
  guard draft sebelum load, Continue proses baru dan Fire langsung tanpa refund;
- 4 dismissal Continue (write, rehire, pay, expired);
- 4 renewal Continue (write, expire, resume, finish);
- 3 paid-production Continue (write, shape, dry);
- 4 cargo Continue (write, paused, resume, deliver);
- 1 population employment dan 1 workshop construction.

Fixture baru secara eksplisit memberi uang3, deposit2, entitlement H2–H8,
XP/condition dan bahan3 per item; clock dibekukan dan profesi job fixture disesuaikan.
Ini bukan bukti perjalanan ekonomi normal. Probe prepare payroll-expired tidak
menjalankan load; regresi renewal/cargo terpisah menguji paused/resume aktual.
Driver perjalanan normal renewal ikut diperbarui expected snapshot-nya tetapi
tiga fase perjalanan normal renewal tidak diulang pada tahap ini.

Impor editor final exit0 tanpa parse error. Satu warning diketahui: UID
`mvp_first_playthrough.gd` yang tidak terlacak dibuat ulang dari cache. Artefak
import di luar cakupan dibuang setelah validasi; setting project/addon tidak berubah.

Root meninjau seluruh runtime diff dan fixture subagen; normalisasi hanya setelah
validasi, tidak memutasi Resource live, tidak melemahkan guard Fire, tidak mengubah
format save atau tarif. `git diff --check` lulus. Bukti log dan hasil normal tersedia
di `evidence/workshop-idle-assignment-2026-10-22/`; perintah fixture ada di
`scenes/test_scenes/README.md`. Review manusia tetap diperlukan sebelum merge.
