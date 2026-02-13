# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "@hotwired--stimulus.js" # @3.2.2
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "trix"
pin "@rails/actiontext", to: "actiontext.esm.js"
pin "sortablejs" # @1.15.6

# Chart.js setup
pin "chart.js", to: "https://cdn.jsdelivr.net/npm/chart.js@4.4.1/+esm"
pin "stimulus-chartjs", to: "https://cdn.jsdelivr.net/npm/stimulus-chartjs@5.0.0/+esm"
pin "@stimulus-components/dialog", to: "@stimulus-components--dialog.js" # @1.0.1
