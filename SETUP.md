# Setup Guide — Citadel on macOS Apple Silicon

Complete first-time setup for source-building **Ignition Citadel** (gz-sim 3
/ gz-rendering 3 / OGRE-next 2.3.3) on Apple Silicon (M1/M2/M3) from
scratch, using the [`collection-mac-citadel.yaml`](collection-mac-citadel.yaml)
collection in this repo.

> **In a hurry?** [`./first_time.sh`](first_time.sh) automates #2–#7 in
> one shot (after you've finished #1 prereqs and the `vcs import` from
> #3). This guide is the manual / explanatory version of that script.
>
> **Estimated time:** 2–4 hours for a clean build, most of it spent compiling
> ogre-next and gz-sim. Incremental rebuilds afterward take seconds.
>
> **End state:** a working `ign gazebo shapes.sdf -r` rendered through a
> source-built OGRE-next 2.3.3 ogre2 backend on Metal.

---

## 1. Prerequisites

### Hardware

- **Mac with Apple Silicon** (M1, M2, M3). Intel Macs are not supported —
  the OGRE-next Metal port assumes ARM64.
- **~40 GB free disk space** for source + build + install.
- **16 GB RAM minimum** (32 GB recommended for parallel builds).

### macOS

macOS 13 Ventura or newer. Tested on macOS 14 Sonoma.

### Xcode Command Line Tools

```bash
xcode-select --install
xcode-select -p
# expected: /Applications/Xcode.app/Contents/Developer  (or /Library/Developer/CommandLineTools)
```

### Homebrew

If you don't have Homebrew, install from [brew.sh](https://brew.sh):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### vcstool

```bash
pip3 install vcstool
```

---

## 2. Install Homebrew Dependencies

Homebrew supplies the **non-ignition** system dependencies (toolchain, Qt,
protobuf, physics libs, etc.). All `ignition-*` / `gz-*` libraries are
built from source from the `vcs import` step (#3) — do **not** install
them via Homebrew.

```bash
brew install \
  cmake pkg-config doxygen graphviz \
  qt@5 \
  freeimage libzzip \
  tinyxml2 protobuf@29 zeromq cppzmq libzip \
  json-c urdfdom rapidjson \
  dartsim assimp fcl \
  tbb jsoncpp eigen glib \
  yaml-cpp ruby
```

`uuid` is **not** in the list because macOS provides UUID natively in
`libsystem_uuid` (`#include <uuid/uuid.h>` Just Works); there is no
Homebrew formula called `uuid` that the build needs.

### Why `protobuf@29` and not plain `protobuf`

Brew's default `protobuf` formula (currently 34.x) emits gencode major
version 7. The Python `protobuf` package on PyPI is still on the 5.x line
(gencode major 5). Major versions must match; mismatched majors break
every `*_pb2.py` you generate from `gz-msgs/proto/`. `protobuf@29` emits
gencode major 5, which Python 5.x can load.

`protobuf@29` is **keg-only** — brew won't link its `protoc` binary onto
your `PATH` automatically. Add it explicitly (this is the only line of
brew shell-config you should need for this whole setup):

```bash
echo 'export PATH="/opt/homebrew/opt/protobuf@29/bin:$PATH"' >> ~/.zshrc
export PATH="/opt/homebrew/opt/protobuf@29/bin:$PATH"

# Verify libprotoc reports 29.x (NOT 34.x):
which protoc && protoc --version
```

If you already had brew's plain `protobuf` (34.x) installed before,
**leave it alone** — Citadel's source-built C++ libs link against its
runtime dylib (`libprotobuf.34.1.0.dylib`), and uninstalling will break
the build. The two formulas coexist fine; `protobuf@29` only adds an
alternate `protoc` binary on `PATH` for codegen, doesn't touch the
runtime libraries.

### Verify what got installed

```bash
brew list --versions \
  cmake pkg-config doxygen graphviz qt@5 freeimage libzzip \
  tinyxml2 protobuf@29 zeromq cppzmq libzip json-c urdfdom rapidjson \
  dartsim assimp fcl tbb jsoncpp eigen glib yaml-cpp ruby
```

Save this output — if anything goes wrong later, paste it into your
issue (#9) so the diff between your versions and a known-working set
can be spotted.

### Do NOT install ignition libraries from Homebrew

Brew's `ignition-*` / `gz-*` formulas track newer Gazebo releases (Fortress,
Garden, Harmonic) — different majors from Citadel. Installing them
alongside the source build either breaks the build (CMake finds the wrong
version of a `find_package`'d dep) or breaks runtime (dyld picks up the
brew dylib instead of the source-built one).

If any of these are already installed, **remove them** before continuing:

```bash
# Citadel collides with these — uninstall any that are present
brew list 2>/dev/null | grep -E '^(gz-sim|gz-rendering|gz-physics|gz-sensors|gz-launch|ignition-gazebo|ignition-rendering|ignition-physics|ignition-sensors|ignition-launch|ignition-cmake|ignition-common|ignition-fuel-tools|ignition-math|ignition-msgs|ignition-plugin|ignition-tools|ignition-transport|ignition-utils|sdformat|ogre2.3)' \
    | xargs -I{} brew uninstall --ignore-dependencies {}
```

(The `--ignore-dependencies` flag is necessary because some of these are
listed as deps of each other in the brew formulas.)

### Do NOT install `ogre2.3` from Homebrew

OGRE-next 2.3.3 is built from source in #4 — the
[`citadel-gazebo-ogre-next`](https://github.com/Kakcalu13/citadel-gazebo-ogre-next)
fork is the OGRE-next 2.3 base with 2.3.3's rendering ported in. It
provides its own headers, libraries, and pkg-config.

If Homebrew's `ogre2.3` is already installed, **uninstall it** — it loads
alongside the source-built 2.3.3 at runtime and produces an Objective-C
class collision (`OgreConfigWindowDelegate implemented in both …`) that
results in a black screen:

```bash
brew list | grep -q ogre2.3 && brew uninstall --ignore-dependencies ogre2.3
```

### Optional: `ogre1.9` for the legacy render backend

A few upstream example worlds request `<engine>ogre</engine>` (the legacy
ogre1.9 backend). If you want them to load as-is:

```bash
brew install ogre1.9
```

Otherwise edit those worlds to use `<engine>ogre2</engine>`. The ogre2
(Metal) path is the actively-maintained one on macOS.

---

## 3. Workspace and source clones

Pick a workspace location (anywhere; `~/citadel-gui/` is the convention
this repo's docs assume):

```bash
mkdir -p ~/citadel-gui/src
cd ~/citadel-gui/src

# Pull all source repos at once via vcstool. Reads the collection
# file directly from this repo's main branch:
curl -L https://raw.githubusercontent.com/Kakcalu13/mac-gazebodistro/main/collection-mac-citadel.yaml \
    -o /tmp/collection-mac-citadel.yaml
vcs import . < /tmp/collection-mac-citadel.yaml
```

Verify the tree landed correctly:

```bash
cd ~/citadel-gui/src
for d in */; do
    printf "%-25s  %s\n" "$d" "$(git -C "$d" rev-parse --abbrev-ref HEAD)"
done
```

You should see 16 directories (the 8 forks + 8 upstream repos in the
collection-mac-citadel.yaml; `citadel-bridge` is commented out, build
it separately if you want it) on the branches listed in the
[README's coverage table](README.md#whats-in-the-collection).

---

## 4. Build OGRE-next first

OGRE-next 2.3.3 must be installed before anything else compiles, because
gz-rendering's ogre2 backend links against it:

```bash
mkdir -p ~/citadel-gui/build/OGRE
cd ~/citadel-gui/build/OGRE

cmake ~/citadel-gui/src/ogre-next \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX=~/citadel-gui/install \
  -DCMAKE_CXX_STANDARD=17 \
  -DCMAKE_CXX_STANDARD_REQUIRED=ON \
  -DOGRE_BUILD_RENDERSYSTEM_METAL=ON \
  -DOGRE_BUILD_RENDERSYSTEM_GL3PLUS=ON \
  -DOGRE_BUILD_RENDERSYSTEM_VULKAN=OFF \
  -DOGRE_BUILD_SAMPLES2=OFF \
  -DOGRE_BUILD_TESTS=OFF

cmake --build . --target install -j$(sysctl -n hw.logicalcpu)
```

> **Why `-DOGRE_BUILD_RENDERSYSTEM_VULKAN=OFF` is required.** OGRE-next
> auto-enables the Vulkan render system if cmake's `find_package(Vulkan)`
> finds `libvulkan.dylib` anywhere (`/usr/local/lib`, MoltenVK, etc.).
> But unless you also have the Vulkan SDK *headers* installed
> (`vulkan/vulkan_core.h`), the build will get past 90% then fail to
> compile the Vulkan render system. Citadel-on-macOS uses Metal — Vulkan
> isn't used at runtime, so just disable the render system at configure
> time.

> **Why `-DCMAKE_CXX_STANDARD=17` is required.** OGRE-next's
> `OgreSharedPtr.h:388` has `#error "Apple Platforms must use at least
> C++11"` guarding C++11 features. With newer CMake (4.x) and OGRE-next's
> old `cmake_minimum_required(VERSION < 3.10)`, the C++ standard isn't
> auto-propagated, so `__cplusplus` reads as C++98 and the `#error`
> trips. Forcing C++17 settles it.

This installs `Ogre.framework`, `OgreHlmsPbs.framework`,
`OgreHlmsUnlit.framework` bundles and the render system plugins
(`RenderSystem_Metal.dylib`, etc.) into `~/citadel-gui/install/`.

---

## 5. pkg-config + dylib symlink bridge (one-time)

OGRE-next installs frameworks, but cmake's `FindIgnOGRE2` wants Unix-style
dylibs with pkg-config. Create the bridge layer:

```bash
# 5a. Dylib symlinks pointing into the framework bundles
FWK=~/citadel-gui/install/lib/RelWithDebInfo
ln -sf "$FWK/Ogre.framework/Versions/2.3.3/Ogre"                     ~/citadel-gui/install/lib/libOgreMain.dylib
ln -sf "$FWK/OgreHlmsPbs.framework/Versions/2.3.3/OgreHlmsPbs"       ~/citadel-gui/install/lib/libOgreHlmsPbs.dylib
ln -sf "$FWK/OgreHlmsUnlit.framework/Versions/2.3.3/OgreHlmsUnlit"   ~/citadel-gui/install/lib/libOgreHlmsUnlit.dylib

# 5a.2 — Render-system + plugin .dylib symlinks under lib/OGRE/
# gz-rendering's ogre2 backend has OGRE2_RESOURCE_PATH compiled in as
# "<install>/lib/OGRE" (taken from pkg-config's `plugindir` variable in
# OGRE-2.3.pc, set below in 5b) and looks for `RenderSystem_Metal.dylib`,
# `RenderSystem_GL3Plus.dylib`, `Plugin_ParticleFX.dylib` directly in
# that dir at runtime. Source-built OGRE-next ships these as frameworks
# under $FWK, so create the .dylib aliases:
mkdir -p ~/citadel-gui/install/lib/OGRE
for plug in RenderSystem_Metal RenderSystem_GL3Plus RenderSystem_NULL Plugin_ParticleFX; do
  ln -sfn "$FWK/${plug}.framework/Versions/2.3.3/${plug}" \
          ~/citadel-gui/install/lib/OGRE/${plug}.dylib
done

# 5b. Source-built OGRE-2.3.pc — points pkg-config at our install, not Homebrew
mkdir -p ~/citadel-gui/install/lib/pkgconfig
cat > ~/citadel-gui/install/lib/pkgconfig/OGRE-2.3.pc <<EOF
prefix=$HOME/citadel-gui/install
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include/OGRE
plugindir=\${libdir}/OGRE

Name: OGRE-2.3
Description: Object-Oriented Graphics Rendering Engine (ogre-next 2.3, source build)
Version: 2.3.3
URL: http://www.ogre3d.org
Libs: -L\${libdir} -lOgreMain
Cflags: -I\${includedir} -I\${includedir}/Hlms/Common
EOF
```

Verify pkg-config resolves correctly:

```bash
PKG_CONFIG_PATH=~/citadel-gui/install/lib/pkgconfig \
    pkg-config --variable=plugindir OGRE-2.3
# expected: <your $HOME>/citadel-gui/install/lib/OGRE
```

---

## 6. Build the gz-* stack with colcon

The fifteen ignition-* / sdformat repos form a deep dep graph (e.g.
`gz-sim` reaches `gz-cmake` through eight intermediates). Rather than
ordering them by hand, we let
[`colcon`](https://colcon.readthedocs.io/) walk the graph for us.
`colcon-cmake` infers the order from each repo's `find_package(...)`
calls — verify with `colcon graph` before building (sdformat9 should
appear *before* `ignition-rendering3`, `ignition-physics2`, `ignition-gui3`,
`ignition-gazebo3`).

### 6a. Install colcon

```bash
pip3 install colcon-common-extensions
which colcon
# expected: /opt/homebrew/bin/colcon  (or a venv path)
```

### 6b. Patch the four CMake-4.x-incompatible `create_symlink` lines

`gz-rendering/ogre{,2}/src/CMakeLists.txt` and
`gz-physics/{dartsim,tpe/plugin}/CMakeLists.txt` each call
`EXECUTE_PROCESS(COMMAND ${CMAKE_COMMAND} -E create_symlink …)` without
a `WORKING_DIRECTORY`. Under CMake 4.x that silently writes the symlink
to a different cwd than `${PROJECT_BINARY_DIR}`, and the next-line
`INSTALL(FILES ${PROJECT_BINARY_DIR}/${unversioned} …)` rule fails with
"file INSTALL cannot find …". Pin the cwd by appending
`WORKING_DIRECTORY ${PROJECT_BINARY_DIR}`:

```bash
cd ~/citadel-gui/src
for f in gz-rendering/ogre/src/CMakeLists.txt \
         gz-rendering/ogre2/src/CMakeLists.txt \
         gz-physics/dartsim/CMakeLists.txt \
         gz-physics/tpe/plugin/CMakeLists.txt
do
  sed -i '' \
    's|EXECUTE_PROCESS(COMMAND ${CMAKE_COMMAND} -E create_symlink ${versioned} ${unversioned})|EXECUTE_PROCESS(COMMAND ${CMAKE_COMMAND} -E create_symlink ${versioned} ${unversioned} WORKING_DIRECTORY ${PROJECT_BINARY_DIR})|' \
    "$f"
done
```

(One-time post-clone patch. Re-running `vcs import --force` would
revert it, so reapply if you ever resync the repos.)

### 6c. Hide already-built / phantom packages from colcon

Colcon's `colcon-cmake` extension does grep-based dep inference: it
scans every `CMakeLists.txt` and `*.cmake` for `find_package(<X>)` and
treats `<X>` as a build dependency. That picks up false positives — most
notably, `gz-cmake/cmake/FindIgnOGRE.cmake` calls `find_package(OGRE …)`,
so colcon thinks `ignition-cmake2` depends on the source-built `OGRE`
project we already finished in #4 and refuses to build until OGRE has
been built *through colcon*.

Mask packages we don't want colcon to touch with a `COLCON_IGNORE`
marker file in their source root:

```bash
# ogre-next: built manually in #4, not through colcon
touch ~/citadel-gui/src/ogre-next/COLCON_IGNORE

# Optional Python bridge — build it separately if you want it
touch ~/citadel-gui/src/citadel-bridge/COLCON_IGNORE
```

Confirm only the 15 ignition / sdformat repos are now in colcon's
workspace view:

```bash
cd ~/citadel-gui
colcon list | wc -l    # expected: 15
colcon graph           # sdformat9 should sit BEFORE rendering3, physics2,
                       # gui3, gazebo3, sensors3
```

### 6d. Run colcon build

```bash
cd ~/citadel-gui

colcon build \
  --merge-install \
  --install-base ~/citadel-gui/install \
  --build-base  ~/citadel-gui/build \
  --cmake-args \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_PREFIX_PATH="$HOME/citadel-gui/install;/opt/homebrew/opt/qt@5" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_CXX_STANDARD_REQUIRED=ON \
    -DQt5_DIR=/opt/homebrew/opt/qt@5/lib/cmake/Qt5 \
    -DBUILD_TESTING=OFF
```

> **`--merge-install`**: install everything to a single
> `~/citadel-gui/install` tree (instead of colcon's default per-package
> install dirs). Matches the layout the rest of this guide assumes.
>
> **`-DCMAKE_POLICY_VERSION_MINIMUM=3.5`**: `ignition-tools` and a few
> others still declare `cmake_minimum_required(VERSION 3.0)`; CMake 4.x
> aborts configure unless this is set.
>
> **`CMAKE_PREFIX_PATH`**: includes both `~/citadel-gui/install` (so
> packages find each other's colcon-installed cmake configs *and* the
> manually-built OGRE-next install) and `/opt/homebrew/opt/qt@5`
> (gz-gui / gz-sim need Qt5).

If a package fails, colcon prints which one and stops — you can resume
with `--packages-start <name>` (build that package and everything after
it in the dep graph) or `--packages-select <name1> <name2>` (build only
the named packages). Build logs land in `~/citadel-gui/log/latest_build/<pkg>/`.

---

## 7. Apply `install_name_tool` patches (REQUIRED)

OGRE-next installs every framework binary with an `@executable_path/...`
install name that only resolves inside a `.app` bundle. `ign` is a CLI
tool, so every framework's self-id and every cross-framework reference
has to be rewritten to an absolute path. **Run after every rebuild of
`gz-rendering` or OGRE-next.**

```bash
FWK=~/citadel-gui/install/lib/RelWithDebInfo
ABS_OGRE="$FWK/Ogre.framework/Versions/2.3.3/Ogre"

# Layer 1 — every framework binary in $FWK
# Each one needs:
#   -id  rewritten from @executable_path/... to its absolute path
#   any -change Ogre@executable_path → absolute Ogre path (for non-Ogre frameworks)
for fwk_dir in "$FWK"/*.framework; do
  name=$(basename "$fwk_dir" .framework)
  bin="$fwk_dir/Versions/2.3.3/$name"
  [ -f "$bin" ] || continue
  install_name_tool -id "$bin" "$bin" 2>/dev/null
  if [ "$name" != "Ogre" ]; then
    install_name_tool \
      -change "@executable_path/../Frameworks/Ogre.framework/Versions/2.3.3/Ogre" \
              "$ABS_OGRE" \
      "$bin" 2>/dev/null
  fi
done

# Layer 2 — gz-rendering ogre2 plugin (both copies: lib/ and engine-plugins/)
for DYLIB in \
  ~/citadel-gui/install/lib/ign-rendering-3/engine-plugins/libignition-rendering3-ogre2.3.7.2.dylib \
  ~/citadel-gui/install/lib/libignition-rendering3-ogre2.3.7.2.dylib; do
  [ -f "$DYLIB" ] || continue
  install_name_tool \
    -change "@executable_path/../Frameworks/Ogre.framework/Versions/2.3.3/Ogre" \
      "$ABS_OGRE" \
    -change "@executable_path/../Frameworks/OgreHlmsPbs.framework/Versions/2.3.3/OgreHlmsPbs" \
      "$FWK/OgreHlmsPbs.framework/Versions/2.3.3/OgreHlmsPbs" \
    -change "@executable_path/../Frameworks/OgreHlmsUnlit.framework/Versions/2.3.3/OgreHlmsUnlit" \
      "$FWK/OgreHlmsUnlit.framework/Versions/2.3.3/OgreHlmsUnlit" \
    "$DYLIB" 2>/dev/null
done
```

> **Why a loop over `$FWK/*.framework`.** OGRE-next 2.3.3 sources install
> Ogre, OgreHlmsPbs, OgreHlmsUnlit, RenderSystem_Metal,
> RenderSystem_GL3Plus, and RenderSystem_NULL all as frameworks in the
> same dir, all with the same `@executable_path` install-name pattern,
> so a single loop fixes every framework's self-id plus its dependency
> on `Ogre` in one pass. The previous version of this script special-cased
> only the three Hlms-related frameworks and missed the render systems —
> dyld would then fail to load `RenderSystem_Metal` from the CLI and
> Citadel would silently fall back to a black window.

---

## 8. Launch

Every new terminal session needs the runtime env set up. `colcon build
--merge-install` (#6d) generated `~/citadel-gui/install/setup.zsh` for
you — it sets `PATH` and a few colcon-internal vars. Source it first,
then add the ign-specific plugin search paths colcon doesn't know
about:

```bash
source ~/citadel-gui/install/setup.zsh

# Where ign looks for its component .yaml manifests (gazebo3.yaml,
# gui3.yaml, transport8.yaml, etc.)
export IGN_CONFIG_PATH=~/citadel-gui/install/share/ignition

# Plugin search paths
export IGN_RENDERING_PLUGIN_PATH=~/citadel-gui/install/lib/ign-rendering-3/engine-plugins
export IGN_GAZEBO_SYSTEM_PLUGIN_PATH=~/citadel-gui/install/lib/ign-gazebo-3/plugins
export IGN_GUI_PLUGIN_PATH=~/citadel-gui/install/lib/ign-gui-3/plugins

# dyld needs both lib/ (gz-* dylibs and Hlms framework symlinks)
# and lib/RelWithDebInfo/ (OGRE-next frameworks). The `:-` guard keeps
# this safe under `set -u` if DYLD_LIBRARY_PATH wasn't already set.
export DYLD_LIBRARY_PATH=~/citadel-gui/install/lib:~/citadel-gui/install/lib/RelWithDebInfo:${DYLD_LIBRARY_PATH:-}
```

To avoid retyping these every session, save the four `export`s plus
the `source` line to a file you can source on demand — for example
`~/citadel-gui/install/env.sh` — and run `source
~/citadel-gui/install/env.sh` whenever you open a new terminal.

Verify `ign` is the source-built one:

```bash
which ign
# MUST print: <your $HOME>/citadel-gui/install/bin/ign
# If it prints /opt/homebrew/bin/ign you'll get a black screen.
```

Run:

```bash
ign gazebo shapes.sdf -r
```

Expected: gray ground plane, red box, blue sphere, green cylinder. No
stripes, no double view, no flat color.

---

## 9. Hit a problem? File an issue

If anything goes wrong — build failures, runtime crashes, missing
dependencies, viewport glitches, anything — open a bug report:

> **<https://github.com/Kakcalu13/mac-citadel-gazebo/issues>**

Useful info to include in the issue:

- macOS version (`sw_vers -productVersion`) and chip (`uname -m`)
- Which step from this guide it failed at
- The exact command you ran
- The full error output (or last ~30 lines if it's huge)
- Output of `which ign`, `which protoc`, `which cmake` if relevant
- Anything in the brew formulas list that might be conflicting (`brew list | grep -E '^(gz|ignition|ogre|sdformat)'`)
- Your dependency versions vs. the snapshot in [#10](#10-known-good-versions-snapshot) — paste the diff if anything's drifted

---

## 10. Known-good versions (snapshot)

Snapshot of every dependency on the machine that successfully built this
stack. Brew formulae move forward over time; if you're reading this in
the future and a build fails after `brew upgrade`, this table tells you
the *exact* versions that are known to work, so you can pin yours to
match (or compare a `brew list --versions` diff to figure out what
moved).

> **Captured: 2026-04-28** — Mac mini M2 (Apple Silicon)

### System

| Component | Version |
|---|---|
| macOS | 14.1.2 (Sonoma, build 23B92) |
| Architecture | arm64 (Apple Silicon) |
| Xcode | 15.4 (15F31d) |
| Homebrew | 5.1.8 |
| Python (system / shell `python3`) | 3.11.15 |

### Build toolchain

| Brew formula | Version | Role |
|---|---|---|
| `cmake` | 4.3.1 | Build system |
| `pkgconf` | 2.5.1 | pkg-config implementation (provides the `pkg-config` command) |
| `doxygen` | 1.16.1 (1.13.2 also installed) | Doc generation (skipped if `BUILD_TESTING=OFF`) |
| `graphviz` | 12.2.1 | Doxygen call-graph rendering |

### GUI stack

| Brew formula | Version | Role |
|---|---|---|
| `qt@5` | 5.15.18 | Qt5 — used by `ignition-gui3` and `ignition-gazebo3` (GzScene3D viewport) |

### Image / archive libraries

| Brew formula | Version | Role |
|---|---|---|
| `freeimage` | 3.18.0 | Image format I/O |
| `libzzip` | 0.13.80 (0.13.78 also installed) | Zip read for resource bundles |
| `libzip` | 1.11.4_1 (1.11.3 also installed) | Modern zip API |

### Serialization / IPC

| Brew formula | Version | Role |
|---|---|---|
| `tinyxml2` | 11.0.0 | XML parsing for SDF |
| `protobuf@29` | **29.6** | **Pinned** — `protoc` that emits gencode v5 (matches Python `protobuf` 5.x runtime) |
| `protobuf` | 34.1 | Citadel's source-built C++ libs link against this — leave installed if present |
| `zeromq` | 4.3.5_2 | ZMQ for ign-transport |
| `cppzmq` | 4.11.0 | C++ wrapper for zeromq |

### System utilities

| Brew formula | Version | Role |
|---|---|---|
| `uuid` | (provided by macOS — not a brew formula) | UUID generation |
| `json-c` | 0.18 | JSON parsing |
| `urdfdom` | 5.1.0 (4.0.1 also installed) | URDF model parsing |
| `rapidjson` | 1.1.0 | Header-only JSON parser used by OGRE-next 2.3.3's `OgreRootLayout.cpp` |

### Physics / collision

| Brew formula | Version | Role |
|---|---|---|
| `dartsim` | 6.16.7 | Dynamics And Robotics Toolkit — backs `ignition-physics2` |
| `assimp` | 6.0.4_1 | Mesh import |
| `fcl` | 0.7.0_2 (0.7.0_1 also installed) | Flexible Collision Library |

### Math / parallelism

| Brew formula | Version | Role |
|---|---|---|
| `tbb` | 2022.3.0 (2022.0.0 also installed) | Threading Building Blocks |
| `jsoncpp` | 1.9.6 | JSON for C++ (separate from `json-c`) |
| `eigen` | 3.4.0_1 (5.0.1 also installed) | Linear algebra — most Citadel packages need 3.4.x |
| `glib` | 2.86.0 (2.88.0 also installed) | Low-level utility (transitive dep of dartsim/Qt) |

### Misc

| Brew formula | Version | Role |
|---|---|---|
| `yaml-cpp` | 0.8.0 | YAML reading |
| `ruby` | 4.0.2 | The `ign` CLI dispatcher uses Ruby |

### Python protobuf (pip, not brew)

| pip package | Version | Why |
|---|---|---|
| `protobuf` | 5.29.6 (or higher in 5.x line) | Must be ≥ gencode emitted by `protobuf@29` (5.29.6). Major must equal gencode major (both 5). |
| `vcstool` | latest | Multi-repo cloner used in #3 |
| `pybind11` | latest | Only needed if you build `citadel-bridge` |

### Notes on multi-version listings

Several formulas show two versions above (e.g. `eigen 3.4.0_1` and
`5.0.1`). Brew keeps both around; the **first** version in the
`brew list --versions` output is the one cmake will resolve via
`pkg-config` and `find_package` because brew's keg-only symlinks
point at the most-recent install. The second is just kept on disk
from a prior `brew install` / `brew upgrade`. If you ever uninstall
the active one, brew falls back to the older one — that can silently
flip your build to a different version, so when something breaks
suddenly check `brew list --versions <pkg>` first.

### Reproducing this exact set later

If a future `brew install` lands a newer version that breaks the build,
pin yours to this snapshot:

```bash
# example: pin protobuf@29 to 29.6 specifically
brew unlink protobuf@29
brew install protobuf@29@29.6 2>/dev/null || \
  echo "older versioned formula not available — see https://github.com/Homebrew/homebrew-versions"
```

In practice, brew generally doesn't keep historical *minor* versions of
unversioned formulas (you can pin `qt@5` but not `qt@5.15.18`), so the
realistic recovery is:

1. `brew pin <formula>` for everything in this snapshot, **right after**
   the build finishes — this prevents `brew upgrade` from quietly moving
   them.
2. If something has already moved, file an issue (#9) with `brew list
   --versions` output of yours next to this table, and we can figure out
   which package's bump broke it.
