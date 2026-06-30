import { Controller } from "@hotwired/stimulus"
import { Chart, registerables } from "chart.js"

// stimulus-chartjs already registers these on boot; registering again is a
// no-op, but we guard so this controller is self-sufficient if loaded alone.
if (!Chart.registry.controllers.get("bar")) {
    Chart.register(...registerables)
}

// Draws a dashed vertical "today" marker across the plot area.
const todayLine = {
    id: "todayLine",
    afterDatasetsDraw(chart, _args, opts) {
        if (opts.offset == null || opts.offset < 0 || opts.offset > 7) return
        const x = chart.scales.x.getPixelForValue(opts.offset)
        const { ctx, chartArea } = chart
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

    render() {
        const g = this.dataValue
        const dark = document.documentElement.classList.contains("dark")

        const grid = dark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.07)"
        const axis = dark ? "#9aa088" : "#5b6450"
        const today = dark ? "#a3b58c" : "#5f734c"

        const rows = g.rows || []

        const data = {
            labels: rows.map((r) => r.title),
            datasets: [
                {
                    data: rows.map((r) => [r.start, r.end]),
                    backgroundColor: rows.map((r) => r.color),
                    borderColor: rows.map((r) => r.color),
                    borderWidth: 0,
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
                    max: 7,
                    offset: false,
                    grid: { color: grid, drawTicks: false },
                    border: { display: false },
                    ticks: {
                        stepSize: 1,
                        color: axis,
                        font: { size: 11, weight: "600" },
                        padding: 6,
                        callback: (value) => {
                            const day = g.days?.[value]
                            return day ? `${day.label} ${day.date}` : ""
                        }
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
                todayLine: { offset: g.today_offset, color: today },
                tooltip: {
                    displayColors: true,
                    callbacks: {
                        title: (items) => rows[items[0].dataIndex]?.title ?? "",
                        label: (item) => {
                            const r = rows[item.dataIndex]
                            return r ? [r.range_label, r.meta] : ""
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
            plugins: [todayLine]
        })
    }
}