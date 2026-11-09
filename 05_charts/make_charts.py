#!/usr/bin/env python3
"""Build 3 README charts straight from the SQL query files (psql --csv), so the charts can never drift
from the queries. Colours: validated categorical slots 1-2 (blue, orange) + single-hue sequential blue."""
import io, pathlib, subprocess
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap
import numpy as np
import pandas as pd

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "docs"; OUT.mkdir(exist_ok=True)
SURFACE, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e6e5e1"
BLUE, ORANGE = "#2a78d6", "#eb6834"
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10, "axes.edgecolor": GRID, "axes.labelcolor": INK2,
                     "xtick.color": INK2, "ytick.color": INK2, "figure.facecolor": SURFACE, "axes.facecolor": SURFACE})


def q(name):
    r = subprocess.run(["psql", "-X", "-q", "--csv", "-v", "ON_ERROR_STOP=1", "-f", str(ROOT / "03_analysis" / name)],
                       capture_output=True, text=True)
    if r.returncode: raise SystemExit(r.stderr)
    return pd.read_csv(io.StringIO(r.stdout))


def clean(ax):
    for s in ("top", "right", "left"): ax.spines[s].set_visible(False)
    ax.tick_params(length=0); ax.yaxis.grid(True, color=GRID, lw=0.8); ax.set_axisbelow(True)


# 1 -- cohort retention heatmap (sequential, one hue, light -> dark)
d = q("q02_cohort_retention.sql").set_index("cohort_month")
m = d[[f"m{i}_pct" for i in range(1, 7)]]
cmap = LinearSegmentedColormap.from_list("seq", ["#e8f0fb", BLUE, "#0f3d7a"])
fig, ax = plt.subplots(figsize=(8.2, 6.4))
ax.imshow(np.ma.masked_invalid(m.values), cmap=cmap, aspect="auto", vmin=0, vmax=8)
for i in range(m.shape[0]):
    for j in range(m.shape[1]):
        v = m.values[i, j]
        if not np.isnan(v):
            ax.text(j, i, f"{v:.1f}", ha="center", va="center", fontsize=8, color="white" if v > 4.3 else INK)
ax.set_xticks(range(6), [f"Month +{i}" for i in range(1, 7)])
ax.set_yticks(range(len(m)), [f"{c[:7]}  (n={n:,})" for c, n in zip(m.index, d.cohort_size)], fontsize=8)
ax.xaxis.tick_top(); ax.tick_params(length=0)
for s in ax.spines.values(): s.set_visible(False)
ax.set_title("Share of each first-purchase cohort that orders again in month +n (%)\nBlank = month not yet observed",
             loc="left", color=INK, fontsize=11, pad=34)
fig.tight_layout(); fig.savefig(OUT / "chart_cohort_retention.png", dpi=160); plt.close(fig)

# 2 -- repeat rate: late vs on-time first delivery, and by first-order review score
a = q("q06_late_delivery_vs_repeat.sql").set_index("first_delivery")
b = q("q06b_review_score_vs_repeat.sql").set_index("first_order_review")
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9.2, 4.2), gridspec_kw={"width_ratios": [2, 3]})
for ax, df, colors, title in ((ax1, a, [BLUE if i == "On time" else ORANGE for i in a.index], "By first delivery"),
                              (ax2, b, [BLUE] * len(b), "By review score of first order")):
    labels = [f"{i}\n(n={n:,})" for i, n in zip(df.index, df.customers)]
    bars = ax.bar(labels, df.repeat_rate_pct, color=colors, width=0.5)
    for r, v in zip(bars, df.repeat_rate_pct):
        ax.text(r.get_x() + r.get_width() / 2, v + 0.5, f"{v:.1f}%", ha="center", color=INK, fontsize=10, fontweight="bold")
    ax.set_ylim(0, max(df.repeat_rate_pct.max() * 1.25, 10)); ax.set_title(title, loc="left", color=INK, fontsize=10)
    clean(ax)
ax1.set_ylabel("Ordered again within 180 days (%)")
fig.suptitle("Customers with a bad first experience come back far less (synthetic data)", x=0.01, ha="left", color=INK, fontsize=11)
fig.tight_layout(rect=(0, 0.02, 1, 0.95)); fig.savefig(OUT / "chart_repeat_rate.png", dpi=160); plt.close(fig)

# 3 -- revenue concentration by customer decile (single axis; cumulative shown as labels, not a 2nd axis)
c = q("q08_revenue_concentration.sql")
fig, ax = plt.subplots(figsize=(8.2, 4.2))
bars = ax.bar(c.customer_decile.astype(str), c.pct_of_revenue, color=BLUE, width=0.62)
for r, v in zip(bars, c.pct_of_revenue):
    ax.text(r.get_x() + r.get_width() / 2, v + 0.5, f"{v:.1f}", ha="center", color=INK, fontsize=9)
top20 = c.loc[c.customer_decile <= 2, "pct_of_revenue"].sum()
ax.text(0.99, 0.93, f"Top 20% of customers\n= {top20:.0f}% of revenue", transform=ax.transAxes, ha="right", va="top",
        color=INK, fontsize=11, fontweight="bold")
ax.set_xlabel("Customer decile (1 = highest spenders)"); ax.set_ylabel("Share of total revenue (%)")
ax.set_title("Revenue concentration by customer decile", loc="left", color=INK, fontsize=11); clean(ax)
fig.tight_layout(); fig.savefig(OUT / "chart_revenue_concentration.png", dpi=160); plt.close(fig)
print("      wrote docs/chart_*.png")
