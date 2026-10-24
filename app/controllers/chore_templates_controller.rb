class ChoreTemplatesController < ApplicationController
  # Limited members can browse the library but not add to the chart (see ApplicationController).
  before_action :require_household_admin!, only: :add

  def index
    @templates = ChoreTemplate.all
  end

  # POST /chore-templates/:id/add — copies the template's category and
  # chores onto the household's chart (see ChoreTemplate#add_to!).
  def add
    template = ChoreTemplate.find(params[:id])
    missing  = template.missing_chores_for(current_household)

    if missing.empty?
      return redirect_to chore_templates_path, notice: "Your chart already has everything in \"#{template.name}\".", status: :see_other
    end

    template.add_to!(current_household)
    redirect_to weekly_chores_path(view: "table"),
                notice: "Added #{helpers.pluralize(missing.size, "chore")} from \"#{template.name}\" to your chore chart.",
                status: :see_other
  end
end
