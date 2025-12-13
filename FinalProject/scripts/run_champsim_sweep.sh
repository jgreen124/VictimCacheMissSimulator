#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../env.sh"

# You probably have this set in env.sh:
: "${CS_TRACE_LIST:=${CONFIG_DIR}/champsim_traces.txt}"

if [[ ! -f "${CS_TRACE_LIST}" ]]; then
  echo "ERROR: ChampSim trace list not found: ${CS_TRACE_LIST}" >&2
  exit 1
fi

echo "Using ChampSim trace list: ${CS_TRACE_LIST}"
echo "RUN_TAG           = ${RUN_TAG}"
echo "CHAMPSIM_RESULTS  = ${CHAMPSIM_RESULTS}"
echo "CS_BINARY_NAME    = ${CS_BINARY_NAME}"
echo "CS_WARMUP_INS     = ${CS_WARMUP_INS}"
echo "CS_SIM_INS        = ${CS_SIM_INS}"

while IFS= read -r TRACE || [[ -n "${TRACE}" ]]; do
  # Skip blank lines and comments
  [[ -z "${TRACE}" ]] && continue
  [[ "${TRACE}" =~ ^# ]] && continue

  echo "=== Running ChampSim baseline on trace: ${TRACE} ==="
  if ! run_champsim.sh "${TRACE}" "${CS_WARMUP_INS}" "${CS_SIM_INS}"; then
    echo "WARNING: ChampSim run failed for ${TRACE}" >&2
  fi
done < "${CS_TRACE_LIST}"

echo "ChampSim sweep complete."
