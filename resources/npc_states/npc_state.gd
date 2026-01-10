class_name NPCState extends Resource

@export var npc_id: String = "" # ID unik NPC untuk mapping save/load (harus sama dengan NPCData.id)
@export var current_position: Vector2 = Vector2.ZERO # Simpan Posisi Terkini
@export var last_position: Vector2 = Vector2.ZERO # Simpan Posisi Terakhir

@export_range(0.0, 1.0, 0.01) var current_satisfaction: float = 1.0 # kepuasan runtime, diberi default aman 1.0
@export_range(0.0, 1.0, 0.01) var trust: float = 0.0 # trust runtime (akan kepakai untuk unlock kerja/contract/relationship)

@export var active_contract_id: String = "" # kontrak aktif (simpan ID saja, jangan simpan Node/Resource berat)
@export var last_updated_day: int = 0 # penanda kapan terakhir state ini di-update (berguna untuk daily reset/decay)
