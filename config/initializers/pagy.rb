# Pagination (recipes and ingredients lists — see shared/_pagination).
# Pagy reads its own dictionaries, not Rails' I18n; this adds ours, which
# overrides the default English wording (config/locales/pagy/en.yml).
Pagy::I18n.pathnames << Rails.root.join("config/locales/pagy")
