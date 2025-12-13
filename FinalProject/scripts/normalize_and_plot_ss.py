#!/usr/bin/env python3
import re
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

###############################################################################
# Inputs / outputs
###############################################################################

RESULTS_ROOT = Path("results/ss")
SUMMARY_IN = RESULTS_ROOT / "ss_summary_all.csv"

OUT_DIR = RESULTS_ROOT / "analysis"
PLOTS_DIR = OUT_DIR / "plots"
OUT_NORMALIZED = OUT_DIR / "ss_normalized.csv"

# Reference cache point (used for knob-sweep plots + bar charts)
REF_DL1 = "dl1:1024:32:1:l"
REF_UL2 = "ul2:16384:64:4:l"

# Reference knob settings (used to isolate clean lines)
REF_VC = 4
REF_MC = 4
REF_SB_DEPTH = 4

# Exclude modes you don't want to plot
EXCLUDE_MODES = {"stream_multi"}  # you said remove multi-buffer sims for now

MODE_ORDER = ["baseline", "victim", "miss", "stream", "victim_stream", "miss_stream"]

###############################################################################
# Parsing helpers
###############################################################################

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
    dl1 = None
    ul2 = None
    for m in CFG_RE.finditer(str(config_str)):
        tok = (m.group(0) or "").lower()
        if tok.startswith("dl1:"):
            dl1 = tok
        elif tok.startswith("ul2:"):
            ul2 = tok
    return dl1, ul2

def cache_bytes(cache_cfg: str):
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
    Parse knobs from your RUN_TAG-based config directory name.
    Supports:
      victim_vc16__...
      miss_mc8__...
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

###############################################################################
# Normalization
###############################################################################

def normalize_against_baseline(df: pd.DataFrame):
    """
    Normalize per (benchmark, dl1_cfg, ul2_cfg) against baseline rows at that same cache point.
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

    out["dl1_miss_norm"]    = [safe_div(a, b) for a, b in zip(out["dl1_miss_rate"], out["dl1_miss_base"])]
    out["ul2_miss_norm"]    = [safe_div(a, b) for a, b in zip(out["ul2_miss_rate"], out["ul2_miss_base"])]
    out["ul2_demand_norm"]  = [safe_div(a, b) for a, b in zip(out["ul2_demand"], out["ul2_demand_base"])]
    out["cpi_norm"]         = [safe_div(a, b) for a, b in zip(out["sim_CPI"], out["cpi_base"])]

    return out

###############################################################################
# Plot helpers
###############################################################################

def ensure_dirs():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    PLOTS_DIR.mkdir(parents=True, exist_ok=True)

def savefig(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    plt.tight_layout()
    plt.savefig(path, dpi=150)
    plt.close()

def agg_for_lines(df: pd.DataFrame, xcol: str, ycol: str):
    """
    Collapse duplicates so each (mode, x) has a single y (mean).
    """
    g = df.dropna(subset=[xcol, ycol]).copy()
    if g.empty:
        return g
    return (
        g.groupby(["mode", xcol], dropna=False, as_index=False)
         .agg({ycol: "mean"})
    )

def lineplot_by_mode(df, xcol, ycol, title, xlabel, ylabel, outpath, mode_order):
    plt.figure()
    g = agg_for_lines(df, xcol, ycol)
    if g.empty:
        return

    for mode in [m for m in mode_order if m in set(g["mode"].unique())]:
        gm = g[g["mode"] == mode].sort_values(xcol)
        if gm.empty:
            continue
        plt.plot(gm[xcol].astype(float), gm[ycol].astype(float), marker="o", label=mode)

    plt.title(title)
    plt.xlabel(xlabel)
    plt.ylabel(ylabel)
    plt.grid(True, linestyle="--", linewidth=0.5)
    plt.legend()
    savefig(outpath)

def barplot_mechanism(df, ycol, title, ylabel, outpath, mode_order):
    plt.figure(figsize=(10, 4))
    g = df.dropna(subset=[ycol]).copy()
    if g.empty:
        return

    benches = sorted(g["benchmark"].unique())
    modes = [m for m in mode_order if m in set(g["mode"].unique())]

    x = np.arange(len(benches))
    width = 0.12 if len(modes) > 0 else 0.2

    for i, mode in enumerate(modes):
        vals = []
        for b in benches:
            sub = g[(g["benchmark"] == b) & (g["mode"] == mode)]
            vals.append(sub[ycol].mean() if not sub.empty else np.nan)
        plt.bar(x + (i - len(modes)/2)*width + width/2, vals, width=width, label=mode)

    plt.xticks(x, benches, rotation=0)
    plt.title(title)
    plt.ylabel(ylabel)
    plt.grid(True, axis="y", linestyle="--", linewidth=0.5)
    plt.legend(ncol=3)
    savefig(outpath)

###############################################################################
# Reference filtering (this is the fix for “vertical lines / only one mode”)
###############################################################################

def filter_ref_knobs_for_mode(df: pd.DataFrame, mode: str):
    """
    For “size sweep” plots, ensure each mode is taken at a consistent knob setting
    so you get one clean line per mode (not multiple interleaved sweeps).
    """
    g = df[df["mode"] == mode].copy()

    if mode == "baseline":
        return g

    if mode == "victim":
        return g[g["vc_entries"] == REF_VC]

    if mode == "miss":
        return g[g["mc_entries"] == REF_MC]

    if mode == "stream":
        return g[g["sb_depth"] == REF_SB_DEPTH]

    if mode == "victim_stream":
        return g[(g["vc_entries"] == REF_VC) & (g["sb_depth"] == REF_SB_DEPTH)]

    if mode == "miss_stream":
        return g[(g["mc_entries"] == REF_MC) & (g["sb_depth"] == REF_SB_DEPTH)]

    # default fallback: return as-is
    return g

def filter_ref_knobs_all_modes(df: pd.DataFrame):
    parts = []
    for m in sorted(df["mode"].unique()):
        parts.append(filter_ref_knobs_for_mode(df, m))
    if not parts:
        return df.iloc[0:0]
    return pd.concat(parts, ignore_index=True)

###############################################################################
# Main
###############################################################################

def main():
    ensure_dirs()

    if not SUMMARY_IN.exists():
        raise SystemExit(f"Missing input: {SUMMARY_IN}")

    df = pd.read_csv(SUMMARY_IN)

    # Standardize mode strings
    df["mode"] = df["mode"].astype(str).str.strip().str.lower()
    df = df[~df["mode"].isin(EXCLUDE_MODES)].copy()

    # Parse cache configs
    dl1_ul2 = df["config"].apply(parse_cache_cfg)
    df["dl1_cfg"] = [t[0] for t in dl1_ul2]
    df["ul2_cfg"] = [t[1] for t in dl1_ul2]

    df["dl1_bytes"] = df["dl1_cfg"].apply(cache_bytes)
    df["ul2_bytes"] = df["ul2_cfg"].apply(cache_bytes)

    # Parse knobs
    knobs = df["config"].apply(parse_knobs)
    df["vc_entries"] = [k[0] for k in knobs]
    df["mc_entries"] = [k[1] for k in knobs]
    df["sb_depth"]   = [k[2] for k in knobs]

    # Numeric conversions
    num_cols = [
        "dl1_miss_rate", "ul2_miss_rate", "sim_CPI",
        "vc_hit_rate", "mc_hit_rate", "sb_hit_rate",
        "ul2_total_accesses"
    ]
    for c in num_cols:
        if c in df.columns:
            df[c] = df[c].apply(_to_float)

    # Define UL2 demand
    df["ul2_demand"] = df["ul2_total_accesses"]

    # Normalize
    norm = normalize_against_baseline(df)
    norm.to_csv(OUT_NORMALIZED, index=False)
    print(f"Wrote: {OUT_NORMALIZED}  ({len(norm)} rows)")
    print(f"Reference cache point: DL1={REF_DL1}  UL2={REF_UL2}")
    print(f"Reference knobs: VC={REF_VC} MC={REF_MC} SB_DEPTH={REF_SB_DEPTH}")
    print(f"Excluded modes: {sorted(EXCLUDE_MODES)}")

    # -----------------------------------------------------------------------
    # (1) DL1 size vs DL1 miss (RAW and normalized) — per benchmark, per UL2
    #     FIX: filter to reference knobs per mode so each mechanism is one line
    # -----------------------------------------------------------------------
    out1_raw  = PLOTS_DIR / "1_cache_size_vs_miss" / "dl1_size_vs_dl1_miss_raw"
    out1_norm = PLOTS_DIR / "1_cache_size_vs_miss" / "dl1_size_vs_dl1_miss_norm"

    for (bench, ul2_cfg), g in norm.groupby(["benchmark", "ul2_cfg"], dropna=False):
        if pd.isna(ul2_cfg):
            continue
        g2 = filter_ref_knobs_all_modes(g)

        title_raw = f"{bench}: DL1 miss rate vs DL1 size (RAW)\nUL2={ul2_cfg}"
        lineplot_by_mode(
            g2, "dl1_bytes", "dl1_miss_rate",
            title_raw, "DL1 size (bytes)", "DL1 miss rate",
            out1_raw / f"{bench}__dl1miss_raw_vs_dl1__ul2_{ul2_cfg.replace(':','-')}.png",
            MODE_ORDER
        )

        title_norm = f"{bench}: DL1 miss rate vs DL1 size (normalized to baseline)\nUL2={ul2_cfg}"
        lineplot_by_mode(
            g2, "dl1_bytes", "dl1_miss_norm",
            title_norm, "DL1 size (bytes)", "DL1 miss rate (normalized)",
            out1_norm / f"{bench}__dl1miss_norm_vs_dl1__ul2_{ul2_cfg.replace(':','-')}.png",
            MODE_ORDER
        )

    # -----------------------------------------------------------------------
    # (2) Mechanism vs DL1 miss (bar) at reference cache point + reference knobs
    # -----------------------------------------------------------------------
    ref = norm[(norm["dl1_cfg"] == REF_DL1) & (norm["ul2_cfg"] == REF_UL2)].copy()
    ref = filter_ref_knobs_all_modes(ref)

    out2 = PLOTS_DIR / "2_mechanism_vs_miss_bars"
    barplot_mechanism(
        ref, "dl1_miss_norm",
        f"Mechanism vs DL1 miss (normalized) @ DL1={REF_DL1}, UL2={REF_UL2}\n(ref knobs: VC={REF_VC}, MC={REF_MC}, SB_DEPTH={REF_SB_DEPTH})",
        "DL1 miss rate (normalized)",
        out2 / "mechanism_vs_dl1_miss__ref.png",
        MODE_ORDER
    )

    # -----------------------------------------------------------------------
    # (3) VC entries vs VC hit rate — per benchmark @ reference caches
    #     victim: vary vc_entries
    #     victim_stream: vary vc_entries with SB fixed to REF_SB_DEPTH
    # -----------------------------------------------------------------------
    out3 = PLOTS_DIR / "3_vc_entries_vs_vc_hitrate"
    vc = norm[(norm["dl1_cfg"] == REF_DL1) & (norm["ul2_cfg"] == REF_UL2)].copy()
    vc = vc[vc["mode"].isin(["victim", "victim_stream"])].copy()
    # lock stream depth for victim_stream
    vc_vs = vc[vc["mode"] == "victim_stream"]
    vc_v  = vc[vc["mode"] == "victim"]
    vc_vs = vc_vs[vc_vs["sb_depth"] == REF_SB_DEPTH]
    vc = pd.concat([vc_v, vc_vs], ignore_index=True)

    for bench, g in vc.groupby("benchmark"):
        title = f"{bench}: VC entries vs VC hit rate\n@ DL1={REF_DL1}, UL2={REF_UL2} (SB depth fixed at {REF_SB_DEPTH} for victim_stream)"
        lineplot_by_mode(
            g, "vc_entries", "vc_hit_rate",
            title, "Victim cache entries", "VC hit rate",
            out3 / f"{bench}__vc_entries_vs_vc_hr__ref.png",
            ["victim", "victim_stream"]
        )

    # -----------------------------------------------------------------------
    # (4) MC entries vs MC hit rate — per benchmark @ reference caches
    #     miss: vary mc_entries
    #     miss_stream: vary mc_entries with SB fixed to REF_SB_DEPTH
    # -----------------------------------------------------------------------
    out4 = PLOTS_DIR / "4_mc_entries_vs_mc_hitrate"
    mc = norm[(norm["dl1_cfg"] == REF_DL1) & (norm["ul2_cfg"] == REF_UL2)].copy()
    mc = mc[mc["mode"].isin(["miss", "miss_stream"])].copy()
    mc_ms = mc[mc["mode"] == "miss_stream"]
    mc_m  = mc[mc["mode"] == "miss"]
    mc_ms = mc_ms[mc_ms["sb_depth"] == REF_SB_DEPTH]
    mc = pd.concat([mc_m, mc_ms], ignore_index=True)

    for bench, g in mc.groupby("benchmark"):
        title = f"{bench}: MC entries vs MC hit rate\n@ DL1={REF_DL1}, UL2={REF_UL2} (SB depth fixed at {REF_SB_DEPTH} for miss_stream)"
        lineplot_by_mode(
            g, "mc_entries", "mc_hit_rate",
            title, "Miss cache entries", "MC hit rate",
            out4 / f"{bench}__mc_entries_vs_mc_hr__ref.png",
            ["miss", "miss_stream"]
        )

    # -----------------------------------------------------------------------
    # (5) SB depth vs SB hit rate — per benchmark @ reference caches
    #     stream: vary sb_depth
    #     victim_stream: vary sb_depth with VC fixed to REF_VC
    #     miss_stream: vary sb_depth with MC fixed to REF_MC
    # -----------------------------------------------------------------------
    out5 = PLOTS_DIR / "5_sb_depth_vs_sb_hitrate"
    sb = norm[(norm["dl1_cfg"] == REF_DL1) & (norm["ul2_cfg"] == REF_UL2)].copy()
    sb = sb[sb["mode"].isin(["stream", "victim_stream", "miss_stream"])].copy()

    sb_s  = sb[sb["mode"] == "stream"]
    sb_vs = sb[sb["mode"] == "victim_stream"]
    sb_ms = sb[sb["mode"] == "miss_stream"]

    sb_vs = sb_vs[sb_vs["vc_entries"] == REF_VC]
    sb_ms = sb_ms[sb_ms["mc_entries"] == REF_MC]

    sb = pd.concat([sb_s, sb_vs, sb_ms], ignore_index=True)

    for bench, g in sb.groupby("benchmark"):
        title = f"{bench}: SB depth vs SB hit rate\n@ DL1={REF_DL1}, UL2={REF_UL2} (VC fixed={REF_VC} for victim_stream, MC fixed={REF_MC} for miss_stream)"
        lineplot_by_mode(
            g, "sb_depth", "sb_hit_rate",
            title, "Stream buffer depth (lines)", "SB hit rate",
            out5 / f"{bench}__sb_depth_vs_sb_hr__ref.png",
            ["stream", "victim_stream", "miss_stream"]
        )

    # -----------------------------------------------------------------------
    # (6) UL2 size vs UL2 miss — BASELINE ONLY (RAW + normalized)
    #     (per your request to avoid useless horizontal multi-mode lines)
    # -----------------------------------------------------------------------
    out6_raw  = PLOTS_DIR / "6_ul2_size_vs_ul2_miss" / "baseline_only_raw"
    out6_norm = PLOTS_DIR / "6_ul2_size_vs_ul2_miss" / "baseline_only_norm"

    base_only = norm[norm["mode"] == "baseline"].copy()
    # collapse duplicates if any
    base_only = (
        base_only.dropna(subset=["ul2_bytes"])
                 .groupby(["benchmark", "dl1_cfg", "ul2_bytes"], as_index=False)
                 .agg(ul2_miss_rate=("ul2_miss_rate", "mean"),
                      ul2_miss_norm=("ul2_miss_norm", "mean"))
    )

    for (bench, dl1_cfg), g in base_only.groupby(["benchmark", "dl1_cfg"], dropna=False):
        if pd.isna(dl1_cfg):
            continue

        plt.figure()
        gg = g.sort_values("ul2_bytes")
        plt.plot(gg["ul2_bytes"].astype(float), gg["ul2_miss_rate"].astype(float), marker="o", label="baseline")
        plt.title(f"{bench}: UL2 miss rate vs UL2 size (RAW)\nDL1={dl1_cfg} (baseline only)")
        plt.xlabel("UL2 size (bytes)")
        plt.ylabel("UL2 miss rate")
        plt.grid(True, linestyle="--", linewidth=0.5)
        plt.legend()
        savefig(out6_raw / f"{bench}__ul2miss_raw_vs_ul2__dl1_{dl1_cfg.replace(':','-')}.png")

        plt.figure()
        plt.plot(gg["ul2_bytes"].astype(float), gg["ul2_miss_norm"].astype(float), marker="o", label="baseline")
        plt.title(f"{bench}: UL2 miss rate vs UL2 size (normalized)\nDL1={dl1_cfg} (baseline only)")
        plt.xlabel("UL2 size (bytes)")
        plt.ylabel("UL2 miss rate (normalized)")
        plt.grid(True, linestyle="--", linewidth=0.5)
        plt.legend()
        savefig(out6_norm / f"{bench}__ul2miss_norm_vs_ul2__dl1_{dl1_cfg.replace(':','-')}.png")

    # -----------------------------------------------------------------------
    # (7) UL2 demand vs DL1 size (normalized) — per benchmark, per UL2
    #     Keep multi-mode lines, but FIX knobs to references (same approach as #1)
    # -----------------------------------------------------------------------
    out7 = PLOTS_DIR / "7_ul2_demand_vs_dl1"
    for (bench, ul2_cfg), g in norm.groupby(["benchmark", "ul2_cfg"], dropna=False):
        if pd.isna(ul2_cfg):
            continue
        g2 = filter_ref_knobs_all_modes(g)

        title = f"{bench}: UL2 demand vs DL1 size (normalized to baseline)\nUL2={ul2_cfg}"
        lineplot_by_mode(
            g2, "dl1_bytes", "ul2_demand_norm",
            title, "DL1 size (bytes)", "UL2 demand (normalized)",
            out7 / f"{bench}__ul2demand_vs_dl1__ul2_{ul2_cfg.replace(':','-')}.png",
            MODE_ORDER
        )

    # -----------------------------------------------------------------------
    # (8) CPI vs mechanism (bar) at reference cache point + reference knobs
    # -----------------------------------------------------------------------
    out8 = PLOTS_DIR / "8_cpi_vs_mechanism_bars"
    barplot_mechanism(
        ref, "cpi_norm",
        f"Mechanism vs CPI (normalized) @ DL1={REF_DL1}, UL2={REF_UL2}\n(ref knobs: VC={REF_VC}, MC={REF_MC}, SB_DEPTH={REF_SB_DEPTH})",
        "CPI (normalized)",
        out8 / "mechanism_vs_cpi__ref.png",
        MODE_ORDER
    )

    print(f"Plots written under: {PLOTS_DIR}")

if __name__ == "__main__":
    main()
