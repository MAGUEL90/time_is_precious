# PALETTE GUIDE — Time is Precious

Version: v0.1  
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

---

## 2. Core Rule

Main outline color:

| Role | Hex |
|---|---|
| Primary Outline | `#191919` |

Use this as the default dark outline for most assets.

Use pure black `#000000` only for UI text, debug guides, or intentional ultra-dark accents. Avoid using it as the normal sprite outline unless needed.

---

## 3. Official Core Palette

These colors are chosen to match the current asset sheet direction and Mesopotamian earthy tones.

| Name | Hex | Use |
|---|---|---|
| Primary Outline | `#191919` | main pixel outline |
| Deep Warm Shadow | `#0F0606` | deepest hair/shadow accent |
| Dark Clay Shadow | `#312210` | dark brown shadow |
| Mud Brown | `#4F4B4B` | gray-brown shadow / dark hair |
| Brick Maroon | `#3C1B1B` | dark red-brown hair/trim |
| Clay Brown | `#88693A` | leather, rope, mud, darker cloth |
| Dust Olive | `#A59B79` | old fabric, muted headgear |
| Linen Shadow | `#A1927C` | cloth shadow |
| Linen Mid | `#C4B297` | linen base |
| Sand Ochre | `#C4A474` | warmer cloth / gold-brown accent |
| Linen Light | `#D9CDBB` | light skin/linen highlight |
| Muted Blue Gray | `#7D929E` | rare accent / cool gray |
| UI Black | `#000000` | UI text or debug only |
| UI White | `#FFFFFF` | UI text/highlight only |

---

## 4. Poor Worker Clothing Ramp

Use for poor tunics, clay-worn wraps, worn pants, basic cloth.

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Deep Shadow | `#312210` |
| Dirt / Patch | `#88693A` |
| Cloth Shadow | `#A1927C` |
| Cloth Base | `#C4B297` |
| Cloth Highlight | `#D9CDBB` |

Notes:

- Use patch/dirt as a big readable shape, not many tiny dots.
- Poor clothing may look uneven, but still readable.
- At 16x16, one patch is enough.

---

## 5. Common Worker Clothing Ramp

Use for cleaner worker tunics and standard everyday clothing.

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Shadow | `#4F4B4B` |
| Belt / Rope | `#88693A` |
| Cloth Mid | `#C4B297` |
| Cloth Warm | `#C4A474` |
| Highlight | `#D9CDBB` |

Notes:

- Cleaner than poor clothing.
- Less dirt.
- More stable silhouette.
- Belt can be the main detail.

---

## 6. Better Worker / Overseer Ramp

Use for richer worker clothing, mandor/overseer, better-status garments.

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Shadow | `#312210` |
| Trim Dark Red | `#3C1B1B` |
| Belt / Trim Brown | `#88693A` |
| Ochre Base | `#C4A474` |
| Highlight | `#D9CDBB` |

Notes:

- Status should read through cleaner shape and stronger color.
- Use red-brown trim sparingly.
- Avoid making worker clothing look royal too early.

---

## 7. Skin Ramp

Current face/head direction uses warm linen/clay skin tones.

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Deep Shadow | `#312210` |
| Dark Skin | `#88693A` |
| Mid Skin | `#C4A474` |
| Light Skin | `#D9CDBB` |

Use this ramp for base faces and expression variants.

---

## 8. Hair Ramps

### Black / Dark Gray Hair

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Deep | `#0F0606` |
| Shadow | `#313030` |
| Mid | `#4F4B4B` |
| Light | `#716C6C` |

### Dark Red / Maroon Hair

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Deep | `#0F0606` |
| Shadow | `#3C1B1B` |
| Mid | `#5A2A2A` |
| Light | `#7A3A2A` |

### Brown Hair

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Deep | `#312210` |
| Shadow | `#4D310F` |
| Mid | `#88693A` |
| Light | `#C4A474` |

---

## 9. Headgear / Accessory Ramp

Use for simple worker headbands, headwraps, caps, hoods.

| Role | Hex |
|---|---|
| Outline | `#191919` |
| Deep Shadow | `#312210` |
| Cloth Shadow | `#A59B79` |
| Cloth Base | `#C4B297` |
| Warm Accent | `#C4A474` |
| Highlight | `#D9CDBB` |

Notes:

- Poor headgear should be duller.
- Better headgear may use more ochre or red-brown trim.
- Avoid bright gold until elite/noble tiers.

---

## 10. Accent Rules

Allowed accents:

| Accent | Hex | Use |
|---|---|---|
| Brick Maroon | `#3C1B1B` | trim, hair, dyed fabric |
| Sand Ochre | `#C4A474` | better cloth, jewelry, trim |
| Muted Blue Gray | `#7D929E` | rare decorative accent, not common worker |
| Linen Light | `#D9CDBB` | highlight |

Avoid:

- neon colors
- saturated modern blue
- pure bright red
- pure bright yellow
- too much white

---

## 11. Palette Exception Rule

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
