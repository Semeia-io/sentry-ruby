ENV["RAILS_ENV"] = "test"

require "rails"

require "active_record"
require "active_job/railtie"
require "action_view/railtie"
require "action_controller/railtie"

require 'sentry/rails'

ActiveSupport::Deprecation.silenced = true
ActiveRecord::Base.logger = Logger.new(nil)

# need to init app before establish connection so sqlite can place the database file under the correct project root
class TestApp < Rails::Application
end

v5_2 = Gem::Version.new("5.2")
v6_0 = Gem::Version.new("6.0")
v6_1 = Gem::Version.new("6.1")
v7_0 = Gem::Version.new("7.0")
v7_1 = Gem::Version.new("7.1")

case Gem::Version.new(Rails.version)
when -> (v) { v < v5_2 }
  require "support/test_rails_app/apps/5-0"
when -> (v) { v.between?(v5_2, v6_0) }
  require "support/test_rails_app/apps/5-2"
when -> (v) { v.between?(v6_0, v6_1) }
  require "support/test_rails_app/apps/6-0"
when -> (v) { v.between?(v6_1, v7_0) }
  require "support/test_rails_app/apps/6-1"
when -> (v) { v.between?(v7_0, v7_1) }
  require "support/test_rails_app/apps/7-0"
end

def make_basic_app(&block)
  run_pre_initialize_cleanup

  app = Class.new(TestApp) do
    def self.name
      "RailsTestApp"
    end
  end

  app.config.hosts = nil
  app.config.secret_key_base = "test"
  app.config.logger = Logger.new(nil)
  app.config.eager_load = true

  configure_app(app)

  app.routes.append do
    get "/exception", :to => "hello#exception"
    get "/view_exception", :to => "hello#view_exception"
    get "/view", :to => "hello#view"
    get "/not_found", :to => "hello#not_found"
    get "/world", to: "hello#world"
    get "/with_custom_instrumentation", to: "hello#with_custom_instrumentation"
    resources :posts, only: [:index, :show] do
      member do
        get :attach
      end
    end
    get "500", to: "hello#reporting"
    root :to => "hello#world"
  end

  app.initializer :configure_sentry do
    Sentry.init do |config|
      config.release = 'beta'
      config.dsn = "http://12345:67890@sentry.localdomain:3000/sentry/42"
      config.transport.transport_class = Sentry::DummyTransport
      # for sending events synchronously
      config.background_worker_threads = 0
      config.capture_exception_frame_locals = true
      yield(config, app) if block_given?
    end
  end

  app.initialize!

  Rails.application = app

  Post.all.to_a # to run the sqlte version query first

  # and then clear breadcrumbs in case the above query is recorded
  Sentry.get_current_scope.clear_breadcrumbs if Sentry.initialized?

  app
end
