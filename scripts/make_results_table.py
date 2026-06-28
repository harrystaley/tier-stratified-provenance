#!/usr/bin/env python3
"""Render a sweep SUMMARY_*.tsv as a LaTeX results table (IEEE OJCS).

Reads the capability-model sweep summary and emits a booktabs table pivoted as
poison-capability (rows) x gate-policy (columns), with the gate-off baseline as
a reference row. Tiers are noted as derived. Usage:

    python make_results_table.py evidence/sweep/SUMMARY_R1.tsv > tab_results.tex
"""
import csv
import sys

# Map the raw capability + policy to presentation labels.
CAP_ORDER = ["none", "untrusted", "root"]
CAP_LABEL = {
    "none":      (r"Commodity",  r"$T_N$", r"unsigned"),
    "untrusted": (r"Capable",    r"$T_W$", r"self-signed"),
    "root":      (r"State",      r"$T_S$", r"anchor-signed$^{\dagger}$"),
}
POLICY_KEYS = {
    "strict(W0,N0)":      "strict",
    "downweight(W.5,N0)": "downweight",
}


def load(path):
    rows = []
    with open(path) as f:
        for r in csv.DictReader(f, delimiter="\t"):
            rows.append(r)
    return rows


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: make_results_table.py SUMMARY_*.tsv")
    rows = load(sys.argv[1])

    baseline = next((r for r in rows if r["label"] == "baseline"), None)
    # index: cell[(capability, policy)] = asrr
    cell = {}
    regime = None
    for r in rows:
        if r["label"] == "baseline":
            continue
        cap = r["poison_cap"]
        pol = POLICY_KEYS.get(r["policy"].strip())
        if pol:
            cell[(cap, pol)] = r["ASR-r(%)"]
        regime = r["legit_regime"]

    def fmt(v):
        if v is None:
            return r"\textemdash"
        f = float(v)
        return f"{f:.0f}"

    L = []
    L.append(r"\begin{table}[t]")
    L.append(r"\centering")
    L.append(r"\caption{Retrieval attack success rate (ASR-r, \%) on EHRAgent under "
             r"the attestation gate, by attacker signing capability and gate policy. "
             r"Attestation tiers are \emph{derived} by validating a real ed25519 "
             r"signature carried with each entry (not assigned). Deployment regime "
             r"R1 (legit adoption "
             r"$\langle T_N,T_W,T_S\rangle=\langle0.80,0.15,0.05\rangle$). "
             r"Lower is better; the gate-off baseline reproduces the undefended attack.}")
    L.append(r"\label{tab:results}")
    L.append(r"\begin{tabular}{llcc}")
    L.append(r"\toprule")
    L.append(r"Attacker & Poison tier & \multicolumn{2}{c}{ASR-r (\%) by gate policy} \\")
    L.append(r"\cmidrule(lr){3-4}")
    L.append(r"capability & (derived) & Strict & Down-weight \\")
    L.append(r" & & {\footnotesize $\langle T_S,T_W,T_N\rangle$} & {\footnotesize $\langle T_S,T_W,T_N\rangle$} \\")
    L.append(r" & & {\footnotesize $=\langle1,0,0\rangle$} & {\footnotesize $=\langle1,0.5,0\rangle$} \\")
    L.append(r"\midrule")
    if baseline:
        L.append(rf"Baseline (gate off) & \textemdash & "
                 rf"\multicolumn{{2}}{{c}}{{{fmt(baseline['ASR-r(%)'])}}} \\")
        L.append(r"\midrule")
    for cap in CAP_ORDER:
        name, tier, how = CAP_LABEL[cap]
        s = fmt(cell.get((cap, "strict")))
        d = fmt(cell.get((cap, "downweight")))
        L.append(rf"{name} & {tier} ({how}) & {s} & {d} \\")
    L.append(r"\bottomrule")
    L.append(r"\end{tabular}")
    L.append(r"\par\smallskip")
    L.append(r"{\footnotesize $^{\dagger}$Poison reaches $T_S$ only by signing with a "
             r"key that chains to the trust root, i.e.\ a \emph{compromised trust "
             r"anchor}; forged or tampered claims fail validation and remain "
             r"$T_W$/$T_N$.}")
    L.append(r"\end{table}")
    print("\n".join(L))


if __name__ == "__main__":
    main()