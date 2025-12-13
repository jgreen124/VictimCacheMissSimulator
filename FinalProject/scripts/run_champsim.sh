#!/usr/bin/env bash
# No -e; we want to keep going even if a run fails
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../env.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <trace_basename> [warmup_ins] [sim_ins]" >&2
  echo "Example: $0 600.perlbench_s-210B.champsimtrace.xz 1000000 10000000" >&2
  exit 1
fi

TRACE_BASENAME="$1"
WARMUP_INS="${2:-${CS_WARMUP_INS}}"
SIM_INS="${3:-${CS_SIM_INS}}"

BIN_NAME="${CS_BINARY_NAME:-champsim}"
BIN_PATH="${CHAMPSIM_ROOT}/bin/${BIN_NAME}"
TRACE_PATH="${TRACE_DIR}/${TRACE_BASENAME}"

if [[ ! -x "${BIN_PATH}" ]]; then
  echo "ERROR: ChampSim binary not found or not executable: ${BIN_PATH}" >&2
  exit 1
fi

if [[ ! -f "${TRACE_PATH}" ]]; then
  echo "ERROR: trace file not found: ${TRACE_PATH}" >&2
  exit 1
fi

# Strip suffix for cleaner output filename
BASE_TRACE_NAME="${TRACE_BASENAME%.champsimtrace.xz}"
BASE_TRACE_NAME="${BASE_TRACE_NAME%.champsimtrace}"

OUT_TXT="${CHAMPSIM_RESULTS}/${BASE_TRACE_NAME}_baseline.txt"
OUT_CSV="${CHAMPSIM_RESULTS}/champsim_baseline.csv"

mkdir -p "${CHAMPSIM_RESULTS}"

echo "Running ChampSim:"
echo "  RUN_TAG      = ${RUN_TAG}"
echo "  Results dir  = ${CHAMPSIM_RESULTS}"
echo "  Binary       = ${BIN_PATH}"
echo "  Trace        = ${TRACE_PATH}"
echo "  Warmup ins   = ${WARMUP_INS}"
echo "  Sim ins      = ${SIM_INS}"
echo "  Output txt   = ${OUT_TXT}"

"${BIN_PATH}" \
  --warmup_instructions "${WARMUP_INS}" \
  --simulation_instructions "${SIM_INS}" \
  "${TRACE_PATH}" \
  > "${OUT_TXT}"
STATUS=$?

if [[ ${STATUS} -ne 0 ]]; then
  echo "WARNING: ChampSim exited with status ${STATUS} for trace ${TRACE_BASENAME}" >&2
fi

echo "Run complete. Parsing metrics (if available)..."

INSTRUCTIONS=$(grep -m1 "Total Instructions" "${OUT_TXT}" 2>/dev/null | awk '{print $NF}' || true)
CYCLES=$(grep -m1 "Total Cycles" "${OUT_TXT}" 2>/dev/null | awk '{print $NF}' || true)

L1D_MISS_RATE=$(grep -m1 "L1D total miss rate" "${OUT_TXT}" 2>/dev/null | awk '{print $NF}' || true)
L1I_MISS_RATE=$(grep -m1 "L1I total miss rate" "${OUT_TXT}" 2>/dev/null | awk '{print $NF}' || true)
LLC_MISS_RATE=$(grep -m1 "LLC total miss rate" "${OUT_TXT}" 2>/dev/null | awk '{print $NF}' || true)

if [[ ! -f "${OUT_CSV}" ]]; then
  echo "trace,l1i_miss_rate,l1d_miss_rate,llc_miss_rate,instructions,cycles,warmup_ins,sim_ins" \
    > "${OUT_CSV}"
fi

echo "${BASE_TRACE_NAME},${L1I_MISS_RATE},${L1D_MISS_RATE},${LLC_MISS_RATE},${INSTRUCTIONS},${CYCLES},${WARMUP_INS},${SIM_INS}" \
  >> "${OUT_CSV}"

echo "Metrics appended to ${OUT_CSV}"
