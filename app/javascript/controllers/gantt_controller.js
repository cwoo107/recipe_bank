import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

// stimulus-chartjs already registers these on boot; registering again is a
// no-op, but we guard so this controller is self-sufficient if loaded alone.
if (!Chart.registry.controllers.get("bar")) {
    Chart.register(...registerables)
}

// Marks the time set aside for the week: a dashed line at that many hours,
// with anything past it shaded — so a plan that runs over shows how far.
const budgetLine = {
    id: "budgetLine",
    beforeDatasetsDraw(chart, _args, opts) {
        if (opts.hours == null) return
        const { ctx, chartArea } = chart
        const x = chart.scales.x.getPixelForValue(opts.hours)
        if (x >= chartArea.right) return
        ctx.save()
        ctx.fillStyle = opts.overflow
        ctx.fillRect(x, chartArea.top, chartArea.right - x, chartArea.bottom - chartArea.top)
        ctx.restore()
    },
    afterDatasetsDraw(chart, _args, opts) {
        if (opts.hours == null) return
        const { ctx, chartArea } = chart
        const x = chart.scales.x.getPixelForValue(opts.hours)
        ctx.save()
        ctx.beginPath()
        ctx.setLineDash([4, 4])
        ctx.lineWidth = 1.5
        ctx.strokeStyle = opts.color
        ctx.moveTo(x, chartArea.top)
        ctx.lineTo(x, chartArea.bottom)
        ctx.stroke()
        ctx.restore()
    }
}

// Whole hours across the top, spaced out so a big week doesn't crowd them.
function hourStep(max) {
    if (max <= 12) return 1
    if (max <= 30) return 2
    if (max <= 60) return 5
    return 10
}

export default class extends Controller {
    static targets = ["canvas"]
    static values  = { data: Object }

    connect() {
        this.render()
    }

    disconnect() {
        this.chart?.destroy()
        this.chart = null
    }

    // A morphing page refresh (e.g. after the time budget changes) swaps in
    // new data without reconnecting — redraw for it.
    dataValueChanged() {
        if (this.chart) this.render()
    }

    render() {
        const g = this.dataValue
        const dark = document.documentElement.classList.contains("dark")

        const grid = dark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.07)"
        const axis = dark ? "#9aa088" : "#5b6450"
        const line = dark ? "#e0a493" : "#c0705a"
        const overflow = dark ? "rgba(211,154,134,0.14)" : "rgba(211,154,134,0.16)"

        const rows = g.rows || []
        const max = Math.max(Math.ceil(g.max_hours || 0), 1)
        // A to-do with no estimate still gets a sliver, so it isn't missing.
        const sliver = max / 100

        const data = {
            labels: rows.map((r) => r.title),
            datasets: [
                {
                    data: rows.map((r) => [r.start, Math.max(r.end, r.start + sliver)]),
                    backgroundColor: rows.map((r) => r.color),
                    borderColor: rows.map((r) => (r.over ? line : r.color)),
                    borderWidth: rows.map((r) => (r.over ? 1.5 : 0)),
                    borderRadius: 4,
                    borderSkipped: false,
                    barThickness: 18,
                    maxBarThickness: 22
                }
            ]
        }

        const options = {
            indexAxis: "y",
            responsive: true,
            maintainAspectRatio: false,
            layout: { padding: { top: 4, right: 8, bottom: 0, left: 0 } },
            scales: {
                x: {
                    position: "top",
                    min: 0,
                    max: max,
                    offset: false,
                    grid: { color: grid, drawTicks: false },
                    border: { display: false },
                    ticks: {
                        stepSize: hourStep(max),
                        color: axis,
                        font: { size: 11, weight: "600" },
                        padding: 6,
                        callback: (value) => `${value}h`
                    }
                },
                y: {
                    grid: { display: false },
                    border: { display: false },
                    ticks: {
                        color: axis,
                        font: { size: 12 },
                        autoSkip: false,
                        crossAlign: "far",
                        callback: (value) => {
                            const label = this.chart?.data?.labels?.[value] ?? ""
                            return label.length > 28 ? `${label.slice(0, 27)}…` : label
                        }
                    }
                }
            },
            plugins: {
                legend: { display: false },
                budgetLine: { hours: g.budget_hours, color: line, overflow },
                tooltip: {
                    displayColors: true,
                    callbacks: {
                        title: (items) => rows[items[0].dataIndex]?.title ?? "",
                        label: (item) => {
                            const r = rows[item.dataIndex]
                            if (!r) return ""
                            return r.over ? [r.range_label, r.meta, "Past the time set aside"] : [r.range_label, r.meta]
                        }
                    }
                }
            }
        }

        this.chart?.destroy()
        this.chart = new Chart(this.canvasTarget, {
            type: "bar",
            data,
            options,
            plugins: [budgetLine]
        })
    }
}
