module ApplicationHelper
  def render_step_item(label, status, job)
    is_current = job.status == status.to_s
    is_complete = RecipeImportJob.statuses[job.status] > RecipeImportJob.statuses[status]

    icon = if is_complete
             tag.svg(class: "w-5 h-5 text-green-500", fill: "currentColor", viewBox: "0 0 20 20") do
               tag.path(fill_rule: "evenodd", d: "M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z", clip_rule: "evenodd")
             end
           elsif is_current
             tag.svg(class: "animate-spin h-5 w-5 text-blue-600", xmlns: "http://www.w3.org/2000/svg", fill: "none", viewBox: "0 0 24 24") do
               tag.circle(class: "opacity-25", cx: "12", cy: "12", r: "10", stroke: "currentColor", stroke_width: "4") +
                 tag.path(class: "opacity-75", fill: "currentColor", d: "M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z")
             end
           else
             tag.svg(class: "w-5 h-5 text-gray-300", fill: "currentColor", viewBox: "0 0 20 20") do
               tag.path(fill_rule: "evenodd", d: "M10 18a8 8 0 100-16 8 8 0 000 16zm0-2a6 6 0 100-12 6 6 0 000 12z", clip_rule: "evenodd")
             end
           end

    tag.div(class: "flex items-center space-x-3") do
      icon + tag.span(label, class: "text-sm #{is_complete ? 'text-gray-900' : 'text-gray-500'}")
    end
  end
end
