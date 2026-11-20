# Ant Colony Survival

A survival and colony-building game prototype built in Godot 4. You play as a single ant in a huge, wild, insect-scale world. Gather resources by day, dig and build colonies above and below ground, and defend them against predators, natural disasters, and rival colonies.

The long-term goal is a multiplayer game where each colony is a team of real players (10 or more), with no NPC workers. Rival colonies compete for resources and try to destroy each other's queens.

> **Status:** early prototype. The single-player foundation works. Multiplayer, enemies, and the queen are planned but not built yet.

## Features so far

- **Smooth, diggable terrain.** The world is a density field meshed with Surface Nets, so tunnels and chambers are rounded and organic instead of blocky.
- **Tunnel tools.** Hold a button to carve continuous tunnels, and use a smoothing brush to round off rough walls.
- **Ant movement.** The ant walks, jumps, and climbs walls and ceilings by aligning itself to whatever surface it stands on.
- **Third-person camera.** A spring-arm camera with smoothed mouse look and steering.
- **Resources and inventory.** Walk over sugar, pebbles, and leaf fiber to collect up to 50 of each. Weight slows the ant, and the load shows on its back.
- **Storage and deposits.** Deliver your load to a storage point to build up the colony stockpile.
- **Building.** Spend stored resources on placeable pieces (pebble wall, fiber floor, mortared pillar) with a ghost preview, rotation, and refunds on removal.
- **Procedural look.** Grass, sand, and clay surface patches, clay pockets and stone veins underground, triplanar surface grain, swaying grass, scattered pebbles, ambient occlusion, and a procedurally modeled ant with animated legs.

## Controls

| Input | Action |
|---|---|
| W / S | Walk forward / backward |
| A / D | Steer left / right |
| Mouse | Look around |
| Space | Jump |
| Hold left click | Dig a tunnel |
| Hold right click | Smooth walls |
| Walk over a resource | Collect it |
| E (at the storage) | Deposit everything you carry |
| B | Toggle build mode |
| 1, 2, 3 | Select a building piece (build mode) |
| R | Rotate the piece (build mode) |
| Left click / right click | Place / remove a piece (build mode) |
| Esc | Release the mouse (click to recapture) |

## Getting started

**Requirements**
- [Godot 4.x](https://godotengine.org/download) (standard version, not .NET)
- A GPU that supports the Forward+ renderer for the best look. The Compatibility renderer also works, but ambient occlusion is not available there.

**Run it**
1. Clone the repository.
2. Open Godot, click **Import**, and select the project folder.
3. Open `main.tscn` and press **F5** (or **F6** to run the open scene).

The scene needs a root `Node3D` named `Main` with a `DirectionalLight3D` child, and the `main.gd` script attached to the root. Everything else (terrain, ant, camera, HUD, scenery) is created by code at startup.

## Project structure

| File | Purpose |
|---|---|
| `main.gd` | Scene setup, terrain generation, scenery, digging, building, HUD, and environment |
| `ant.gd` | The player: movement, surface climbing, camera rig, inventory, and the ant model |
| `world.gd` | Chunk storage, coordinate conversion, digging and smoothing brushes, density raycast |
| `chunk.gd` | A 16x16x16 block of density and material samples |
| `surface_mesher.gd` | Turns chunk data into a smooth mesh (Surface Nets) with vertex colors |
| `blocks.gd` | Material IDs (dirt, stone, grass, clay, sand) |
| `pickup.gd` | Collectable resources and their definitions |
| `piece.gd` | Buildable colony pieces and their definitions |

## How it works

- **Chunks.** The world is stored sparsely as a dictionary of 16x16x16 chunks. Only chunks that exist use memory.
- **Density field.** Each sample stores how solid it is (positive is solid, negative is air). The surface is wherever the value crosses zero.
- **Meshing.** Each chunk is meshed with Surface Nets. Chunks read one sample past their edges, so neighboring meshes match without cracks.
- **Editing.** Digging subtracts a capsule from the density field, and only the chunks that changed are re-meshed.
- **Climbing.** The ant casts rays to find the surface it should stick to, then rotates its "up" direction toward that surface's normal.

## Roadmap

- [ ] Queen chamber and colony health
- [ ] Day and night cycle
- [ ] Night enemies (spiders, beetles, centipedes) and termite zones
- [ ] Curved building pieces and arched tunnel supports
- [ ] Flowers, mushrooms, and solid boulders
- [ ] Chunk streaming for a larger, taller world
- [ ] Natural disasters (forest fire, bird raid, flash flood, rockfall)
- [ ] Roles (worker, soldier, forager, digger, scout)
- [ ] Multiplayer with an authoritative server and player-run servers
- [ ] Colony versus colony raids and the regroup mechanic

## Design notes

The full game design (colony roles, economy, world zones, enemies, disasters, and multiplayer rules) is documented in the game design document. Add a link to it here, or copy it into a `docs/` folder in the repository.

## License

Not yet chosen. Add a license before accepting contributions.

## Author

Frimpong Evans Boateng ([@1337-KB](https://github.com/1337-KB))
