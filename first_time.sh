#!/usr/bin/env zsh

set -euo pipefail

########################################
# Homebrew dependency check
########################################

required=(
  cmake pkg-config doxygen graphviz
  qt@5
  freeimage libzzip
  tinyxml tinyxml2 protobuf@29 zeromq cppzmq libzip
  json-c urdfdom rapidjson
  dartsim assimp fcl gts
  tbb jsoncpp eigen glib
  ffmpeg ruby
)

# tinyxml v1 was disabled in homebrew-core on 2025-06-03 (deprecated upstream).
# A revived copy lives in the kakcalu13/legacy tap so plain `brew install
# tinyxml` works again. Adding the tap is idempotent; installing tinyxml here
# (before the required-check loop below) means the loop will see it as
# already-present and not flag it as missing.
brew tap kakcalu13/legacy
brew install kakcalu13/legacy/tinyxml

missing=()

for pkg in "${required[@]}"; do
  if ! brew list --versions "$pkg" >/dev/null 2>&1; then
    missing+=("$pkg")
  fi
done

pip3 install colcon-common-extensions

if (( ${#missing[@]} > 0 )); then
  echo "You don't have these Homebrew libraries/tools installed:"
  for pkg in "${missing[@]}"; do
    echo "  - $pkg"
  done
  echo
  echo "If you want to install them, run:"
  echo "  brew install ${missing[@]}"
  exit 1
fi

########################################
# OGRE build and Citadel build
########################################

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

cmake --build . --target install -j"$(sysctl -n hw.logicalcpu)"

FWK=~/citadel-gui/install/lib/RelWithDebInfo
ln -sf "$FWK/Ogre.framework/Versions/2.3.3/Ogre"                     ~/citadel-gui/install/lib/libOgreMain.dylib
ln -sf "$FWK/OgreHlmsPbs.framework/Versions/2.3.3/OgreHlmsPbs"       ~/citadel-gui/install/lib/libOgreHlmsPbs.dylib
ln -sf "$FWK/OgreHlmsUnlit.framework/Versions/2.3.3/OgreHlmsUnlit"   ~/citadel-gui/install/lib/libOgreHlmsUnlit.dylib

mkdir -p ~/citadel-gui/install/lib/OGRE
for plug in RenderSystem_Metal RenderSystem_GL3Plus RenderSystem_NULL Plugin_ParticleFX; do
  ln -sfn "$FWK/${plug}.framework/Versions/2.3.3/${plug}" \
         ~/citadel-gui/install/lib/OGRE/${plug}.dylib
done

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

cd ~/citadel-gui/src
for f in \
  gz-rendering/ogre/src/CMakeLists.txt \
  gz-rendering/ogre2/src/CMakeLists.txt \
  gz-physics/dartsim/CMakeLists.txt \
  gz-physics/tpe/plugin/CMakeLists.txt
do
  sed -i '' \
    's|EXECUTE_PROCESS(COMMAND ${CMAKE_COMMAND} -E create_symlink ${versioned} ${unversioned})|EXECUTE_PROCESS(COMMAND ${CMAKE_COMMAND} -E create_symlink ${versioned} ${unversioned} WORKING_DIRECTORY ${PROJECT_BINARY_DIR})|' \
    "$f"
done

# Hide ogre-next (built manually in §4) and citadel-bridge (optional Python
# bridge, commented out of the yaml by default) from colcon. Only mark
# packages that are actually present on disk — citadel-bridge typically
# isn't, since users opt in by uncommenting it in collection-mac-citadel.yaml
# and re-running vcs import.
for marker_pkg in ogre-next citadel-bridge; do
  pkg_dir=~/citadel-gui/src/$marker_pkg
  if [ -d "$pkg_dir" ]; then
    touch "$pkg_dir/COLCON_IGNORE"
  fi
done

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

FWK=~/citadel-gui/install/lib/RelWithDebInfo
ABS_OGRE="$FWK/Ogre.framework/Versions/2.3.3/Ogre"

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

for DYLIB in \
  ~/citadel-gui/install/lib/ign-rendering-3/engine-plugins/libignition-rendering3-ogre2.3.7.2.dylib \
  ~/citadel-gui/install/lib/libignition-rendering3-ogre2.3.7.2.dylib
  do
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

export PATH=~/citadel-gui/install/bin:$PATH
export IGN_CONFIG_PATH=~/citadel-gui/install/share/ignition
export IGN_RENDERING_PLUGIN_PATH=~/citadel-gui/install/lib/ign-rendering-3/engine-plugins
export IGN_GAZEBO_SYSTEM_PLUGIN_PATH=~/citadel-gui/install/lib/ign-gazebo-3/plugins
export IGN_GUI_PLUGIN_PATH=~/citadel-gui/install/lib/ign-gui-3/plugins
export DYLD_LIBRARY_PATH=~/citadel-gui/install/lib:~/citadel-gui/install/lib/RelWithDebInfo:${DYLD_LIBRARY_PATH-}


echo "Built everything for you. This steps are shown in the SETUP.md"
echo "==============================="
echo "Now you just need to 'source ~/citadel-gui/install/setup.zsh' in your terminal then run 'ign gazebo' like linux"
echo "=-----------------------------="