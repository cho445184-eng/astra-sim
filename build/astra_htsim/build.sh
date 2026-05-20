#!/bin/bash
set -e
set -x

# set paths
SCRIPT_DIR=$(dirname "$(realpath "$0")")
PROJECT_DIR="${SCRIPT_DIR:?}/../.."
BUILD_DIR="${SCRIPT_DIR:?}"/build
# set functions
function setup() {
  # make build directory if one doesn't exist
  if [[ ! -d "${BUILD_DIR:?}" ]]; then
    mkdir -p "${BUILD_DIR:?}"
  fi

  # set concurrent build threads, capped at 16
  NUM_THREADS=$(nproc)
  if [[ ${NUM_THREADS} -ge 16 ]]; then
    NUM_THREADS=16
  fi
}

function patch_htsim() {
  patch -p1 -d "${SCRIPT_DIR:?}"/../../extern/network_backend/csg-htsim \
    --forward --reject-file=- -i "${SCRIPT_DIR:?}"/htsim_astrasim.patch && true
  ret=$?
  if [[ $ret -eq 0 ]]; then
    echo "HTSim patch applied successfully"
  elif [[ $ret -eq 1 ]]; then
    echo "HTSim patch skipped"
  else
    echo "HTSim patch failed"
    exit 1
  fi
}

function compile_astrasim_htsim() {
  # compile AstraSim
  cd "${BUILD_DIR:?}" || exit
  cmake ..
  cmake --build . -j "${NUM_THREADS:?}"
}

function compile_astrasim_htsim_as_debug() {
  # compile AstraSim
  cd "${BUILD_DIR:?}" || exit
  cmake .. -DCMAKE_BUILD_TYPE=Debug
  cmake --build . --config=Debug -j "${NUM_THREADS:?}"
}

function cleanup() {
  rm -rf "${BUILD_DIR:?}"
}

# set default option values
build_as_debug=false
should_clean=false

# Process command-line options
while getopts "ldr" OPT; do
  case "${OPT:?}" in
  l)
    should_clean=true
    ;;
  d)
    build_as_debug=true
    ;;
  *)
    exit 1
    ;;
  esac
done

# run operations as required
if [[ ${should_clean:?} == true ]]; then
  cleanup
else
  # setup ASTRA-sim build
  setup
  patch_htsim

  # compile ASTRA-sim
  if [[ ${build_as_debug:?} == true ]]; then
    compile_astrasim_htsim_as_debug
  else
    compile_astrasim_htsim
  fi
fi
