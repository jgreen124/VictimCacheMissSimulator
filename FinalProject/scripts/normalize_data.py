#!/usr/bin/env python3
import re
from pathlib import Path

import numpy as np
import pandas as pd

# Inputs/Outputs

RESULTS_ROOT = Path("results/ss")
SUMMARY_IN = RESULTS_ROOT / "ss_summary_all.csv"

OUT_DIR = RESULTS_ROOT / "analysis"
OUT_NORMALIZED = OUT_DIR / "ss_normalized.csv"

# Reference cache point (for reporting)
REF_DL1 = "dl1:1024:32:1:l"
REF_UL2 = "ul2:16384:64:4:l"

# Modes to exclude
EXCLUDE_MODES = {"stream_multi"}

# Parsing Helpers

CFG_RE = re.compile(r"(dl1:\d+:\d+:\d+:[lfr])|(ul2:\d+:\d+:\d+:[lfr])", re.IGNORECASE)

def _to_float(x):
    try:
        if pd.isna(x):
            return np.nan
        s = str(x).strip()
        if s == "":
            return np.nan
        return float(s)
    except Exception:
        return np.nan

def parse_cache_cfg(config_str: str):
    """
    Extract dl1:<nsets>:<bsize>:<assoc>:<repl> and ul2:<...> from a config tag.
    Example:
      miss_stream_mc16_d8__dl1:16:32:1:l__ul2:16384:64:4:l
    """
    dl1 = None
    ul2 = None
    for m in CFG_RE.finditer(str(config_str)):
        token = (m.group(0) or "").lower()
        if token.startswith("dl1:"):
            dl1 = token
        elif token.startswith("ul2:"):
            ul2 = token
    return dl1, ul2

def cache_bytes(cache_cfg: str):
    """
    cache_cfg format: name:nsets:bsize:assoc:repl
    Capacity = nsets * bsize * assoc
    """
    if not cache_cfg or not isinstance(cache_cfg, str):
        return np.nan
    parts = cache_cfg.split(":")
    if len(parts) < 5:
        return np.nan
    try:
        nsets = int(parts[1])
        bsize = int(parts[2])
        assoc = int(parts[3])
        return float(nsets * bsize * assoc)
    except Exception:
        return np.nan

def parse_knobs(config_str: str):
    """
    Parse experiment parameters from the config tag.
    Supports:
      miss_mc8__...
      victim_vc16__...
      stream_d8__...
      victim_stream_vc8_d4__...
      miss_stream_mc16_d8__...
    """
    s = str(config_str).lower()
    vc = re.search(r"(?:^|_)vc(\d+)(?:_|$)", s)
    mc = re.search(r"(?:^|_)mc(\d+)(?:_|$)", s)
    d  = re.search(r"(?:^|_)d(\d+)(?:_|$)",  s)

    vc_entries = float(vc.group(1)) if vc else np.nan
    mc_entries = float(mc.group(1)) if mc else np.nan
    sb_depth   = float(d.group(1))  if d  else np.nan
    return vc_entries, mc_entries, sb_depth

# Data Normalization

def normalize_against_baseline(df: pd.DataFrame) -> pd.DataFrame:
    """
    For each (benchmark, dl1_cfg, ul2_cfg), normalize to baseline values
    at the same cache point.
    """
    key = ["benchmark", "dl1_cfg", "ul2_cfg"]

    base = (
        df[df["mode"] == "baseline"]
        .groupby(key, dropna=False)
        .agg(
            dl1_miss_base=("dl1_miss_rate", "mean"),
            ul2_miss_base=("ul2_miss_rate", "mean"),
            ul2_demand_base=("ul2_demand", "mean"),
            cpi_base=("sim_CPI", "mean"),
        )
        .reset_index()
    )

    out = df.merge(base, on=key, how="left")

    def safe_div(a, b):
        a = _to_float(a)
        b = _to_float(b)
        if np.isnan(a) or np.isnan(b) or b == 0:
            return np.nan
        return a / b

    out["dl1_miss_norm"]   = [safe_div(a, b) for a, b in zip(out["dl1_miss_rate"], out["dl1_miss_base"])]
    out["ul2_miss_norm"]   = [safe_div(a, b) for a, b in zip(out["ul2_miss_rate"], out["ul2_miss_base"])]
    out["ul2_demand_norm"] = [safe_div(a, b) for a, b in zip(out["ul2_demand"], out["ul2_demand_base"])]
    out["cpi_norm"]        = [safe_div(a, b) for a, b in zip(out["sim_CPI"], out["cpi_base"])]

    return out

# Main

def main():
    if not SUMMARY_IN.exists():
        raise SystemExit(f"Missing input CSV: {SUMMARY_IN}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(SUMMARY_IN)

    # Standardize mode
    df["mode"] = df["mode"].astype(str).str.strip().str.lower()
    df = df[~df["mode"].isin(EXCLUDE_MODES)].copy()

    # Parse cache configs from "config" tag
    dl1_ul2 = df["config"].apply(parse_cache_cfg)
    df["dl1_cfg"] = [t[0] for t in dl1_ul2]
    df["ul2_cfg"] = [t[1] for t in dl1_ul2]

    # Derived capacities
    df["dl1_bytes"] = df["dl1_cfg"].apply(cache_bytes)
    df["ul2_bytes"] = df["ul2_cfg"].apply(cache_bytes)

    # Parse parameters
    knobs = df["config"].apply(parse_knobs)
    df["vc_entries"] = [k[0] for k in knobs]
    df["mc_entries"] = [k[1] for k in knobs]
    df["sb_depth"]   = [k[2] for k in knobs]

    # Numeric conversions
    num_cols = [
        "dl1_miss_rate", "ul2_miss_rate", "sim_CPI",
        "vc_hit_rate", "mc_hit_rate", "sb_hit_rate",
        "ul2_total_accesses",
    ]
    for c in num_cols:
        if c in df.columns:
            df[c] = df[c].apply(_to_float)

    # UL2 demand
    df["ul2_demand"] = df["ul2_total_accesses"]

    # Normalize
    norm = normalize_against_baseline(df)

    norm["has_baseline_for_cachepoint"] = ~norm["dl1_miss_base"].isna()

    norm.to_csv(OUT_NORMALIZED, index=False)

    total = len(norm)
    base_missing = int((~norm["has_baseline_for_cachepoint"]).sum())
    print(f"Wrote: {OUT_NORMALIZED} ({total} rows)")
    print(f"Baseline missing for {base_missing} rows (no baseline at that benchmark+DL1+UL2 cache point).")
    print(f"(Reference cache point for analysis: DL1={REF_DL1}, UL2={REF_UL2})")
    print(f"Excluded modes: {sorted(EXCLUDE_MODES)}")

if __name__ == "__main__":
    main()
