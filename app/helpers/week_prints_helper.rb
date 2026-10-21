module WeekPrintsHelper
  # The PDF of one page of the week's plan (WeekPlanPdf::SECTIONS), for a
  # page's own Print button — in that page's default orientation.
  def week_section_pdf_path(section, week)
    week_print_path(format: :pdf, week: week.beginning_of_week.iso8601, sections: [ section ])
  end
end
