module CalendarSourcesHelper
  def provider_description(provider)
    {
      "google"  => "Sync via OAuth",
      "apple"   => "iCal export URL",
      "outlook" => "Microsoft 365 / Outlook",
      "ical"    => "Any public .ics feed"
    }[provider]
  end

  # Returns a small inline SVG icon for each provider
  def provider_icon_svg(provider)
    case provider
    when "google"
      tag.svg(xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", class: "size-6 shrink-0") do
        tag.path(d: "M21.35 11.1H12v2.9h5.35c-.23 1.23-.93 2.27-1.97 2.97v2.47h3.18c1.86-1.71 2.93-4.23 2.93-7.17 0-.68-.06-1.34-.17-1.97zM12 22c2.7 0 4.96-.9 6.61-2.43l-3.18-2.47C14.46 17.73 13.29 18.1 12 18.1c-2.6 0-4.8-1.76-5.58-4.12H3.14v2.55C4.78 19.96 8.15 22 12 22zM6.42 14.01a5.9 5.9 0 0 1 0-4.02V7.44H3.14A9.99 9.99 0 0 0 2 12c0 1.62.39 3.15 1.07 4.5l3.35-2.49zM12 5.9c1.47 0 2.79.5 3.82 1.5l2.86-2.86C16.96 2.9 14.7 2 12 2 8.15 2 4.78 4.04 3.14 7.44l3.28 2.55C7.2 7.66 9.4 5.9 12 5.9z", fill: "currentColor")
      end
    when "apple"
      tag.svg(xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", class: "size-6 shrink-0") do
        tag.path(d: "M16.52 3.52a4.63 4.63 0 0 1-1.04 3.45 3.87 3.87 0 0 1-3.26 1.56 4.02 4.02 0 0 1 .94-3.33 4.42 4.42 0 0 1 3.36-1.68zm4.23 15.3c-.5.95-1.04 1.84-1.88 2.38-.8.53-1.34.6-2.23.6-.9 0-1.53-.3-2.22-.63-.72-.33-1.47-.65-2.5-.65s-1.78.32-2.5.65c-.7.33-1.32.63-2.22.63-.9 0-1.44-.07-2.23-.6-.84-.54-1.38-1.43-1.88-2.38C2 16.8 1.7 14.9 1.7 13.05c0-3.35 2.2-5.12 4.37-5.12.9 0 1.75.34 2.47.6.53.2 1 .38 1.38.38.38 0 .85-.18 1.38-.38.72-.27 1.57-.6 2.47-.6 2.17 0 4.37 1.77 4.37 5.12 0 1.85-.3 3.75-1.39 5.77z", fill: "currentColor")
      end
    when "outlook"
      tag.svg(xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", class: "size-6 shrink-0") do
        concat tag.path(d: "M21.17 5.17H10.83A1.83 1.83 0 0 0 9 7v10a1.83 1.83 0 0 0 1.83 1.83H21.17A1.83 1.83 0 0 0 23 17V7a1.83 1.83 0 0 0-1.83-1.83zM14.33 16H11v-7.5h1.5V14.5H14.33V16zm2.17 0h-1.5V8.5H16.5V16zm2.17 0H17V8.5h1.67V16z", fill: "currentColor")
        concat tag.path(d: "M1 4.5A1.5 1.5 0 0 1 2.5 3h6A1.5 1.5 0 0 1 10 4.5v15A1.5 1.5 0 0 1 8.5 21h-6A1.5 1.5 0 0 1 1 19.5V4.5zm4 7.5a2.5 2.5 0 1 0 5 0 2.5 2.5 0 0 0-5 0z", fill: "currentColor")
      end
    else # ical
      tag.svg(xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", class: "size-6 shrink-0") do
        tag.path(stroke_linecap: "round", stroke_linejoin: "round", stroke_width: "1.5", d: "M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5")
      end
    end
  end
end