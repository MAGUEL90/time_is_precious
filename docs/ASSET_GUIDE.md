# ASSET GUIDE — Time is Precious

Version: v0.1  
Focus: modular character assets, worker clothing, hair, headgear, accessories, and small item icons.

---

## 1. Core Direction

The visual direction is:

- Mesopotamian-inspired
- earthy, old-world, practical
- small-pixel readable
- modular and reusable
- clean enough for production, not over-detailed

Current asset rule:

> Main canvas maximum: **16x16 px**  
> Actual occupied size may be smaller, such as **4x10**, **8x11**, **14x16**, etc.

Do not force every asset to fill 16x16. The 16x16 canvas is the container, not the visible object size.

---

## 2. Canvas & Size Rules

### Standard Canvas

| Asset Type | Canvas | Notes |
|---|---:|---|
| Head parts | 16x16 | Face, hair, expression, head accessories |
| Body parts | 16x16 | Torso/body variants |
| Clothing/body outfit | 16x16 | Garment may occupy 8–14 px wide |
| Headgear/accessory | 16x16 | Often only 4–12 px wide/tall |
| Small resource icon | 16x16 | Use simple silhouette |
| Tool icon | 16x16 | May occupy diagonal or horizontal area |
| UI inventory icon | 32x32 optional | Only when needed later |

### Important

- Keep a transparent background.
- Keep assets pixel-perfect.
- No blur.
- No anti-aliasing.
- No soft brush.
- No semi-transparent pixels unless intentionally documented.

---

## 3. Occupied Size Rule

Because the assets are modular, record both:

- **Canvas size**
- **Actual size**

Example:

```text
canvas_size: 16x16
actual_size: 8x11
```

Examples:

| Asset | Canvas | Actual Size | Acceptable? |
|---|---:|---:|---|
| Small earring | 16x16 | 4x10 | Yes |
| Headband | 16x16 | 10x3 | Yes |
| Hair cap | 16x16 | 8x6 | Yes |
| Body torso | 16x16 | 5x7 | Yes |
| Worker tunic | 16x16 | 10x14 | Yes |

The asset is not wrong because it is smaller than the canvas. It is wrong only if it is unreadable, misaligned, or inconsistent.

---

## 4. Alignment Rules

Use consistent alignment so modular parts can stack cleanly.

### Character modular parts

| Part | Alignment Rule |
|---|---|
| Head | Centered horizontally |
| Hair | Align to head top |
| Expression | Align to face base |
| Body | Align below head, centered |
| Head accessory | Align to hair/head top |
| Clothing | Align to body anchor |

### Recommended anchor mindset

Use **center-bottom logic** for character parts:

```text
16x16 canvas
asset sits inside canvas
bottom or face/body connection point must stay consistent
```

If an asset has different actual dimensions, do not randomly center it if it needs to connect to another part.

---

## 5. Naming Convention

Use lowercase snake_case.

Format:

```text
category_tier_name_size.png
```

Examples:

```text
clothing_poor_clay_worn_wrap_16x16.png
clothing_common_worker_linen_tunic_16x16.png
clothing_better_dyed_wool_tunic_16x16.png

headgear_poor_frayed_headband_16x16.png
headgear_common_worker_headwrap_16x16.png
headgear_better_trimmed_headcloth_16x16.png

hair_black_short_cap_16x16.png
hair_brown_side_part_16x16.png
expression_light_neutral_16x16.png
body_light_base_16x16.png
```

Avoid:

```text
asset1.png
newfinal.png
baju_fix2.png
hairbaru.png
```

---

## 6. Status Progression

Every asset must have one status.

```text
IDEA → SKETCH → DRAFT → REVIEW → APPROVED → EXPORTED → IN_GAME
```

| Status | Meaning |
|---|---|
| IDEA | Name/concept exists only |
| SKETCH | Rough pixel shape exists |
| DRAFT | Usable draft exists |
| REVIEW | Needs checking for palette, size, style, readability |
| APPROVED | Accepted visually |
| EXPORTED | Final PNG exported correctly |
| IN_GAME | Already placed/tested in Godot |

Do not create many random assets without status. Every asset must move through this pipeline.

---

## 7. Category List

Use these categories first:

```text
head
body
expression
hair
accessory
headgear
clothing
pants
tool
resource
building_material
ui_icon
```

For now, prioritize:

```text
1. head
2. body
3. expression
4. hair
5. accessory/headgear
6. clothing
7. pants
8. tools
9. resources
```

Do not expand too fast into buildings, NPC variants, and decorative items until the character base set is stable.

---

## 8. Readability Rules for 16x16

At 16x16, every asset needs one main readable idea.

Good:

- one clear silhouette
- one clear outline
- one or two strong internal details
- 3–6 colors
- strong contrast between outline, shadow, base, highlight

Bad:

- too many folds
- too many stains
- too many tiny trims
- too many similar browns
- unclear shape
- weak silhouette

---

## 9. Clothing Rules

For small worker clothing, use only 1–2 major visual identifiers.

Examples:

| Clothing | Main Identifier |
|---|---|
| Clay-Worn Wrap | V-neck + patch |
| Frayed Tunic | torn hem |
| Worker Linen Tunic | cleaner body + belt |
| Cross-Wrap Tunic | diagonal chest fold |
| Dyed Wool Tunic | ochre cloth + red-brown trim |

Do not draw 64x64 details directly into 16x16. Redesign the idea for the smaller size.

---

## 10. Headgear & Accessory Rules

Head accessories should not overpower the face.

Good identifiers:

- headband = thin horizontal strip
- headwrap = thicker curved shape
- cap = rounded top shape
- hood = larger silhouette around head
- earring = tiny vertical accent

At 16x16, avoid excessive stitches, knots, and fabric folds unless they are readable.

---

## 11. Export Rules

Recommended folder structure:

```text
assets/
├─ aseprite/
│  ├─ character/
│  ├─ clothing/
│  ├─ headgear/
│  ├─ hair/
│  ├─ tools/
│  └─ resources/
│
├─ export/
│  └─ 16x16/
│     ├─ head/
│     ├─ body/
│     ├─ expression/
│     ├─ hair/
│     ├─ accessory/
│     ├─ clothing/
│     └─ tool/
│
└─ reference/
   ├─ approved_style/
   └─ concept_sketch/
```

Keep `.aseprite` source files separate from exported PNG files.

---

## 12. Asset Review Checklist

Use this before approval:

```text
[ ] Correct canvas size
[ ] Actual size recorded
[ ] Transparent background
[ ] No blur / no anti-alias
[ ] Uses official palette or approved exception
[ ] Outline is readable
[ ] Silhouette is clear
[ ] Fits Mesopotamian theme
[ ] Naming follows convention
[ ] Status updated in registry
[ ] Exported PNG matches source
[ ] Tested visually at actual game size
```

Decision options:

```text
APPROVED
REWORK
REJECT
```

---

## 13. Current Production Priority

Worker Set v0.1:

```text
- clothing_poor_clay_worn_wrap
- clothing_poor_frayed_tunic
- clothing_common_worker_linen_tunic
- clothing_better_dyed_wool_tunic
- pants_poor_clay_worn_pants
- headgear_poor_frayed_headband
- headgear_common_worker_headwrap
- headgear_common_simple_work_hood
```

Do not chase quantity yet. Build a clean, consistent first set.
