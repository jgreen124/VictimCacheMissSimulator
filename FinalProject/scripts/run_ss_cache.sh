#!/usr/bin/env bash
# Run one SimpleScalar benchmark with cache + experiment config
# Usage: run_ss_cache.sh <benchmark_name> <program> [args...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../env.sh"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <benchmark_name> <program> [args...]" >&2
  exit 1
fi

BENCH_NAME="$1"
shift
BENCH_CMD=( "$@" )

IL1="${SS_IL1_CONFIG}"
DL1="${SS_DL1_CONFIG}"
UL2="${SS_UL2_CONFIG}"

OUT_TXT="${SS_RESULTS}/${BENCH_NAME}_${SS_MODE}.txt"
OUT_CSV="${SS_RESULTS}/ss_${SS_MODE}.csv"

mkdir -p "${SS_RESULTS}"

echo "Running sim-cache for benchmark: ${BENCH_NAME}"
echo "Command: ${BENCH_CMD[*]}"
echo "IL1=${IL1}, DL1=${DL1}, UL2=${UL2}"
echo "Mode=${SS_MODE}, VC=${SS_VC_ENABLE}/${SS_VC_ENTRIES}, SB=${SS_SB_ENABLE}x${SS_SB_COUNT}x${SS_SB_DEPTH}"
echo "Results directory: ${SS_RESULTS}"
echo "Text output: ${OUT_TXT}"
echo "CSV output:  ${OUT_CSV}"

"${SS_ROOT}/sim-cache" \
  -redir:sim "${OUT_TXT}" \
  -cache:il1 "${IL1}" \
  -cache:dl1 "${DL1}" \
  -cache:il2 "${UL2}" \
  -cache:dl2 "${UL2}" \
  -exp:mode "${SS_MODE}" \
  -vc:enable "${SS_VC_ENABLE}" \
  -vc:entries "${SS_VC_ENTRIES}" \
  -mc:enable "${SS_MC_ENABLE}" \
  -mc:entries "${SS_MC_ENTRIES}" \
  -sb:enable "${SS_SB_ENABLE}" \
  -sb:count  "${SS_SB_COUNT}" \
  -sb:depth  "${SS_SB_DEPTH}" \
  -sb:degree "${SS_SB_DEGREE}" \
  "${BENCH_CMD[@]}"
STATUS=$?

if [[ ${STATUS} -ne 0 ]]; then
  echo "WARNING: sim-cache exited with status ${STATUS} for benchmark ${BENCH_NAME}" >&2
fi

echo "Simulation complete. Parsing metrics (if available)..."

# ----------------------------------------------
# Basic stats
# ----------------------------------------------
IL1_MISS_RATE=$(grep -m1 "il1.miss_rate"      "${OUT_TXT}" 2>/dev/null | awk '{print $2}' || true)
DL1_MISS_RATE=$(grep -m1 "dl1.miss_rate"      "${OUT_TXT}" 2>/dev/null | awk '{print $2}' || true)
UL2_MISS_RATE=$(grep -m1 "ul2.miss_rate"      "${OUT_TXT}" 2>/dev/null | awk '{print $2}' || true)

SIM_NUM_INSN=$(grep -m1 "sim_num_insn"        "${OUT_TXT}" 2>/dev/null | awk '{print $2}' || true)
SIM_ELAPSED_TIME=$(grep -m1 "sim_elapsed_time" "${OUT_TXT}" 2>/dev/null | awk '{print $2}' || true)
SIM_CPI=$(grep -m1 "sim_CPI"                 "${OUT_TXT}" 2>/dev/null | awk '{print $2}' || true)

UL2_D_ACCESSES=$(grep -m1 "ul2_d_accesses"   "${OUT_TXT}" 2>/dev/null | awk '{print $2}' || true)
UL2_I_ACCESSES=$(grep -m1 "ul2_i_accesses"   "${OUT_TXT}" 2>/dev/null | awk '{print $2}' || true)

# ----------------------------------------------
# Initialize all optional counters to 0
# ----------------------------------------------
VC_LOOKUPS=0
VC_HITS=0
MC_LOOKUPS=0
MC_HITS=0
SB_LOOKUPS=0
SB_HITS=0
SB_PREFETCHES=0

# ----------------------------------------------
# Mode-specific stats
# ----------------------------------------------

# Victim cache stats (victim-only or victim+stream)
if [[ "${SS_MODE}" == "victim" || "${SS_MODE}" == "victim_stream" ]]; then
  VC_LOOKUPS=$(grep -m1 "vc_lookups" "${OUT_TXT}" 2>/dev/null | awk '{print $2}' || echo 0)
  VC_HITS=$(grep -m1 "vc_hits"       "${OUT_TXT}" 2>/dev/null | awk '{print $2}' || echo 0)
fi

# Miss cache stats
if [[ "${SS_MODE}" == "miss" ]]; then
  MC_LOOKUPS=$(grep -m1 "mc_lookups" "${OUT_TXT}" 2>/dev/null | awk '{print $2}' || echo 0)
  MC_HITS=$(grep -m1 "mc_hits"       "${OUT_TXT}" 2>/dev/null | awk '{print $2}' || echo 0)
fi

# Stream buffer stats (stream-only, multi-stream, or victim+stream)
if [[ "${SS_MODE}" == "stream" || "${SS_MODE}" == "stream_multi" || "${SS_MODE}" == "victim_stream" ]]; then
  SB_LOOKUPS=$(grep -m1 "sb_lookups"    "${OUT_TXT}" 2>/dev/null | awk '{print $2}' || echo 0)
  SB_HITS=$(grep -m1 "sb_hits"          "${OUT_TXT}" 2>/dev/null | awk '{print $2}' || echo 0)
  SB_PREFETCHES=$(grep -m1 "sb_prefetches" "${OUT_TXT}" 2>/dev/null | awk '{print $2}' || echo 0)
fi

# Miss cache stats
if [[ "${SS_MODE}" == "miss" || "${SS_MODE}" == "miss_stream" ]]; then
  MC_LOOKUPS=$(grep -m1 "mc_lookups" "${OUT_TXT}" | awk '{print $2}' || echo 0)
  MC_HITS=$(grep -m1 "mc_hits" "${OUT_TXT}" | awk '{print $2}' || echo 0)
fi

# Stream buffer stats
if [[ "${SS_MODE}" == "stream" || "${SS_MODE}" == "stream_multi" || \
      "${SS_MODE}" == "victim_stream" || "${SS_MODE}" == "miss_stream" ]]; then
  SB_LOOKUPS=$(grep -m1 "sb_lookups" "${OUT_TXT}" | awk '{print $2}' || echo 0)
  SB_HITS=$(grep -m1 "sb_hits" "${OUT_TXT}" | awk '{print $2}' || echo 0)
  SB_PREFETCHES=$(grep -m1 "sb_prefetches" "${OUT_TXT}" | awk '{print $2}' || echo 0)
fi


# ----------------------------------------------
# Emit CSV
# ----------------------------------------------
if [[ ! -f "${OUT_CSV}" ]]; then
  echo "benchmark,mode,il1_miss_rate,dl1_miss_rate,ul2_miss_rate,sim_num_insn,sim_elapsed_time,sim_CPI,vc_lookups,vc_hits,mc_lookups,mc_hits,sb_lookups,sb_hits,sb_prefetches,ul2_d_accesses,ul2_i_accesses" \
    > "${OUT_CSV}"
fi

echo "${BENCH_NAME},${SS_MODE},${IL1_MISS_RATE},${DL1_MISS_RATE},${UL2_MISS_RATE},${SIM_NUM_INSN},${SIM_ELAPSED_TIME},${SIM_CPI},${VC_LOOKUPS},${VC_HITS},${MC_LOOKUPS},${MC_HITS},${SB_LOOKUPS},${SB_HITS},${SB_PREFETCHES},${UL2_D_ACCESSES},${UL2_I_ACCESSES}" \
  >> "${OUT_CSV}"

echo "Metrics appended to ${OUT_CSV}"
