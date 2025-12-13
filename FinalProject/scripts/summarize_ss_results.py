#!/usr/bin/env python3
import csv
from pathlib import Path

RESULTS_ROOT = Path("results/ss")
SUMMARY_PATH = RESULTS_ROOT / "ss_summary_all.csv"


def safe_float(val):
    """Convert to float, returning None on empty or invalid."""
    if val is None:
        return None
    s = str(val).strip()
    if s == "":
        return None
    try:
        return float(s)
    except ValueError:
        return None


def main():
    rows_out = []

    # Walk all CSVs under results/ss
    for csv_path in RESULTS_ROOT.rglob("ss_*.csv"):
        if csv_path.resolve() == SUMMARY_PATH.resolve():
            continue
        config = csv_path.relative_to(RESULTS_ROOT).parts[0]


        with csv_path.open(newline="") as f:
            reader = csv.DictReader(f)

            for row in reader:
                bench = (row.get("benchmark") or "").strip()
                mode = (row.get("mode") or "").strip()

                # Skip header/empty lines
                if not bench or bench.lower() == "benchmark":
                    continue

                # Basic stats (strings are fine — we just pass them through)
                il1_miss = (row.get("il1_miss_rate") or "").strip()
                dl1_miss = (row.get("dl1_miss_rate") or "").strip()
                ul2_miss = (row.get("ul2_miss_rate") or "").strip()
                sim_num_insn = (row.get("sim_num_insn") or "").strip()
                sim_elapsed = (row.get("sim_elapsed_time") or "").strip()
                sim_cpi = (row.get("sim_CPI") or "").strip()

                # Victim cache stats
                vc_lookups = (row.get("vc_lookups") or "").strip()
                vc_hits = (row.get("vc_hits") or "").strip()

                # Miss cache stats
                mc_lookups = (row.get("mc_lookups") or "").strip()
                mc_hits = (row.get("mc_hits") or "").strip()

                # Stream buffer stats (new)
                sb_lookups = (row.get("sb_lookups") or "").strip()
                sb_hits = (row.get("sb_hits") or "").strip()
                sb_prefetches = (row.get("sb_prefetches") or "").strip()

                # UL2 access stats
                ul2_d = (row.get("ul2_d_accesses") or "").strip()
                ul2_i = (row.get("ul2_i_accesses") or "").strip()

                # ------------------------------------------------------------------
                # Derived metrics
                # ------------------------------------------------------------------

                # Victim cache hit rate
                vc_lookup_f = safe_float(vc_lookups)
                vc_hits_f = safe_float(vc_hits)
                vc_hr = ""
                if vc_lookup_f is not None and vc_lookup_f > 0 and vc_hits_f is not None:
                    vc_hr = f"{vc_hits_f / vc_lookup_f:.4f}"

                # Miss cache hit rate
                mc_lookup_f = safe_float(mc_lookups)
                mc_hits_f = safe_float(mc_hits)
                mc_hr = ""
                if mc_lookup_f is not None and mc_lookup_f > 0 and mc_hits_f is not None:
                    mc_hr = f"{mc_hits_f / mc_lookup_f:.4f}"

                # Stream buffer hit rate
                sb_lookup_f = safe_float(sb_lookups)
                sb_hits_f = safe_float(sb_hits)
                sb_hr = ""
                if sb_lookup_f is not None and sb_lookup_f > 0 and sb_hits_f is not None:
                    sb_hr = f"{sb_hits_f / sb_lookup_f:.4f}"

                # Total UL2 accesses
                ul2_d_f = safe_float(ul2_d) or 0.0
                ul2_i_f = safe_float(ul2_i) or 0.0
                ul2_total = ""
                if (ul2_d and ul2_d.strip() != "") or (ul2_i and ul2_i.strip() != ""):
                    ul2_total = str(int(ul2_d_f + ul2_i_f))

                rows_out.append({
                    "config": config,
                    "benchmark": bench,
                    "mode": mode,
                    "il1_miss_rate": il1_miss,
                    "dl1_miss_rate": dl1_miss,
                    "ul2_miss_rate": ul2_miss,
                    "sim_num_insn": sim_num_insn,
                    "sim_elapsed_time": sim_elapsed,
                    "sim_CPI": sim_cpi,
                    "vc_lookups": vc_lookups,
                    "vc_hits": vc_hits,
                    "vc_hit_rate": vc_hr,
                    "mc_lookups": mc_lookups,
                    "mc_hits": mc_hits,
                    "mc_hit_rate": mc_hr,
                    "sb_lookups": sb_lookups,
                    "sb_hits": sb_hits,
                    "sb_hit_rate": sb_hr,
                    "sb_prefetches": sb_prefetches,
                    "ul2_d_accesses": ul2_d,
                    "ul2_i_accesses": ul2_i,
                    "ul2_total_accesses": ul2_total,
                    "source_csv": str(csv_path),
                })

    # ----------------------------------------------------------------------
    # Write the combined CSV
    # ----------------------------------------------------------------------
    SUMMARY_PATH.parent.mkdir(parents=True, exist_ok=True)

    fieldnames = [
        "config",
        "benchmark",
        "mode",
        "il1_miss_rate",
        "dl1_miss_rate",
        "ul2_miss_rate",
        "sim_num_insn",
        "sim_elapsed_time",
        "sim_CPI",
        "vc_lookups",
        "vc_hits",
        "vc_hit_rate",
        "mc_lookups",
        "mc_hits",
        "mc_hit_rate",
        "sb_lookups",
        "sb_hits",
        "sb_hit_rate",
        "sb_prefetches",
        "ul2_d_accesses",
        "ul2_i_accesses",
        "ul2_total_accesses",
        "source_csv",
    ]

    with SUMMARY_PATH.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in rows_out:
            writer.writerow(r)

    print(f"Wrote summary of {len(rows_out)} rows to {SUMMARY_PATH}")


if __name__ == "__main__":
    main()
