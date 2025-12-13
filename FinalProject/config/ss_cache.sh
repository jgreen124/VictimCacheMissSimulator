# config/ss_cache.sh
# SimpleScalar cache and experiment configuration

########################################
# Base cache geometry
########################################

# # L1 instruction cache
# export SS_IL1_CONFIG="il1:32768:64:1:l"

# # L1 data cache (tiny DL1)
# export SS_DL1_CONFIG="dl1:16:32:1:l"

# # Unified L2 cache (small UL2)
# export SS_UL2_CONFIG="ul2:8192:64:4:l"

export SS_IL1_CONFIG="${SS_IL1_CONFIG:-il1:32768:64:1:l}"
export SS_DL1_CONFIG="${SS_DL1_CONFIG:-dl1:16:32:1:l}"
export SS_UL2_CONFIG="${SS_UL2_CONFIG:-ul2:8192:64:4:l}"

########################################
# Experiment mode
########################################
# Valid values:
#   baseline
#   victim
#   miss
#   stream
#   stream_multi
#   victim_stream
#
# You can override this from the environment, e.g.:
#   SS_MODE=miss ss_sweep

export SS_MODE="${SS_MODE:-baseline}"

########################################
# Default parameters (can be overridden by mode)
########################################

# Victim cache parameters
SS_VC_ENTRIES="${SS_VC_ENTRIES:-4}"

# Miss cache parameters
SS_MC_ENTRIES="${SS_MC_ENTRIES:-4}"

# Stream buffer parameters
SS_SB_COUNT="${SS_SB_COUNT:-1}"
SS_SB_DEPTH="${SS_SB_DEPTH:-4}"
SS_SB_DEGREE="${SS_SB_DEGREE:-1}"

########################################
# Mode → feature mapping
########################################

case "${SS_MODE}" in
  baseline)
    SS_VC_ENABLE=0
    SS_MC_ENABLE=0
    SS_SB_ENABLE=0
    ;;

  victim)
    SS_VC_ENABLE=1
    SS_MC_ENABLE=0
    SS_SB_ENABLE=0
    ;;

  miss)
    SS_VC_ENABLE=0
    SS_MC_ENABLE=1
    SS_SB_ENABLE=0
    ;;

  stream)
    SS_VC_ENABLE=0
    SS_MC_ENABLE=0
    SS_SB_ENABLE=1
    ;;

  stream_multi)
    SS_VC_ENABLE=0
    SS_MC_ENABLE=0
    SS_SB_ENABLE=1
    SS_SB_COUNT="${SS_SB_COUNT:-4}"
    ;;

  victim_stream)
    SS_VC_ENABLE=1
    SS_MC_ENABLE=0
    SS_SB_ENABLE=1
    ;;

    miss_stream)
    SS_VC_ENABLE=0
    SS_MC_ENABLE=1
    SS_SB_ENABLE=1
    ;;
  *)
    echo "[ss_cache.sh] WARNING: unknown SS_MODE='${SS_MODE}', defaulting to baseline" >&2
    SS_VC_ENABLE=0
    SS_MC_ENABLE=0
    SS_SB_ENABLE=0
    ;;
esac

# Export fields for run_ss_cache.sh
export SS_VC_ENABLE SS_VC_ENTRIES
export SS_MC_ENABLE SS_MC_ENTRIES
export SS_SB_ENABLE SS_SB_COUNT SS_SB_DEPTH SS_SB_DEGREE
