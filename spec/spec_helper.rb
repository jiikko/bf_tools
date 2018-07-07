ENV['RUN_ENV'] = 'test'

require "bundler/setup"
require "pry"
require "bf"
require "resque_spec"
require "support/factory"

RSpec.configure do |config|
  config.before(:each) do
    ResqueSpec.reset!
    ActiveRecord::Base.connection.begin_transaction
  end
  config.after(:each) do
    ActiveRecord::Base.connection.rollback_transaction
  end

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

ActiveRecord::Base.establish_connection(
  adapter:   'sqlite3',
  database:  ':memory:'
)
ActiveRecord::Migrator.migrate(File.expand_path('../../db/migrate', __FILE__))
ActiveRecord::Base.logger = Logger.new(File.join(File.dirname(__FILE__), '../log/test.log'))
