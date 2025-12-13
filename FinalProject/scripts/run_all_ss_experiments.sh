#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Run ALL SimpleScalar cache experiments + parameter sweeps.
#
# Usage:
#   bash scripts/run_all_ss_experiments.sh
#   bash scripts/run_all_ss_experiments.sh --clean
#
# Bench file format (config/ss_benchmarks.txt), one per line:
#   <bench_name> <program_path> [args...]
# Example:
#   test-fmath traces/test-fmath
#   test-math  traces/test-math
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BENCH_LIST="${ROOT_DIR}/config/ss_benchmarks.txt"
RUN_ONE="${ROOT_DIR}/scripts/run_ss_cache.sh"

if [[ ! -f "${BENCH_LIST}" ]]; then
  echo "ERROR: missing benchmark list: ${BENCH_LIST}" >&2
  exit 1
fi
if [[ ! -x "${RUN_ONE}" ]]; then
  echo "ERROR: missing or non-executable: ${RUN_ONE}" >&2
  echo "Try: chmod +x ${RUN_ONE}" >&2
  exit 1
fi

CLEAN=0
if [[ "${1:-}" == "--clean" ]]; then
  CLEAN=1
fi

if [[ ${CLEAN} -eq 1 ]]; then
  echo "[run_all] Cleaning prior SS results under: ${ROOT_DIR}/results/ss"
  rm -rf "${ROOT_DIR}/results/ss"
fi

###############################################################################
# Sweep knobs (EDIT THESE)
###############################################################################

# Cache geometries to sweep.
# Keep the config string format: name:nsets:bsize:assoc:repl
IL1_CONFIG="il1:32768:64:1:l"

# DL1 sweeps (direct-mapped, bsize=32)
DL1_CONFIGS=(
  "dl1:16:32:1:l"
  "dl1:64:32:1:l"
  "dl1:256:32:1:l"
  "dl1:1024:32:1:l"
)

# UL2 sweeps (4-way, bsize=64)
UL2_CONFIGS=(
  "ul2:8192:64:4:l"
  "ul2:16384:64:4:l"
  "ul2:32768:64:4:l"
  "ul2:65536:64:4:l"
)

# Buffer size sweeps
MC_ENTRIES_LIST=(2 4 8 16)
VC_ENTRIES_LIST=(2 4 8 16)
SB_DEPTH_LIST=(2 4 8 16)

# Stream buffer fixed defaults (edit if needed)
SB_COUNT_DEFAULT=1
SB_DEGREE_DEFAULT=1

# For combined sweeps, keep one side fixed while sweeping the other.
VC_FIXED=4
MC_FIXED=4
SB_FIXED_DEPTH=4

###############################################################################
# Helpers
###############################################################################

# Resolve program path:
# - if path is absolute, keep it
# - else treat it as ROOT_DIR-relative
resolve_prog_path() {
  local p="$1"
  if [[ "${p}" = /* ]]; then
    printf "%s" "${p}"
  else
    printf "%s" "${ROOT_DIR}/${p}"
  fi
}

# Run all benchmarks for the *current* environment configuration.
run_benchmarks() {
  local raw line
  while IFS= read -r raw || [[ -n "${raw}" ]]; do
    # strip comments
    line="${raw%%#*}"

    # trim leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # skip blank lines
    [[ -z "${line}" ]] && continue

    # shellsplit into array
    local parts=()
    read -r -a parts <<< "${line}"

    # must have at least: bench program
    if (( ${#parts[@]} < 2 )); then
      echo "[run_all] WARNING: skipping malformed benchmark line: '${raw}'" >&2
      continue
    fi

    local bench="${parts[0]}"
    local prog_rel="${parts[1]}"
    local prog
    prog="$(resolve_prog_path "${prog_rel}")"

    local args=()
    if (( ${#parts[@]} > 2 )); then
      args=("${parts[@]:2}")
    fi

    "${RUN_ONE}" "${bench}" "${prog}" "${args[@]}"
  done < "${BENCH_LIST}"
}

# One “experiment point”: choose caches + mode + knobs, set RUN_TAG, source env.sh, run.
run_point() {
  local mode="$1"
  local dl1="$2"
  local ul2="$3"
  local tag="$4"

  export SS_MODE="${mode}"

  export SS_IL1_CONFIG="${IL1_CONFIG}"
  export SS_DL1_CONFIG="${dl1}"
  export SS_UL2_CONFIG="${ul2}"

  # RUN_TAG influences env.sh result directories
  export RUN_TAG="${tag}"

  # Set knobs deterministically. If caller unset them, these defaults apply.
  export SS_VC_ENTRIES="${SS_VC_ENTRIES:-${VC_FIXED}}"
  export SS_MC_ENTRIES="${SS_MC_ENTRIES:-${MC_FIXED}}"
  export SS_SB_COUNT="${SS_SB_COUNT:-${SB_COUNT_DEFAULT}}"
  export SS_SB_DEPTH="${SS_SB_DEPTH:-${SB_FIXED_DEPTH}}"
  export SS_SB_DEGREE="${SS_SB_DEGREE:-${SB_DEGREE_DEFAULT}}"

  # Load env + mode->enable mapping
  # shellcheck source=/dev/null
  source "${ROOT_DIR}/env.sh"

  echo
  echo "============================================================================="
  echo "[run_all] MODE=${SS_MODE}  TAG=${RUN_TAG}"
  echo "[run_all] IL1=${SS_IL1_CONFIG}"
  echo "[run_all] DL1=${SS_DL1_CONFIG}"
  echo "[run_all] UL2=${SS_UL2_CONFIG}"
  echo "[run_all] VC: enable=${SS_VC_ENABLE} entries=${SS_VC_ENTRIES}"
  echo "[run_all] MC: enable=${SS_MC_ENABLE} entries=${SS_MC_ENTRIES}"
  echo "[run_all] SB: enable=${SS_SB_ENABLE} count=${SS_SB_COUNT} depth=${SS_SB_DEPTH} degree=${SS_SB_DEGREE}"
  echo "============================================================================="
  echo

  run_benchmarks
}

###############################################################################
# Main sweep plan
###############################################################################

for dl1 in "${DL1_CONFIGS[@]}"; do
  for ul2 in "${UL2_CONFIGS[@]}"; do

    # -------------------------
    # baseline
    # -------------------------
    (
      unset SS_VC_ENTRIES SS_MC_ENTRIES SS_SB_DEPTH SS_SB_COUNT SS_SB_DEGREE
      run_point "baseline" "${dl1}" "${ul2}" "baseline__${dl1}__${ul2}"
    )

    # -------------------------
    # miss: sweep miss entries
    # -------------------------
    for mc in "${MC_ENTRIES_LIST[@]}"; do
      (
        export SS_MC_ENTRIES="${mc}"
        unset SS_VC_ENTRIES SS_SB_DEPTH SS_SB_COUNT SS_SB_DEGREE
        run_point "miss" "${dl1}" "${ul2}" "miss_mc${mc}__${dl1}__${ul2}"
      )
    done

    # -------------------------
    # victim: sweep victim entries
    # -------------------------
    for vc in "${VC_ENTRIES_LIST[@]}"; do
      (
        export SS_VC_ENTRIES="${vc}"
        unset SS_MC_ENTRIES SS_SB_DEPTH SS_SB_COUNT SS_SB_DEGREE
        run_point "victim" "${dl1}" "${ul2}" "victim_vc${vc}__${dl1}__${ul2}"
      )
    done

    # -------------------------
    # stream: sweep stream depth
    # -------------------------
    for depth in "${SB_DEPTH_LIST[@]}"; do
      (
        export SS_SB_DEPTH="${depth}"
        export SS_SB_COUNT="${SB_COUNT_DEFAULT}"
        export SS_SB_DEGREE="${SB_DEGREE_DEFAULT}"
        unset SS_VC_ENTRIES SS_MC_ENTRIES
        run_point "stream" "${dl1}" "${ul2}" "stream_d${depth}__${dl1}__${ul2}"
      )
    done

    # -------------------------
    # victim_stream:
    #   A) vary victim only (stream fixed)
    #   B) vary stream only (victim fixed)
    #   C) vary both
    # -------------------------

    # A) victim only
    for vc in "${VC_ENTRIES_LIST[@]}"; do
      (
        export SS_VC_ENTRIES="${vc}"
        export SS_SB_DEPTH="${SB_FIXED_DEPTH}"
        export SS_SB_COUNT="${SB_COUNT_DEFAULT}"
        export SS_SB_DEGREE="${SB_DEGREE_DEFAULT}"
        unset SS_MC_ENTRIES
        run_point "victim_stream" "${dl1}" "${ul2}" "victim_stream_vc${vc}_d${SB_FIXED_DEPTH}__${dl1}__${ul2}"
      )
    done

    # B) stream only
    for depth in "${SB_DEPTH_LIST[@]}"; do
      (
        export SS_VC_ENTRIES="${VC_FIXED}"
        export SS_SB_DEPTH="${depth}"
        export SS_SB_COUNT="${SB_COUNT_DEFAULT}"
        export SS_SB_DEGREE="${SB_DEGREE_DEFAULT}"
        unset SS_MC_ENTRIES
        run_point "victim_stream" "${dl1}" "${ul2}" "victim_stream_vc${VC_FIXED}_d${depth}__${dl1}__${ul2}"
      )
    done

    # C) both
    for vc in "${VC_ENTRIES_LIST[@]}"; do
      for depth in "${SB_DEPTH_LIST[@]}"; do
        (
          export SS_VC_ENTRIES="${vc}"
          export SS_SB_DEPTH="${depth}"
          export SS_SB_COUNT="${SB_COUNT_DEFAULT}"
          export SS_SB_DEGREE="${SB_DEGREE_DEFAULT}"
          unset SS_MC_ENTRIES
          run_point "victim_stream" "${dl1}" "${ul2}" "victim_stream_vc${vc}_d${depth}__${dl1}__${ul2}"
        )
      done
    done

    # -------------------------
    # miss_stream:
    #   A) vary miss only (stream fixed)
    #   B) vary stream only (miss fixed)
    #   C) vary both
    # -------------------------

    # A) miss only
    for mc in "${MC_ENTRIES_LIST[@]}"; do
      (
        export SS_MC_ENTRIES="${mc}"
        export SS_SB_DEPTH="${SB_FIXED_DEPTH}"
        export SS_SB_COUNT="${SB_COUNT_DEFAULT}"
        export SS_SB_DEGREE="${SB_DEGREE_DEFAULT}"
        unset SS_VC_ENTRIES
        run_point "miss_stream" "${dl1}" "${ul2}" "miss_stream_mc${mc}_d${SB_FIXED_DEPTH}__${dl1}__${ul2}"
      )
    done

    # B) stream only
    for depth in "${SB_DEPTH_LIST[@]}"; do
      (
        export SS_MC_ENTRIES="${MC_FIXED}"
        export SS_SB_DEPTH="${depth}"
        export SS_SB_COUNT="${SB_COUNT_DEFAULT}"
        export SS_SB_DEGREE="${SB_DEGREE_DEFAULT}"
        unset SS_VC_ENTRIES
        run_point "miss_stream" "${dl1}" "${ul2}" "miss_stream_mc${MC_FIXED}_d${depth}__${dl1}__${ul2}"
      )
    done

    # C) both
    for mc in "${MC_ENTRIES_LIST[@]}"; do
      for depth in "${SB_DEPTH_LIST[@]}"; do
        (
          export SS_MC_ENTRIES="${mc}"
          export SS_SB_DEPTH="${depth}"
          export SS_SB_COUNT="${SB_COUNT_DEFAULT}"
          export SS_SB_DEGREE="${SB_DEGREE_DEFAULT}"
          unset SS_VC_ENTRIES
          run_point "miss_stream" "${dl1}" "${ul2}" "miss_stream_mc${mc}_d${depth}__${dl1}__${ul2}"
        )
      done
    done

  done
done

echo
echo "[run_all] Complete."
