class_name NPCData extends Resource

# ============= IDENTITY
@export_category("Identity") # identitas NPC
@export var id: String = "" # ID unik & stabil (harus cocok dengan NPCStates.npc_id untuk save/load)
@export var npc_name: String = "" # nama tampilan NPC
@export var role: String = "" # peran/kelas NPC (pedagang, pekerja, dsb)

# ============= DIALOUGE
@export_category("Dialouge")
@export var unique_dialogue : DialogueResource

# ============= SATISFACTION
@export_category("Satisfaction")
@export_range(0.0, 1.0, 0.01) var min_limit_satisfaction: float = 0.0 # batas bawah
@export_range(0.0, 1.0, 0.01) var max_limit_satisfaction: float = 1.0 # batas atas
@export_range(0.0, 1.0, 0.01) var initial_satisfaction: float = 1.0 # nilai awal

# ============= WORK & CONTRACT
@export_category("Work & Contract")
@export var base_wage: float = 0.0  # upah dasar (template); perhitungan uang sebaiknya pakai state/runtime
@export var work_duration_day: int = 0 # durasi kerja per hari (template)
@export var allow_contract: bool = false # artinya: NPC ini "bisa menawarkan" kontrak (bukan izin runtime per jam/cuaca)
@export var work_start_hour: int = 8 # jam kerja mulai (rencana kamu: tiap NPC unik) — template
@export var work_end_hour: int = 17 # jam kerja selesai — template
@export_range(0.0, 1.0, 0.01) var contract_difficult: float = 0.0 # tingkat sulit kontrak (template)
# INI HINT, BARIS KE BERAPA AKU?
# ============= NEEDS
@export_category("Needs") 
@export var needs: Dictionary = {
	"food": {"grade_A": 0.0, "grade_B": 0.0, "grade_C": 0.0, "grade_D": 0.0},
	"clothes": {"clothes": 0.0, "sandals": 0.0, "pants": 0.0, "accesories": 0.0},
	"house": {"hut": 0.0, "house": 0.0, "mansion": 0.0, "elite_mansion": 0.0},
	"shekel": {"bronze": 0.0, "silver": 0.0, "gold": 0.0},
}

func clamp_satisfaction(value: float) -> float: # helper: jaga kepuasan tetap dalam limit data NPC
	return clamp(value, min_limit_satisfaction, max_limit_satisfaction) # penting untuk stabilitas saat banyak sistem mengubah satisfaction
