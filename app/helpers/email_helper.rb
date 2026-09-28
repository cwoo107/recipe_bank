# Building blocks for the HTML emails (layouts/mailer.html.erb). Email
# clients ignore stylesheets and modern CSS, so everything here is inline
# styles on tables — keep it that way.
module EmailHelper
  SAGE       = "#5f734c".freeze
  SAGE_DARK  = "#3f4d34".freeze
  SAGE_LIGHT = "#e8ede3".freeze
  INK        = "#2f3027".freeze
  MUTED      = "#6f705f".freeze
  SERIF      = "'Instrument Serif', Georgia, 'Times New Roman', serif".freeze
  SANS       = "Inter, -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif".freeze

  # What to call someone: their name on the household's member list, else the
  # first part of their email.
  def email_name_for(user)
    user.household_membership&.name.presence || user.email.to_s.split("@").first
  end

  # A big serif heading, like the page titles in the app.
  def email_heading(text)
    content_tag(:h1, text, style: "margin:0 0 16px;font-family:#{SERIF};font-size:30px;line-height:1.2;font-weight:400;color:#{INK};")
  end

  def email_paragraph(text = nil, &block)
    content_tag(:p, text || capture(&block), style: "margin:0 0 16px;font-family:#{SANS};font-size:15px;line-height:1.6;color:#{INK};")
  end

  # Small print under the main content.
  def email_note(text = nil, &block)
    content_tag(:p, text || capture(&block), style: "margin:0 0 12px;font-family:#{SANS};font-size:13px;line-height:1.5;color:#{MUTED};")
  end

  # The one call to action — a "bulletproof" table button that renders in
  # Outlook too — followed by the raw link for clients that block buttons.
  def email_button(label, url)
    button = content_tag(:table, role: "presentation", cellspacing: 0, cellpadding: 0, border: 0, style: "margin:8px 0 24px;") do
      content_tag(:tr) do
        content_tag(:td, style: "border-radius:8px;background:#{SAGE};") do
          link_to(label, url, style: "display:inline-block;padding:12px 22px;font-family:#{SANS};font-size:15px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:8px;")
        end
      end
    end

    fallback = email_note do
      safe_join([ "Button not working? Paste this into your browser:", tag.br,
                  link_to(url, url, style: "color:#{SAGE};word-break:break-all;") ])
    end

    button + fallback
  end
end
