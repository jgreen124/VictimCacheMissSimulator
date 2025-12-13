#!/usr/bin/env bash
#
# Unified environment setup for SimpleScalar + ChampSim experiments
# Supports RUN_TAG tagging, config files, and sweep automation.
#

# Project Root
export PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Tool Roots
export SS_ROOT="${PROJECT_ROOT}/simplesim-3.0"
export CHAMPSIM_ROOT="${PROJECT_ROOT}/ChampSim"

# Trace Directory
export TRACE_DIR="${PROJECT_ROOT}/traces"

#Config Directory
export CONFIG_DIR="${PROJECT_ROOT}/config"
mkdir -p "${CONFIG_DIR}"

# Lists of workloads
export SS_BENCH_LIST="${CONFIG_DIR}/ss_benchmarks.txt"
export CS_TRACE_LIST="${CONFIG_DIR}/champsim_traces.txt"

# Run Tagging (for results organization)
: "${RUN_TAG:=latest}"
export RUN_TAG

# Results Root Directory
export RESULTS_ROOT="${PROJECT_ROOT}/results"

# SimpleScalar results
export SS_RESULTS="${RESULTS_ROOT}/ss/${RUN_TAG}"

# ChampSim results
export CHAMPSIM_RESULTS="${RESULTS_ROOT}/champsim/${RUN_TAG}"

mkdir -p "${SS_RESULTS}" "${CHAMPSIM_RESULTS}"

# SimpleSim configuration
# Defaults may be overridden via config/ss_cache.sh
export SS_IL1_CONFIG="${SS_IL1_CONFIG:-il1:32768:64:1:l}"
export SS_DL1_CONFIG="${SS_DL1_CONFIG:-dl1:32768:64:1:l}"
export SS_UL2_CONFIG="${SS_UL2_CONFIG:-ul2:262144:64:4:l}"
export SS_MODE="${SS_MODE:-baseline}"

if [[ -f "${CONFIG_DIR}/ss_cache.sh" ]]; then
    . "${CONFIG_DIR}/ss_cache.sh"
fi


# Optional modes for SimpleSim experiments (baseline, prefetch, etc.)
export SS_MODE="${SS_MODE:-baseline}"

# Load SS overrides if present
if [[ -f "${CONFIG_DIR}/ss_cache.sh" ]]; then
    . "${CONFIG_DIR}/ss_cache.sh"
fi
  
# ChampSim configuration
# Defaults may be overridden via config/champsim_run.sh
export CS_BINARY_NAME="${CS_BINARY_NAME:-champsim}"
export CS_WARMUP_INS="${CS_WARMUP_INS:-1000000}"
export CS_SIM_INS="${CS_SIM_INS:-10000000}"

# Load ChampSim overrides if present
if [[ -f "${CONFIG_DIR}/champsim_run.sh" ]]; then
    . "${CONFIG_DIR}/champsim_run.sh"
fi

# Paths and Aliases

# Add scripts directory to PATH for convenience
export PATH="${PROJECT_ROOT}/scripts:${PATH}"

# Quick navigation
alias cproj='cd "${PROJECT_ROOT}"'
alias css='cd "${SS_ROOT}"'
alias ccs='cd "${CHAMPSIM_ROOT}"'

# Sweeps
alias ss_sweep='run_ss_sweep.sh'
alias cs_sweep='run_champsim_sweep.sh'

# Quick views of latest CSVs
alias ss_csv='column -s, -t < "${SS_RESULTS}/ss_baseline.csv" | less'
alias cs_csv='column -s, -t < "${CHAMPSIM_RESULTS}/champsim_baseline.csv" | less'

# "Last output" helpers
alias ss_last='ls -1t "${SS_RESULTS}"/*.txt 2>/dev/null | head -n 1 | xargs -r tail -n 40'
alias cs_last='ls -1t "${CHAMPSIM_RESULTS}"/*.txt 2>/dev/null | head -n 1 | xargs -r tail -n 40'

# Debug info
echo "[env.sh] Loaded with RUN_TAG='${RUN_TAG}'"
echo "[env.sh] SS_RESULTS='${SS_RESULTS}'"
echo "[env.sh] CHAMPSIM_RESULTS='${CHAMPSIM_RESULTS}'"
echo "[env.sh] SS_CACHE: IL1=${SS_IL1_CONFIG}, DL1=${SS_DL1_CONFIG}, UL2=${SS_UL2_CONFIG}"
echo "[env.sh] ChampSim binary='${CS_BINARY_NAME}', Warmup=${CS_WARMUP_INS}, Sim=${CS_SIM_INS}"
echo
