redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/1")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  schedule_file = Rails.root.join("config/schedule.yml")
  Sidekiq::Cron::Job.load_from_hash(YAML.load_file(schedule_file)) if schedule_file.exist?
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
