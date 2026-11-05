// Dashboard charts. Data is rendered into #chart-data by the server.
(function () {
  const data = JSON.parse(document.getElementById("chart-data").textContent);
  const css = getComputedStyle(document.documentElement);
  const color = (name) => css.getPropertyValue(name).trim();
  const money = (v) => v.toLocaleString(undefined, { maximumFractionDigits: 0 });
  const compact = (v) => v.toLocaleString(undefined, { notation: "compact", maximumFractionDigits: 1 });

  Chart.defaults.font.family = getComputedStyle(document.body).fontFamily;
  Chart.defaults.color = color("--ink-muted");
  Chart.defaults.plugins.tooltip.padding = 10;

  const grid = { color: "rgba(0, 0, 0, 0.06)" };
  const bar = { borderRadius: 4, borderSkipped: "start", maxBarThickness: 28 };

  new Chart(document.getElementById("chart-monthly"), {
    type: "bar",
    data: {
      labels: data.monthly.labels,
      datasets: [
        { label: "Money in", data: data.monthly.money_in, backgroundColor: color("--series-in"), ...bar },
        { label: "Money out", data: data.monthly.money_out, backgroundColor: color("--series-out"), ...bar },
      ],
    },
    options: {
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: { position: "top", align: "start", labels: { boxWidth: 12, boxHeight: 12 } },
        tooltip: { callbacks: { label: (c) => `${c.dataset.label}: ${money(c.parsed.y)}` } },
      },
      scales: {
        x: { grid: { display: false } },
        y: { grid, border: { display: false }, ticks: { callback: compact } },
      },
    },
  });

  const horizontal = (id, labels, values, label, format) =>
    new Chart(document.getElementById(id), {
      type: "bar",
      data: { labels, datasets: [{ label, data: values, backgroundColor: color("--series-in"), ...bar }] },
      options: {
        indexAxis: "y",
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: { callbacks: { label: (c) => `${label}: ${format(c.parsed.x)}` } },
        },
        scales: {
          x: { grid, border: { display: false }, ticks: { callback: compact } },
          y: { grid: { display: false } },
        },
      },
    });

  horizontal("chart-branches", data.branches.labels, data.branches.values, "Deposits held", money);
  horizontal("chart-channels", data.channels.labels, data.channels.values, "Transactions",
             (v) => v.toLocaleString());
})();
