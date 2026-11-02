# Blank map authoring scene

Open `new_map_authoring.tscn` in Godot 4.5 and select a TileMapLayer to paint
from the TileMap panel. This scene is separate from the playable map.

- **Water**: water beneath the ground.
- **Base**: the main ground surface.
- **Detail**: ground edges and decorative overlays.
- **Objects**: details that should use Y sorting.

The shared atlas uses 16 × 16 pixel cells from the new PNG. Larger shapes can be
painted by selecting their cells together. Terrain/autotile rules, collisions,
navigation, and gameplay objects have not been configured.
