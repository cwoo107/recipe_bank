import { Application } from "@hotwired/stimulus"
import Chartjs from "stimulus-chartjs"

const application = Application.start()
application.register("chartjs", Chartjs)
// "dialog" is controllers/dialog_controller.js, which builds on
// @stimulus-components/dialog.

// Configure Stimulus development experience
application.debug = false
window.Stimulus   = application

export { application }