# ZONE BREAKER — Roadmap

The game is built in small steps, and every step leaves it playable. This page tracks what is done,
what comes next, and what was deliberately dropped.

**Target:** 23 stages, each its own "zone" with unique terrain, background, enemies, boss and music,
on a single difficulty. Harder difficulties are planned as add-ons that reuse the same stages.
The whole progression curve (levels, XP, enemy scaling, rewards, gear prices) is already tuned for
all 23 stages.

**Status:** 4 of 23 stages playable · core systems complete · ~44,000 automated test checks.

---

## ✅ Done

### Core game (steps 0–5)

- **Shooting**: 8-direction aiming, prone and crawl, drop-through platforms, sprint with stamina,
  recoil, muzzle flash, hit sparks, screen shake.
- **Weapons**: data-driven weapons (rifle, grenades, more in the shop) and a screen-clearing
  ultimate (two uses per life).
- **Enemies**: patrol, turret, flying, charging and grenade-throwing types sharing one AI base,
  with line of sight, diagonal fire and prone reactions.
- **Bosses**: shared boss rules (entrance, health bar, ultimate resistance) and a second phase at half
  health.
- **Art pipeline**: all visuals, effects, HUD, sound and music go through swappable skin packs; a test
  suite proves that swapping art never changes game rules.
- **Game flow**: main menu, character roster saves, character setup, pause, skill points, death
  screen with retry, pixel-font HUD.
- **RPG progression**: XP and levels (cap 30), four stats, money, shop, eight gear slots,
  level-gated equipment; progress is kept on death.
- **Local co-op**: two players, shared camera, revive a downed partner, separate progression,
  per-player gamepad assignment.

### Stages (step 6, in progress)

| # | Zone | Layout | Boss |
|---|------|--------|------|
| 1 | Green zone (park) | Horizontal, layered | Missile mech |
| 2 | Industrial zone | Horizontal, layered | Machine operator (crane claw) |
| 3 | Bar street (neon night) | Horizontal, layered | Unicycle mech |
| 4 | Basement shaft | **Vertical climb** | Skull (laser sweeps) |

Each stage has six enemy types of its own, and every stage after the first adds new enemy behaviours
(lungers, leapers, armoured brutes, hovering drones, ...). Supporting work done along the way:

- **Layered levels**: floors, ladders, gaps, and routes that force detours.
- **Traps**: hydraulic presses, blast gates, conveyor belts, breakable crates, explosive barrels that
  chain-react.
- **Generated levels**: levels are generated from grid maps by a path checker, which proves every stage
  can be completed and that the forced detours really are forced.
- **Map painter**: a pixel-image tool for drawing level segments by hand.
- **Stage flow**: stage clear, results screen, stage unlocks and stage select.
- **Content scanning**: content (stages, characters, shop items) is discovered by scanning folders, so
  new content can be dropped in without code changes.
- **Public build**: the public repository runs without the licensed art.

---

## 🔜 Next

### Stages 5–23 (step 6, continued)

Each new stage follows the same recipe:

1. **New zone art**: a tileset, a parallax background, decorations, and music if the pack has a
   track.
2. **Six enemies**: two or three new behaviours per stage; the rest reuse existing AI with new art and
   tuned numbers.
3. **A boss**: its own patterns, a readable wind-up before each attack, and an enraged second phase.
4. **A layered grid map**:
   - about 10 segments;
   - roughly 70% of segments force a detour and 30% offer a free choice of route;
   - one exit, at the boss.
5. **Tests**: stage tests that run the real rules over the forced routes, then screenshots for review.

Notes:

- The bar street asset pack comes with two more bosses that are not used yet. They are candidates for
  upcoming stages.
- Each stage mixes in variety: horizontal and vertical stages, and new trap types where a zone suggests
  them.

### Step 7 — Audio and release

- **Audio**:
  - A main-menu theme (the hook is in place; no track has been picked yet).
  - Replacements for the few sound effects that still use 8-bit placeholders: jump, stamina, downed
    and revive, hammer smash, boss enrage.
  - Music for the stages whose packs ship without a track.
- **Windows export**: build presets, leave the test suite out of the package, and turn off the
  "all stages unlocked" development switch.
- **Release pass**: balance playthrough of all stages, first-time player experience, settings menu
  (volume, controls).

### Content backlog

- **Status effects**: the system is in place (damage over time, slow, paralysis, gear resistances).
  Still to do: actual poison/burn/shock effects, weapons that apply them, and HUD and visual feedback.
- **More gear**: armour tiers 4–8 (icons already available), trinket-slot items, and more weapons
  (ten hand-held gun sprites to choose from).
- **Art polish**: diagonal-firing frames for the stage 2 gunner, which currently fires diagonally
  while drawn shooting straight.

---

## 🧩 Later / add-ons

- **Difficulty add-ons (Hard, Hell)**: same stages and enemies, with higher enemy health, damage and
  reward multipliers. These ship as small data files only.
- **New zone add-ons**: extra stages dropped into the content folders, with no engine changes
  needed.
- **Localisation**: a CJK pixel font would allow Chinese text. The UI is currently English uppercase
  only.

---

## ❌ Dropped (on purpose)

- **Score**: XP and money already give two numbers to chase; a third would be noise.
- **Checkpoints**: you keep all levels, XP, money and gear on death, and stages are fast to replay.
  Checkpoints would undercut that loop.
- **In-stage pickups (health, weapon upgrades)**: power growth happens in the shop between stages.
  This keeps a player's stats fixed within a stage, so enemy strength can be tuned against them.
