import { Application } from "@hotwired/stimulus"
import Chartjs from "stimulus-chartjs"
import Dialog from "@stimulus-components/dialog"

const application = Application.start()
application.register("chartjs", Chartjs)
application.register('dialog', Dialog)

// Configure Stimulus development experience
application.debug = false
window.Stimulus   = application

export { application }