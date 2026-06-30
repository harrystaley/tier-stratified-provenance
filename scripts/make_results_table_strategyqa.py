#!/usr/bin/env python3
"""Render the StrategyQA structural sweep SUMMARY_*.tsv as a LaTeX results table
(IEEE OJCS), sibling to make_results_table.py (which handles the EHRAgent PKI sweep).

The StrategyQA sweep is structural (manifest membership), not PKI, and was run
under a single gate policy (down-weight), so the table is a one-column capability
ladder rather than the EHRAgent capability x policy grid. The distinguishing
point this table makes is structural UNFORGEABILITY: `forge` stays at $T_N$
(a fabricated handle is not in the manifest), where PKI self-signing would reach
$T_W$. Only `member` (corpus compromise) reaches $T_W$.

Reads columns: label / gate / struct_cap / tier_outcome / ASR-r(%) / n

Usage:
    python make_results_table_strategyqa.py evidence/sweep_strategyqa/SUMMARY_R1.tsv > tab_results_strategyqa.tex
"""
import csv
import sys

# Order of the structural capability ladder, with presentation labels.
CAP_ORDER = ["none", "forge", "member"]
CAP_LABEL = {
    "none":   (r"Commodity",  r"$T_N$", r"no handle"),
    "forge":  (r"Forging",    r"$T_N$", r"fabricated handle$^{\dagger}$"),
    "member": (r"Compromise", r"$T_W$", r"manifest member$^{\ddagger}$"),
}


def load(path):
    rows = []
    with open(path) as f:
        for r in csv.DictReader(f, delimiter="\t"):
            rows.append(r)
    return rows


def fmt(v):
    if v is None or v == "":
        return r"\textemdash"
    # one decimal place: StrategyQA's 56.8 is the reproduced baseline, and the fact
    # that `member` returns to *exactly* 56.8 is part of the result -- don't round it away.
    return f"{float(v):.1f}"


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: make_results_table_strategyqa.py SUMMARY_*.tsv")
    rows = load(sys.argv[1])

    baseline = next((r for r in rows if r["label"].strip() == "baseline"), None)
    # index by structural capability -> ASR-r (down-weight policy; the only policy run)
    cell = {}
    n_per_cell = None
    for r in rows:
        if r["label"].strip() == "baseline":
            continue
        cell[r["struct_cap"].strip()] = r["ASR-r(%)"]
        n_per_cell = r.get("n", n_per_cell)

    L = []
    L.append(r"\begin{table}[t]")
    L.append(r"\centering")
    L.append(r"\caption{Retrieval attack success rate (ASR-r, \%) on ReAct-StrategyQA "
             r"under the structural attestation gate, by attacker capability. "
             r"Attestation tiers are \emph{derived} by validating provenance-handle "
             r"membership in the genuine corpus manifest (9{,}251 Wikipedia handles), "
             r"not by signature. Gate policy is down-weight "
             r"$\langle T_S,T_W,T_N\rangle=\langle1,0.5,0\rangle$; legitimate "
             r"encyclopedic content is $T_W$ (manifest membership establishes "
             r"resolution/custody binding, not author identity). Lower is better; "
             r"the gate-off baseline reproduces the undefended attack.}")
    L.append(r"\label{tab:results-strategyqa}")
    L.append(r"\begin{tabular}{llc}")
    L.append(r"\toprule")
    L.append(r"Attacker & Poison tier & ASR-r (\%) \\")
    L.append(r"capability & (derived) & (down-weight) \\")
    L.append(r"\midrule")
    if baseline:
        L.append(rf"Baseline (gate off) & \textemdash & {fmt(baseline['ASR-r(%)'])} \\")
        L.append(r"\midrule")
    for cap in CAP_ORDER:
        name, tier, how = CAP_LABEL[cap]
        a = fmt(cell.get(cap))
        L.append(rf"{name} & {tier} ({how}) & {a} \\")
    L.append(r"\bottomrule")
    L.append(r"\end{tabular}")
    L.append(r"\par\smallskip")
    L.append(r"{\footnotesize $^{\dagger}$A forged handle is \emph{not} in the manifest, "
             r"so it fails membership and remains $T_N$: structural attestation has no "
             r"self-signing analogue, and forging cannot reach $T_W$ (contrast PKI, where "
             r"a self-signature reaches $T_W$). "
             r"$^{\ddagger}$Poison reaches $T_W$ only when the corpus itself is compromised "
             r"so the poison handle is a genuine manifest member, i.e.\ a compromised "
             r"structural trust root.}")
    L.append(r"\end{table}")
    print("\n".join(L))


if __name__ == "__main__":
    main()
