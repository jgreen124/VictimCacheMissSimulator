#!/usr/bin/env bash
# No -e; we want to attempt all benchmarks
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../env.sh"

if [[ -z "${SS_BENCH_LIST:-}" ]]; then
  echo "ERROR: SS_BENCH_LIST is not set in env.sh" >&2
  exit 1
fi

if [[ ! -f "${SS_BENCH_LIST}" ]]; then
  echo "ERROR: SimpleScalar benchmark list not found: ${SS_BENCH_LIST}" >&2
  exit 1
fi

echo "Using SS benchmark list: ${SS_BENCH_LIST}"
echo "SS_RESULTS = ${SS_RESULTS}"

while IFS= read -r LINE || [[ -n "${LINE}" ]]; do
  # Skip blank lines and comments
  [[ -z "${LINE}" ]] && continue
  [[ "${LINE}" =~ ^# ]] && continue

  NAME="${LINE%%:*}"
  BIN_REL="${LINE#*:}"

  if [[ -z "${NAME}" || -z "${BIN_REL}" ]]; then
    echo "WARNING: malformed line in ${SS_BENCH_LIST}: '${LINE}'" >&2
    continue
  fi

  PROG_PATH="${TRACE_DIR}/${BIN_REL}"

  echo "=== Running benchmark: ${NAME} ==="
  echo "Program path: ${PROG_PATH}"

  if ! run_ss_cache.sh "${NAME}" "${PROG_PATH}"; then
    echo "WARNING: benchmark ${NAME} failed (see its baseline txt file)" >&2
  fi
done < "${SS_BENCH_LIST}"

echo "SimpleScalar sweep complete."
