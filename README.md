# mac-gazebodistro

A [vcstool](https://github.com/dirk-thomas/vcstool) collection for
source-building **Ignition Citadel on macOS Apple Silicon**.

Same idea as the official
[gazebodistro](https://github.com/gazebo-tooling/gazebodistro) collections,
but pinned to forks that carry the macOS / Apple Silicon / Metal patches
needed to make Citadel run natively on M-series Macs.

## Quick start

```bash
# 1. clone sources into ~/citadel-gui/src
pip3 install vcstool
mkdir -p ~/citadel-gui/src && cd ~/citadel-gui/src
curl -L https://raw.githubusercontent.com/Kakcalu13/mac-gazebodistro/main/collection-mac-citadel.yaml \
    -o /tmp/collection-mac-citadel.yaml
vcs import . < /tmp/collection-mac-citadel.yaml

# 2. build everything (brew check, OGRE-next, gz-* via colcon, install_name patches)
cd ~/citadel-gui/src/mac-gazebodistro
./first_time.sh
```

When the script finishes, **open a new terminal** and run:

```bash
cd ~/citadel-gui
source install/setup.zsh
ign gazebo
```

That's it. Needs more information? Scroll down to detailed start.

## What's in the collection

[`collection-mac-citadel.yaml`](collection-mac-citadel.yaml) imports 17
repositories laid out under `~/citadel-gui/src/`:

| Repo | Source | Why a fork? |
|------|--------|-------------|
| `gz-cmake` | fork (`mac-gz-cmake`, `ign-cmake2`) | Find-module + pkg-config patches |
| `gz-msgs` | fork (`mac-gz-msgs`, `ign-msgs5`) | Build-system patches |
| `gz-transport` | fork (`mac-gz-transport`, `ign-transport8`) | Build / linker fixes |
| `gz-rendering` | fork (`mac-gz-rendering`, `ign-rendering3`) | Ogre-next 2.3 + Metal port + MSAA-resolve fix + clear-color runtime override |
| `gz-gui` | fork (`mac-ign-gui3`, `ign-gui3`) | `ImageProvider` mutex + Qt stride fix |
| `gz-sim` | fork (`mac-citadel-gazebo`, `ign-gazebo3`) | Removal of debug hardcoded background, viewport fixes |
| `gz-launch` | fork (`mac-gz-launch`, `ign-launch2`) | Build patches |
| `ogre-next` | fork (`citadel-gazebo-ogre-next`, `citadel-gazebo-ogre`) | Apple Silicon Metal backend tweaks |
| `gz-math` | upstream (`gazebosim/gz-math`, `ign-math6`) | unchanged |
| `gz-common` | upstream (`gazebosim/gz-common`, `ign-common3`) | unchanged |
| `gz-plugin` | upstream (`gazebosim/gz-plugin`, `ign-plugin1`) | unchanged |
| `gz-tools` | upstream (`gazebosim/gz-tools`, `ign-tools1`) | unchanged |
| `gz-fuel-tools` | upstream (`gazebosim/gz-fuel-tools`, `ign-fuel-tools4`) | unchanged |
| `gz-physics` | upstream (`gazebosim/gz-physics`, `ign-physics2`) | unchanged |
| `gz-sensors` | upstream (`gazebosim/gz-sensors`, `ign-sensors3`) | unchanged |
| `sdformat` | upstream (`gazebosim/sdformat`, `sdf9`) | unchanged |
| `citadel-bridge` | separate (`Kakcalu13/citadel-bridge`, `main`) | Optional pybind11 bridge for Python access to ign-transport |

## Detailed start

If anything in `./first_time.sh` fails or you want to understand each
step, work through the manual flow below.

### 1. Install vcstool

```bash
pip3 install vcstool
```

### 2. Import all repos under a workspace

```bash
mkdir -p ~/citadel-gui/src
cd ~/citadel-gui/src

# fetch the collection file then import
curl -L https://raw.githubusercontent.com/Kakcalu13/mac-gazebodistro/main/collection-mac-citadel.yaml -o /tmp/collection-mac-citadel.yaml
vcs import . < /tmp/collection-mac-citadel.yaml
```

After this finishes, `ls ~/citadel-gui/src/` shows all 17 repos checked out
on their respective branches.

### 3. Build

The full build sequence (brew prereqs, OGRE-next-first ordering, pkg-config
bridge layer, the gz-* dependency-order configure + build loop, the
`install_name_tool` patches, runtime env exports) lives next to this
README:

> **[`SETUP.md`](SETUP.md)** — full first-time build guide

The collection's job is the *clone* step (this Quick start §1–2). `SETUP.md`
picks up from there with §1 (Xcode/Homebrew prereqs), §2 (brew deps), and
goes through the whole build/install/run flow.

If you've already done §1–2 above (`vcs import` is finished), jump
straight to **`SETUP.md` §4** ("Build OGRE-next first") and continue from
there.

### Quick post-clone sanity check

After `vcs import` finishes (step 2), verify the tree looks right before
you start building:

```bash
cd ~/citadel-gui/src
ls                        # should list 17 directories
for d in */; do
    echo "$d $(git -C "$d" rev-parse --abbrev-ref HEAD)"
done
```

Each line should print the directory name and its branch. Compare against
the table at the top of this README — if any branch doesn't match, your
local checkout was already on a different branch when `vcs import` ran
(in which case `vcs import --force` to overwrite, or fix manually).

## Updating the collection

When a fork picks up a new fix, just edit
[`collection-mac-citadel.yaml`](collection-mac-citadel.yaml), commit, and
push. Consumers re-run `vcs import` to pull updates (it does an in-place
fetch + checkout, won't blow away local work).

## Why HTTPS URLs

So anyone can `vcs import` without setting up SSH keys for GitHub. If you
prefer SSH after the import, rewrite the remotes in-place:

```bash
cd ~/citadel-gui/src
for d in */; do
  cd "$d" && git remote set-url origin "$(git remote get-url origin | sed 's|https://github.com/|git@github.com:|')"
  cd ..
done
```

## Conventions

- **Branch naming**: matches the upstream Citadel-era convention (`ign-<name><N>`,
  except `sdformat` which uses `sdf<N>`).
- **Repo naming**: directory names use the modern `gz-*` convention because
  that's what `~/citadel-gui/src/` already uses; this is purely cosmetic
  (gazebosim/ org redirects from old `ignitionrobotics/` URLs).
- **The fork repo names are NOT renamed** to match — the directory layout
  vcstool produces controls that, not the upstream repo name.

## Related

- [`Kakcalu13/mac-citadel-gazebo`](https://github.com/Kakcalu13/mac-citadel-gazebo) — the gz-sim fork (one of the 8 forks listed in the collection)
- [`Kakcalu13/citadel-bridge`](https://github.com/Kakcalu13/citadel-bridge) — pybind11 bridge for Python ↔ ign-transport (optional)
- [`gazebo-tooling/gazebodistro`](https://github.com/gazebo-tooling/gazebodistro) — the official upstream gazebodistro for Linux Citadel/Fortress/Garden (referenced for collection format)
