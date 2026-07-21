"""
Dashboard generator for the Cloud Avengers eval framework.

Reads the JSON report (and optionally evals-dataset.json) and generates a
self-contained dark-theme HTML dashboard using Chart.js from CDN.

Usage
-----
  python3 evals/dashboard.py [--report PATH] [--dataset PATH] [--output PATH] [--no-open]
"""
from __future__ import annotations

import argparse
import json
import math
import os
import webbrowser
from datetime import datetime, timezone


# ---------------------------------------------------------------------------
# Wilson CI (duplicated here so dashboard.py has no internal imports)
# ---------------------------------------------------------------------------

def _wilson_ci(passed: int, total: int) -> tuple[float, float]:
    if total == 0:
        return (0.0, 1.0)
    z = 1.96
    p = passed / total
    n = total
    centre = (p + z * z / (2 * n)) / (1 + z * z / n)
    half_width = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / (1 + z * z / n)
    return (max(0.0, centre - half_width), min(1.0, centre + half_width))


def _load_json(path: str, default: object) -> object:
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return default


# ---------------------------------------------------------------------------
# HTML generation helpers
# ---------------------------------------------------------------------------

def _safe(value: object) -> str:
    return str(value).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def _pct(value: float) -> str:
    return f"{value * 100:.1f}%"


def _generate_html(report: dict, dataset: dict) -> str:
    iterations = report.get("iterations", [])
    regressions = []
    for suite in dataset.get("suites", []):
        for item in suite.get("data", []):
            if "regression_id" in item:
                regressions.append(item)

    # Trend data
    trend_labels = [
        datetime.fromisoformat(it["timestamp"]).strftime("%m-%d %H:%M")
        for it in iterations
    ]
    trend_data = [round(it["pass_rate"] * 100, 1) for it in iterations]
    trend_ci_lower = [round(it["ci_lower"] * 100, 1) for it in iterations]
    trend_ci_upper = [round(it["ci_upper"] * 100, 1) for it in iterations]

    # Latest iteration summary
    if iterations:
        latest = iterations[-1]
        pass_rate_pct = _pct(latest["pass_rate"])
        ci_lower = _pct(latest["ci_lower"])
        ci_upper = _pct(latest["ci_upper"])
        total_passed = latest["total_passed"]
        total_items = latest["total_items"]
        converged = latest["converged"]
        suite_names = [s["name"] for s in latest["suites"]]
        suite_pass_rates = [round(s["pass_rate"] * 100, 1) for s in latest["suites"]]
    else:
        pass_rate_pct = "N/A"
        ci_lower = "N/A"
        ci_upper = "N/A"
        total_passed = 0
        total_items = 0
        converged = False
        suite_names = []
        suite_pass_rates = []

    converged_class = "converged" if converged else "not-converged"
    converged_label = "✅ CONVERGED" if converged else "❌ NOT CONVERGED"

    # Run history rows
    run_rows = ""
    for i, it in enumerate(reversed(iterations)):
        run_idx = len(iterations) - i
        ts = datetime.fromisoformat(it["timestamp"]).strftime("%Y-%m-%d %H:%M:%S UTC")
        status = "✅" if it["converged"] else "❌"
        failing_html = ""
        for suite in it.get("suites", []):
            for item in suite.get("items", []):
                if not item.get("actual_pass"):
                    checks = item.get("failing_checks", [])
                    check_lines = "".join(
                        f'<li><b>{_safe(c["check"])}</b>: {_safe(c["reason"])}</li>'
                        for c in checks
                    )
                    failing_html += (
                        f'<details><summary>{_safe(item["fixture"])}</summary>'
                        f'<ul>{check_lines}</ul></details>'
                    )
        run_rows += f"""
        <tr>
          <td>#{run_idx}</td>
          <td>{_safe(ts)}</td>
          <td>{status} {_pct(it['pass_rate'])}</td>
          <td>[{_pct(it['ci_lower'])}, {_pct(it['ci_upper'])}]</td>
          <td>{it['total_passed']}/{it['total_items']}</td>
          <td class="details-cell">{failing_html if failing_html else '—'}</td>
        </tr>"""

    # Regression catalog rows
    reg_rows = ""
    for reg in regressions:
        reg_rows += f"""
        <tr>
          <td>{_safe(reg.get('regression_id', ''))}</td>
          <td>{_safe(reg.get('regression_description', ''))}</td>
          <td>{_safe(reg.get('query', ''))}</td>
          <td>{'expect_pass=False' if not reg.get('expect_pass', True) else 'expect_pass=True'}</td>
        </tr>"""

    suite_names_json = json.dumps(suite_names)
    suite_pass_rates_json = json.dumps(suite_pass_rates)
    trend_labels_json = json.dumps(trend_labels)
    trend_data_json = json.dumps(trend_data)
    trend_ci_lower_json = json.dumps(trend_ci_lower)
    trend_ci_upper_json = json.dumps(trend_ci_upper)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Cloud Avengers — Eval Dashboard</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js@4/dist/chart.umd.min.js"></script>
  <style>
    :root {{
      --bg: #0d1117; --surface: #161b22; --border: #30363d;
      --accent: #58a6ff; --green: #3fb950; --red: #f85149;
      --text: #c9d1d9; --text-muted: #8b949e;
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{ background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", monospace; padding: 24px; }}
    h1 {{ font-size: 1.6rem; margin-bottom: 4px; }}
    .subtitle {{ color: var(--text-muted); font-size: 0.85rem; margin-bottom: 24px; }}
    .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 16px; margin-bottom: 24px; }}
    .card {{ background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 20px; }}
    .card h2 {{ font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.08em; color: var(--text-muted); margin-bottom: 8px; }}
    .big-number {{ font-size: 2.4rem; font-weight: 700; }}
    .converged {{ color: var(--green); }}
    .not-converged {{ color: var(--red); }}
    .ci {{ font-size: 0.8rem; color: var(--text-muted); margin-top: 4px; }}
    .chart-wrap {{ background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 20px; margin-bottom: 24px; }}
    .chart-wrap h2 {{ font-size: 0.85rem; font-weight: 600; margin-bottom: 12px; }}
    canvas {{ max-height: 260px; }}
    table {{ width: 100%; border-collapse: collapse; font-size: 0.82rem; }}
    thead tr {{ background: var(--surface); }}
    th, td {{ padding: 10px 12px; border-bottom: 1px solid var(--border); text-align: left; vertical-align: top; }}
    th {{ color: var(--text-muted); font-weight: 600; }}
    .details-cell details {{ margin-bottom: 4px; }}
    .details-cell summary {{ cursor: pointer; color: var(--accent); }}
    .details-cell ul {{ padding-left: 16px; margin-top: 4px; }}
    section {{ background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 20px; margin-bottom: 24px; }}
    section h2 {{ font-size: 0.85rem; font-weight: 600; margin-bottom: 12px; }}
  </style>
</head>
<body>
  <h1>☁️ Cloud Avengers — Eval Dashboard</h1>
  <div class="subtitle">Migration pipeline evaluation results · Generated {datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")}</div>

  <div class="grid">
    <div class="card">
      <h2>Overall pass rate</h2>
      <div class="big-number {converged_class}">{pass_rate_pct}</div>
      <div class="ci">Wilson 95% CI: [{ci_lower}, {ci_upper}]</div>
    </div>
    <div class="card">
      <h2>Items</h2>
      <div class="big-number">{total_passed}<span style="font-size:1.2rem;color:var(--text-muted)">/{total_items}</span></div>
      <div class="ci">passed / total</div>
    </div>
    <div class="card">
      <h2>Status</h2>
      <div class="big-number {converged_class}" style="font-size:1.4rem">{converged_label}</div>
      <div class="ci">threshold = 90%</div>
    </div>
    <div class="card">
      <h2>Runs recorded</h2>
      <div class="big-number">{len(iterations)}</div>
    </div>
  </div>

  <div class="chart-wrap">
    <h2>Pass rate trend</h2>
    <canvas id="trendChart"></canvas>
  </div>

  <div class="chart-wrap">
    <h2>Suite breakdown (latest run)</h2>
    <canvas id="suiteChart"></canvas>
  </div>

  <section>
    <h2>Run history</h2>
    <table>
      <thead><tr><th>#</th><th>Timestamp</th><th>Result</th><th>Wilson CI</th><th>Passed/Total</th><th>Failing items</th></tr></thead>
      <tbody>{run_rows if run_rows else '<tr><td colspan="6" style="color:var(--text-muted)">No runs recorded yet.</td></tr>'}</tbody>
    </table>
  </section>

  <section>
    <h2>Regression catalog</h2>
    <table>
      <thead><tr><th>Regression ID</th><th>Description</th><th>Query</th><th>Type</th></tr></thead>
      <tbody>{reg_rows if reg_rows else '<tr><td colspan="4" style="color:var(--text-muted)">No regressions catalogued yet.</td></tr>'}</tbody>
    </table>
  </section>

  <script>
    const trendLabels = {trend_labels_json};
    const trendData = {trend_data_json};
    const trendCiLower = {trend_ci_lower_json};
    const trendCiUpper = {trend_ci_upper_json};
    const suiteNames = {suite_names_json};
    const suiteRates = {suite_pass_rates_json};

    if (trendLabels.length > 0) {{
      new Chart(document.getElementById('trendChart'), {{
        type: 'line',
        data: {{
          labels: trendLabels,
          datasets: [
            {{
              label: 'Pass rate %',
              data: trendData,
              borderColor: '#58a6ff',
              backgroundColor: 'rgba(88,166,255,0.12)',
              fill: true,
              tension: 0.3,
              pointRadius: 4,
            }},
            {{
              label: 'CI lower',
              data: trendCiLower,
              borderColor: 'rgba(88,166,255,0.3)',
              borderDash: [4,3],
              pointRadius: 0,
              fill: false,
            }},
            {{
              label: 'CI upper',
              data: trendCiUpper,
              borderColor: 'rgba(88,166,255,0.3)',
              borderDash: [4,3],
              pointRadius: 0,
              fill: false,
            }},
          ]
        }},
        options: {{
          plugins: {{ legend: {{ labels: {{ color: '#c9d1d9' }} }} }},
          scales: {{
            x: {{ ticks: {{ color: '#8b949e' }}, grid: {{ color: '#21262d' }} }},
            y: {{ min: 0, max: 100, ticks: {{ color: '#8b949e', callback: v => v + '%' }}, grid: {{ color: '#21262d' }} }}
          }}
        }}
      }});
    }}

    if (suiteNames.length > 0) {{
      new Chart(document.getElementById('suiteChart'), {{
        type: 'bar',
        data: {{
          labels: suiteNames,
          datasets: [{{
            label: 'Pass rate %',
            data: suiteRates,
            backgroundColor: suiteRates.map(v => v >= 90 ? 'rgba(63,185,80,0.7)' : 'rgba(248,81,73,0.7)'),
            borderRadius: 4,
          }}]
        }},
        options: {{
          plugins: {{ legend: {{ display: false }} }},
          scales: {{
            x: {{ ticks: {{ color: '#8b949e' }}, grid: {{ color: '#21262d' }} }},
            y: {{ min: 0, max: 100, ticks: {{ color: '#8b949e', callback: v => v + '%' }}, grid: {{ color: '#21262d' }} }}
          }}
        }}
      }});
    }}
  </script>
</body>
</html>
"""


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Generate eval dashboard HTML")
    parser.add_argument("--report", default="evals/evals-report.json", metavar="PATH")
    parser.add_argument("--dataset", default="evals/evals-dataset.json", metavar="PATH")
    parser.add_argument("--output", default="evals/dashboard.html", metavar="PATH")
    parser.add_argument("--no-open", action="store_true", help="Do not open in browser.")
    args = parser.parse_args(argv)

    report = _load_json(args.report, {"iterations": []})
    dataset = _load_json(args.dataset, {"suites": []})

    html = _generate_html(report, dataset)  # type: ignore[arg-type]
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Dashboard written to: {args.output}")

    if not args.no_open:
        webbrowser.open(f"file://{os.path.abspath(args.output)}")


if __name__ == "__main__":
    main()
