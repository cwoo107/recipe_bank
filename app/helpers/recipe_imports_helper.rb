# app/helpers/recipe_imports_helper.rb
module RecipeImportsHelper
  def render_import_step(job, step_status, title, description, last: false)
    current_status = job.status.to_sym

    # Get the order of statuses
    status_order = [:pending, :fetching_html, :parsing_recipe, :matching_ingredients,
                    :resolving_with_ai, :creating_recipe, :completed, :failed]

    current_index = status_order.index(current_status) || 0
    step_index = status_order.index(step_status) || 0

    # Special handling: if job is completed, all steps are completed
    is_completed = job.completed? || current_index > step_index
    is_current = current_status == step_status && !job.completed? && !job.failed?
    is_pending = current_index < step_index && !job.completed? && !job.failed?
    is_failed = job.failed? && current_status == step_status

    # Determine icon and color
    icon_html, icon_color = if is_failed
                              [failed_icon_svg, 'bg-red-600 dark:bg-red-700']
                            elsif is_completed
                              [completed_icon_svg, 'bg-[#5f734c] dark:bg-[#7a8f62]']
                            elsif is_current
                              [loading_icon_svg, 'bg-[#5f734c] dark:bg-[#7a8f62]']
                            else
                              [pending_icon_svg, 'bg-gray-300 dark:bg-gray-700']
                            end

    content_tag(:li) do
      content_tag(:div, class: "relative pb-8") do
        connector = unless last
                      content_tag(:span, '',
                                  class: "absolute top-4 left-4 -ml-px h-full w-0.5 bg-gray-200 dark:bg-gray-700",
                                  aria: { hidden: true }
                      )
                    end

        step_content = content_tag(:div, class: "relative flex space-x-3") do
          icon_wrapper = content_tag(:div) do
            content_tag(:span,
                        icon_html.html_safe,
                        class: "flex size-8 items-center justify-center rounded-full #{icon_color} ring-8 ring-white dark:ring-gray-900"
            )
          end

          text_content = content_tag(:div, class: "flex min-w-0 flex-1 justify-between space-x-4 pt-1.5") do
            content_tag(:div) do
              title_html = content_tag(:p, class: "text-sm font-medium text-gray-900 dark:text-white") do
                title
              end

              desc_html = if is_completed || is_current
                            content_tag(:p, description, class: "mt-0.5 text-sm text-gray-500 dark:text-gray-400")
                          end

              title_html + (desc_html || ''.html_safe)
            end
          end

          icon_wrapper + text_content
        end

        (connector || ''.html_safe) + step_content
      end
    end
  end

  private

  def completed_icon_svg
    <<~SVG
      <svg viewBox="0 0 20 20" fill="currentColor" class="size-5 text-white">
        <path d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z" clip-rule="evenodd" fill-rule="evenodd" />
      </svg>
    SVG
  end

  def loading_icon_svg
    <<~SVG
      <svg class="animate-spin size-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
        <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
        <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
    SVG
  end

  def pending_icon_svg
    <<~SVG
      <svg viewBox="0 0 20 20" fill="currentColor" class="size-5 text-gray-400 dark:text-gray-500">
        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm.75-13a.75.75 0 00-1.5 0v5c0 .414.336.75.75.75h4a.75.75 0 000-1.5h-3.25V5z" clip-rule="evenodd" />
      </svg>
    SVG
  end

  def failed_icon_svg
    <<~SVG
      <svg viewBox="0 0 20 20" fill="currentColor" class="size-5 text-white">
        <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z" clip-rule="evenodd" />
      </svg>
    SVG
  end
end