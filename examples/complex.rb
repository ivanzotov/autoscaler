require 'sidekiq'
require 'autoscaler/sidekiq'
require 'autoscaler/heroku_platform_scaler'

# This setup is for multiple queues, where each queue has a dedicated process type

heroku = nil
if ENV['HEROKU_APP']
  heroku = {}
  scaleable = %w[default import] - (ENV['ALWAYS'] || '').split(' ')
  scaleable.each do |queue|
    # We are using the convention that worker process type is the
    # same as the queue name
    heroku[queue] = Autoscaler::HerokuPlatformScaler.new(
      queue,
      ENV['HEROKU_ACCESS_TOKEN'],
      ENV['HEROKU_APP'])
  end
end

Sidekiq.configure_client do |config|
  if heroku
    config.client_middleware do |chain|
      chain.add Autoscaler::Sidekiq::Client, heroku
    end
  end
end

# define HEROKU_PROCESS in the Procfile:
#
#    default: env HEROKU_PROCESS=default bundle exec sidekiq -r ./background/boot.rb
#    import:  env HEROKU_PROCESS=import bundle exec sidekiq -q import -c 1 -r ./background/boot.rb

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    if heroku && ENV['HEROKU_PROCESS'] && heroku[ENV['HEROKU_PROCESS']]
      p "Setting up auto-scaledown"
      chain.add(Autoscaler::Sidekiq::Server, heroku[ENV['HEROKU_PROCESS']], 60, [ENV['HEROKU_PROCESS']]) # 60 second timeout
    else
      p "Not scaleable"
    end
  end
end
