# Panduan TileSet untuk Content Scene

Status audit: statis, 2026-09-13. Panduan ini ditulis untuk Godot 4.5 dan struktur project saat ini. Tidak ada proses import, launch, atau test Godot yang dijalankan dalam audit ini.

## Peta resource yang harus diketahui

| Area | Node | TileSet / source | Tekstur | Catatan |
| --- | --- | --- | --- | --- |
| Kota, lapisan ground | `scenes/content_scene/content_scene.tscn` → `Ground/water`, `Ground/base`, `Ground/base2` | TileSet bawaan `TileSet_t5r06`; source ID `0` dan `4` | `assets/tile_set/tileset_base.png` dan `assets/tile_set/tileset_base_17.06.2026.png`, masing-masing `160×128` | Ketiganya menunjuk TileSet bawaan yang sama di scene. Tidak ada physics, navigation, terrain, occlusion, atau custom-data layer pada TileSet ini. |
| Kota, objek | `scenes/content_scene/content_scene.tscn` → `YSortWorld/object` | `res://scenes/content_scene/object_tile_set.tres`, UID `uid://dmedjrf3am34i`; source ID `1`; `alternative ID 0` | `assets/objects/object_17.06.2026.png`, `426×240` | Resource eksternal dan dipakai bersama oleh scene interior. |
| Rumah, furniture | `scenes/player_home_interior/player_home_interior.tscn` → `YSortWorld/Furniture` | Resource eksternal yang sama: `object_tile_set.tres`, source ID `1` | `object_17.06.2026.png` | Mengubah metadata TileSet ini dapat mengubah kota dan furniture rumah sekaligus. |
| Rumah, floor/walls | `player_home_interior.tscn` → `Ground/Floor`, `Ground/Walls` | TileSet bawaan terpisah; source ID `0` | `assets/temporer/tile_set/test_tile_set.png`, `128×752` | `Walls` memiliki physics layer 0 (`collision_layer=1`, `collision_mask=0`); `Floor` tidak memiliki physics layer pada file scene. |

`TileSet` dan `TileSetAtlasSource` tidak menetapkan ukuran khusus di file-file ini. Nilai default Godot 4.5 adalah `tile_size` dan `texture_region_size` `16×16`; koordinat atlas ditulis sebagai `x:y/0`. Karena itu, jangan menyimpulkan bahwa semua piksel pada PNG adalah tile yang boleh dipakai. Pada atlas objek, PNG berukuran `426×240`, tetapi hanya koordinat yang tercantum di bawah yang merupakan tile terdaftar.

## Koordinat yang sudah menjadi kontrak

Ground kota menyimpan semua tile dengan alternative ID `0`.

- Source `0` (`TileSetAtlasSource_nji41`, `tileset_base.png`, 64 tile): `y0={0,1,2,5,6,7}`, `y1={0..9}`, `y2={0..9}`, `y3={0,1,2,5,6,7}`, `y4={0..9}`, `y5={0..9}`, `y6={0..5}`, `y7={0..5}`.
- Source `4` (`TileSetAtlasSource_ihkwn`, `tileset_base_17.06.2026.png`, 70 tile): baris yang sama, tetapi `y6={0..8}` dan `y7={0..8}`.

Atlas objek (`object_tile_set.tres`) memiliki 82 tile terdaftar:

```text
y0:  x10
y6:  x2..8
y7:  x1..8
y8:  x2..8
y9:  x4, x6..8
y10: x2, x6..12
y11: x1..12
y12: x1..6, x8..12
y13: x1..12
y14: x1..12
```

Semua koordinat di atas menggunakan source ID `1` dan alternative ID `0`. Nilai `y_sort_origin` sudah ditentukan pada 75 dari 82 tile. Kelompok pentingnya adalah `y6: x2..4=8, x5..6=24, x7..8=56`; `y7: x1..6=8, x7..8=40`; `y8: x2..5=8, x6..8=24`; `y10: x6..7=24, x8..12=72`; `y11: x6..7=8, x8..12=56`; `y12: x1..6=8, x8..12=40`; `y13: x1..7=8, x8..12=24`; dan `y14: x1..12=8`. Nilai ini ikut menentukan urutan gambar pada `TileMapLayer` yang mengaktifkan Y-sort.

30 tile objek memiliki polygon collision pada physics layer 0:

```text
y6:  x5..6
y7:  x2..6
y8:  x2..5
y9:  x4, x6..8
y10: x6..7
y11: x6..8, x12
y12: x8, x12
y13: x8, x12
y14: x8..12
```

Physics layer resource ini memakai `collision_layer=1` dan `collision_mask=0`. Tidak ada `terrain_set`, terrain peering, `navigation_layer`, occlusion polygon, atau custom-data layer pada `object_tile_set.tres`. Jadi collision dan y-sort di atas adalah metadata TileSet yang nyata; navigation tidak berasal dari atlas ini.

## Tempat edit yang aman

Untuk repaint atau retexture, pertahankan kontrak berikut: ukuran PNG, grid `16×16`, margin/separation atlas, posisi setiap objek pada koordinat `x:y`, transparansi sel yang memang kosong, source ID, alternative ID `0`, collision polygon, dan `y_sort_origin`. Mengganti warna atau menggambar ulang isi sel pada posisi yang sama biasanya mempertahankan seluruh pemetaan dan metadata. Pastikan siluet baru masih cocok dengan polygon collision yang lama; repaint yang lebih lebar atau lebih tinggi dapat membuat collider tidak lagi sesuai meskipun ID tidak berubah.

Edit ground melalui TileSet bawaan `TileSet_t5r06` di `content_scene.tscn`. Karena `water`, `base`, dan `base2` menunjuk subresource yang sama, perubahan definisi TileSet pada salah satu layer berlaku untuk ketiganya. Painting sel pada salah satu `TileMapLayer` mengubah `tile_map_data` milik layer tersebut, bukan definisi TileSet bersama; pastikan panel TileMap sedang berada pada layer yang dimaksud.

Edit objek/furniture melalui `object_tile_set.tres` bila perubahan memang harus berlaku untuk kota dan rumah. Jika hanya kota yang perlu varian, buat salinan TileSet atau gunakan `Make Unique` pada properti TileSet milik `YSortWorld/object`, lalu pastikan `content_scene.tscn` benar-benar menunjuk salinan tersebut. Ini adalah fork resource: perubahan berikutnya pada `object_tile_set.tres` tidak otomatis menyegarkan salinan kota, sehingga path dan pemilik resource harus dicatat dengan jelas.

Salinan TileSet tidak otomatis memberi salinan file PNG. Jika gambar kota harus berbeda dari gambar rumah, simpan PNG varian dan pastikan atlas pada TileSet salinan memakai PNG tersebut. Periksa juga resource atlas di dalamnya agar perubahan metadata tidak masih mengarah ke resource bersama.

Mengubah `tile_size`, `texture_region_size`, margin, separation, atlas source ID, koordinat tile, alternative ID, atau footprint multi-sel adalah perubahan layout dan berisiko tinggi. Godot dapat kehilangan tile yang berada di luar geometri atlas baru; cell lama di `tile_map_data` tetap menyimpan ID lama dan dapat tampil sebagai placeholder tile yang hilang. Jangan menghapus atau memindahkan tile terdaftar hanya untuk merapikan PNG. Bila relokasi ID memang diperlukan, siapkan pemetaan pada **Manage Tile Proxies** lalu migrasikan/repaint cell yang terdampak. Alternative ID yang berubah juga memutus TileMap yang sudah menggunakannya.

## Navigation dan batas movement saat ini

`content_scene.tscn` memiliki satu `NavigationRegion2D` bernama `CitizenWanderRegion` dengan `NavigationPolygon_v5dai`. `CitizenActor` menunggu sinkronisasi NavigationServer, meminta titik acak dari navigation map, lalu mengikuti `NavigationAgent2D`. Ground dan object TileSet tidak memiliki navigation layer. Karena polygon navigation ini terpisah dari collision polygon objek, mengubah atau menambah collider objek tidak otomatis membuat area itu terlarang bagi warga.

Ada batas tambahan pada implementasi saat ini: root `CitizenActor` adalah `Node2D`, dan geraknya menetapkan `global_position` langsung setelah meminta path. Static audit ini mendukung kesimpulan bahwa collider TileMap belum menjadi penghindar fisika warga secara umum. Player dan objek masih perlu mematuhi konfigurasi physics layer/mask yang berlaku. Jika navigasi kota diperluas, desain harus memilih satu sumber navigasi yang konsisten, lalu memeriksa polygon, layer `npc_navigation`, dan perilaku agent bersama-sama. Dokumentasi Godot juga memperingatkan bahwa navigasi bawaan TileMap memiliki keterbatasan pathfinding/path-following dan menyarankan mesh yang dibake melalui `NavigationRegion2D` atau `NavigationServer2D` untuk kasus yang membutuhkannya.

Worker worksite dan Hauler memakai pergerakan lurus berbasis waktu dari MVP, belum pathfinding menghindari bangunan. Saat memindahkan `Worksites/WorkerDeparture`, worksite, atau storage, sediakan jalur terbuka di antaranya. Jangan menaruh tembok di jalur tersebut dengan asumsi worker akan otomatis memutar. Slot/kapasitas dan perilaku pengiriman tidak ditentukan oleh TileSet.

## Checklist sebelum menyerahkan perubahan

1. Periksa `git status` dan diff; ubah hanya resource/asset yang memang dimaksud. Jangan menimpa edit lokal lain.
2. Jika repaint, pastikan dimensi, grid, posisi objek, dan nama/path texture tetap sesuai. Periksa ulang 82 koordinat atlas objek dan tile yang dipakai pada kedua scene.
3. Buka TileMap editor pada `content_scene/YSortWorld/object` dan `player_home_interior/YSortWorld/Furniture`; pastikan tidak ada placeholder tile yang hilang.
4. Tampilkan collision debug atau buka polygon editor untuk memastikan 30 collider tetap berada di tile yang tepat; periksa juga y-sort pada objek multi-sel.
5. Jika layout atau ID berubah, simpan rencana proxy/migrasi dan baca ulang `tile_map_data` setelah semua cell dipetakan. Jangan menganggap scene tetap benar hanya karena editor berhasil menyimpan.
6. Setelah perubahan resource stabil, validasi terpisah di kota dan rumah: visual, gerak player, blocking collider, urutan gambar, dan jalur warga. Audit ini belum menjalankan langkah runtime tersebut.

## Rujukan resmi Godot 4.5

- [Using TileSets](https://docs.godotengine.org/en/4.5/tutorials/2d/using_tilesets.html): ukuran atlas, margin/separation, collision/navigation, alternative tile, dan tile proxy.
- [TileSet](https://docs.godotengine.org/en/4.5/classes/class_tileset.html): source ID, atlas coordinate ID, alternative ID, dan default `tile_size=16×16`.
- [TileSetAtlasSource](https://docs.godotengine.org/en/4.5/classes/class_tilesetatlassource.html): grid atlas, alternative ID `0`, dan default `texture_region_size=16×16`.
- [Using TileMaps](https://docs.godotengine.org/en/4.5/tutorials/2d/using_tilemaps.html): resource eksternal untuk reuse, batas navigation TileMap, dan placeholder saat ID tile hilang.
- [Resource](https://docs.godotengine.org/en/4.5/classes/class_resource.html) serta [Creating instances](https://docs.godotengine.org/en/4.5/getting_started/step_by_step/instancing.html): resource sharing, `resource_local_to_scene`, dan **Make Unique**.
