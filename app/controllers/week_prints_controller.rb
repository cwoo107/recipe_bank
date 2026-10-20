# "Print this week's plan": pick a week and which screens to include, then get
# a PDF (WeekPlanPdf) streamed straight back — generated in memory, never
# saved. Read-only, so every household member can print.
class WeekPrintsController < ApplicationController
  def new
    @week_start = week_start_from_params
    # Pages for steps the household leaves out of the planner start unticked
    # (Household#default_print_sections); they can still be ticked here.
    @sections   = selected_sections.presence || current_household.default_print_sections
    @layouts    = WeekPlanPdf.layouts_from(params[:layouts] || {})
  end

  def show
    sections = selected_sections
    return redirect_to(new_week_print_path(week: week_start_from_params), alert: "Pick at least one page to print.") if sections.empty?

    pdf = WeekPlanPdf.new(household: current_household, week_start: week_start_from_params, sections:, layouts: params[:layouts] || {})
    send_data pdf.render, filename: pdf.filename, type: "application/pdf", disposition: "inline"
  end

  private

  def week_start_from_params
    date = Date.iso8601(params[:week].to_s) rescue Date.current
    date.beginning_of_week
  end

  # The grocery and restock pages are now one shopping list — older links
  # (and the planner) may still name them.
  def selected_sections
    picked = Array(params[:sections]).map { |key| %w[groceries restock].include?(key) ? "shopping" : key }
    WeekPlanPdf::SECTIONS.keys & picked
  end
end
