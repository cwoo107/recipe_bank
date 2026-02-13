// stimulus-chartjs@5.0.1 downloaded from https://ga.jspm.io/npm:stimulus-chartjs@5.0.1/dist/stimulus-chartjs.mjs

import{Controller as a}from"@hotwired/stimulus";import s from"chart.js/auto";class t extends a{connect(){const a=this.hasCanvasTarget?this.canvasTarget:this.element;this.chart=new s(a.getContext("2d"),{type:this.typeValue,data:this.chartData,options:this.chartOptions})}disconnect(){this.chart.destroy(),this.chart=void 0}get chartData(){return this.hasDataValue||console.warn("[stimulus-chartjs] You need to pass data as JSON to see the chart."),this.dataValue}get chartOptions(){return{...this.defaultOptions,...this.optionsValue}}get defaultOptions(){return{}}}t.targets=["canvas"];t.values={type:{type:String,default:"line"},data:Object,options:Object};export{t as default};

