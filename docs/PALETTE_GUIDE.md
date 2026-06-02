# PALETTE GUIDE — Time is Precious

Version: v0.2  
Direction: Mesopotamian-inspired earthy palette for small pixel assets.

---

## 1. Palette Philosophy

The world should feel:

- sun-baked
- clay-heavy
- linen-based
- ancient
- practical
- warm but not cartoonish

Use controlled colors. The goal is consistency, not color chaos.

At 16x16, too many colors make the asset noisy. Most assets should use:

```text
3–6 colors + transparency
```

Important rule:

> Skin and clothing must not use the same main base/highlight colors.  
> Skin should feel warmer and alive. Cloth should feel dustier, flatter, and more worn.

Do not treat the Aseprite checkerboard/background colors as game palette colors.

---

## 2. Core System Colors

| Name | Hex | Use |
|---|---|---|
| Primary Outline | `#191919` | main sprite outline |
| UI Black | `#000000` | UI text/debug only, not normal sprite outline |
| UI White | `#FFFFFF` | UI text/highlight only, use sparingly |
| Transparent | alpha | background for exported assets |

Use `#191919` as the default outline for most assets.

---

## 3. Official Color List — Current Game Palette

These are the approved colors used or discussed so far.

| Name | Hex | Family | Use |
|---|---|---|---|
| Primary Outline | `#191919` | Core | main outline |
| Deep Warm Shadow | `#0F0606` | Shadow / Hair | deepest dark accent |
| Dark Clay Shadow | `#312210` | Earth / Skin / Hair | dark brown shadow |
| Earth Shadow | `#5E4630` | Skin / Cloth | tan/dark skin shadow, cloth shadow |
| Clay Cloth Shadow | `#6E5638` | Poor Cloth | clay-worn wrap shadow |
| Mud Brown | `#4F4B4B` | Hair / Shadow | gray-brown shadow, dark gray hair |
| Ash Gray Light | `#716C6C` | Hair | ash gray hair highlight |
| Brick Maroon | `#3C1B1B` | Hair / Trim | dark red hair, trim |
| Maroon Mid | `#5A2A2A` | Hair | dark red hair midtone |
| Maroon Light | `#7A3A2A` | Hair | dark red hair highlight |
| Dark Brown Hair | `#4D310F` | Hair | brown hair shadow |
| Clay Brown | `#88693A` | Skin / Rope / Dirt | tan skin, rope, dirt, patch |
| Clay Cloth Base | `#A98B5A` | Poor Cloth | poor worker cloth base |
| Clay Cloth Light | `#C3A06A` | Poor Cloth | poor worker cloth highlight |
| Dust Olive | `#A59B79` | Headgear | old muted fabric |
| Linen Skin Shadow | `#A1927C` | Skin | light skin shadow |
| Dust Linen Shadow | `#8F826C` | Common Cloth | plain linen shadow |
| Dust Linen Base | `#B2A386` | Common Cloth | plain linen base |
| Linen Mid | `#C4B297` | Skin | light skin base only |
| Linen Cloth Light | `#CBB99A` | Common Cloth | plain linen highlight |
| Sand Ochre | `#C4A474` | Skin / Accent | warm skin highlight, muted gold accent |
| Linen Light | `#D9CDBB` | Skin / Highlight | skin highlight, rare cloth sparkle only |
| Muted Blue Gray | `#7D929E` | Rare Accent | rare cool accent |
| Soft Gold | `#D9A441` | UI / Logo Accent | muted gold highlight |
| Bright Gold | `#FFD35A` | UI / Logo Glow | glowing time/gold accent, use rarely |

---

## 4. Skin Palettes

Skin ramps are allowed to reuse warm earth tones, but they must stay visually separate from cloth.

### Light Linen Skin

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Shadow | `#A1927C` |
| Base | `#C4B297` |
| Highlight | `#D9CDBB` |

### Warm Sand Skin

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Shadow | `#88693A` |
| Base | `#C4A474` |
| Highlight | `#D9CDBB` |

### Clay Tan Skin

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Shadow | `#5E4630` |
| Base | `#88693A` |
| Highlight | `#C4A474` |

### Dark Earth Skin

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Shadow | `#312210` |
| Base | `#5E4630` |
| Highlight | `#88693A` |

### Skin Rule

Do not use the following as main cloth base/highlight when placed directly beside light skin:

```text
#C4B297
#D9CDBB
```

They may appear as tiny highlights only if the clothing shape remains readable.

---

## 5. Clothing Palettes

Clothing should look dustier and flatter than skin.

### Poor Worker — Clay-Worn Wrap / Clay-Worn Pants

Use for `clay_worn_wrap`, poor worker pants, damaged tunics, dusty cloth.

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Deep Shadow | `#312210` |
| Shadow | `#6E5638` |
| Dirt / Patch | `#88693A` |
| Base | `#A98B5A` |
| Highlight | `#C3A06A` |

Notes:

- Use one big readable patch, not many tiny dots.
- Keep it darker and earthier than light skin.
- Good for poor/rough NPC clothing.

### Common Worker — Plain Linen Wrap / Worker Linen Tunic

Use for `plain_linen_wrap`, `worker_linen_tunic`, simple common villager cloth.

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Deep Shadow | `#5E4630` |
| Shadow | `#8F826C` |
| Base | `#B2A386` |
| Highlight | `#CBB99A` |
| Belt / Rope | `#88693A` |

Notes:

- Cleaner than poor clothing.
- Still dusty/muted, not as alive as skin.
- Avoid using `#D9CDBB` as the main cloth highlight here.

### Better Worker / Overseer — Dyed Wool Tunic

Use for richer worker clothing, mandor/overseer, better-status garments.

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Shadow | `#312210` |
| Trim Dark Red | `#3C1B1B` |
| Belt / Trim Brown | `#88693A` |
| Ochre Base | `#C4A474` |
| Gold Accent | `#D9A441` |

Notes:

- Status should read through cleaner shape and stronger color.
- Use red-brown trim sparingly.
- Do not make worker clothing look royal too early.

---

## 6. Hair Palettes

Use 4–5 controlled hair families only.

### Obsidian Black

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Deep | `#0F0606` |
| Shadow | `#313030` |
| Mid | `#4F4B4B` |

### Ash Gray

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Shadow | `#313030` |
| Base | `#4F4B4B` |
| Highlight | `#716C6C` |

### Clay Brown

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Deep | `#312210` |
| Shadow | `#4D310F` |
| Base | `#88693A` |

### Date Palm Brown

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Shadow | `#4D310F` |
| Base | `#88693A` |
| Highlight | `#C4A474` |

### Brick Maroon

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Deep | `#0F0606` |
| Shadow | `#3C1B1B` |
| Base | `#5A2A2A` |
| Highlight | `#7A3A2A` |

Preferred early set:

```text
Obsidian Black
Ash Gray
Clay Brown
Brick Maroon
```

---

## 7. Eye Palettes

At 16x16, eyes should stay simple. Usually 1–2 pixels are enough.

| Name | Main | Optional Highlight | Use |
|---|---|---|---|
| Dark Eye | `#191919` | — | default eye |
| Deep Brown Eye | `#312210` | `#88693A` | warmer NPC eye |
| Amber Eye | `#88693A` | `#C4A474` | special warm eye |
| Ash Eye | `#4F4B4B` | `#716C6C` | older/calm NPC |

Default rule:

```text
Normal NPC eye: #191919
Special warm highlight: #88693A
```

Avoid blue/green eyes for now unless the NPC is intentionally special.

---

## 8. Headgear / Accessory Palette

Use for worker headbands, headwraps, caps, hoods, simple jewelry.

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Deep Shadow | `#312210` |
| Cloth Shadow | `#A59B79` |
| Cloth Base | `#B2A386` |
| Warm Accent | `#C4A474` |
| Small Gold Accent | `#D9A441` |

Notes:

- Poor headgear should be duller.
- Better headgear may use more ochre or red-brown trim.
- Gold should be tiny unless the item is elite/special.

---

## 9. UI / Dialogue Box Palette

Use for stone chat boxes, dialogue windows, small nameplates, and mouse cursor visuals.

### Stone Dialogue Box

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Deep Crack | `#312210` |
| Stone Shadow | `#5E4630` |
| Stone Mid | `#88693A` |
| Stone Light | `#B2A386` |
| Inner Tablet | `#CBB99A` |
| Text Dark | `#191919` |

### UI Gold Accent

| Role | Hex |
|---|---|
| Muted Gold | `#C4A474` |
| Soft Gold | `#D9A441` |
| Glow Gold | `#FFD35A` |

Use gold only for:

- next/continue indicator
- clock/time icon
- active cursor highlight
- logo glow
- rare important UI accent

Do not cover large UI areas with bright gold.

---

## 10. Logo / Time Relic Palette

Use for the Time is Precious clock logo and special time-related iconography.

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Deep Stone Shadow | `#312210` |
| Stone Shadow | `#5E4630` |
| Stone Base | `#88693A` |
| Stone Light | `#B2A386` |
| Muted Gold | `#C4A474` |
| Soft Gold | `#D9A441` |
| Bright Glow | `#FFD35A` |
| Hot Core Shadow | `#4D310F` |

Notes:

- Stone should dominate.
- Gold should feel revealed, not cover everything.
- Bright glow is for the peeled/open golden time core only.

---

## 11. Resource / World Earth Palette

Use for mud, clay, sun-dried mudbrick, reed, wood, and rough terrain icons.

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Deep Earth | `#312210` |
| Earth Shadow | `#5E4630` |
| Clay Brown | `#88693A` |
| Sand Ochre | `#C4A474` |
| Dust Linen | `#B2A386` |

Future resource-specific colors may be added only after approval.

---

## 12. Accent Rules

Allowed accents:

| Accent | Hex | Use |
|---|---|---|
| Brick Maroon | `#3C1B1B` | trim, hair, dyed fabric |
| Sand Ochre | `#C4A474` | muted gold, better cloth, skin highlight |
| Soft Gold | `#D9A441` | UI active accent, logo gold |
| Bright Gold | `#FFD35A` | glowing time/gold accent only |
| Muted Blue Gray | `#7D929E` | rare cool accent, not common worker |

Avoid:

- neon colors
- saturated modern blue
- pure bright red
- pure bright yellow as flat fill
- too much white
- uncontrolled new browns that are almost identical to existing ones

---

## 13. Practical Contrast Rules

### Skin vs Clothes

If skin is:

```text
#C4B297 / #D9CDBB
```

Then clothing near the body should prefer:

```text
#A98B5A / #C3A06A
```

or:

```text
#B2A386 / #CBB99A
```

Do not use the exact skin base/highlight as the clothing base/highlight.

### Poor vs Common Clothes

Poor clothing should be:

```text
warmer, darker, dirtier
```

Common clothing should be:

```text
dustier, cleaner, slightly cooler/muted
```

### Better Clothes

Better clothing can use:

```text
#C4A474
#D9A441
#3C1B1B
```

but only in controlled amounts.

---

## 14. Palette Exception Rule

If a new asset needs a new color, document it first.

Use this format:

```text
New color request:
Hex:
Reason:
Asset affected:
Approved: yes/no
```

Do not let the palette grow randomly. Small pixel art dies from uncontrolled color spread.
