require 'bf/engine'
require "logger"
require "active_record"
require "mysql2"
require "bf/version"
require "bf/monitor"
require "bf/client"
require "bf/trade"
require "bf/fetcher"
require "bf/cli"
require "bf/setting"
require "bf/my_trade"
require "bf/my_trade_ship"
require "bf/worker/base_worker"
require "bf/worker/buying_trade_worker"
require "bf/worker/selling_trade_worker"

module BF
  END_POINT = 'api.bitflyer.jp'
  PROCUT_CODE = 'FX_BTC_JPY'

  def logger
    @logger ||= Logger.new("debug.log")
  end

  def logger=(logger)
    @logger = logger
  end
end
