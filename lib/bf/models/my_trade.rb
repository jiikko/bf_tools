module BF
  class MyTrade < ::ActiveRecord::Base
    serialize :params

    enum status: [
      :waiting_to_request,
      :waiting_to_sell,
      :requested,
      :succeed,
      :failed,
      :timeout,
      :error,
      :canceled,
      :canceled_before_request,
      :selling,
      :parted_trading,
    ]
    RUNNING_STATUS_FOR_BUY = [
      :waiting_to_request, :requested, :parted_trading,
    ]
    RUNNING_STATUS_FOR_SELL = [
      :waiting_to_sell, :selling,
    ]

    enum kind: [:buy, :sell]

    has_one :trade_ship, class_name: 'BF::MyTradeShip', foreign_key: :buy_trade_id, dependent: :destroy
    has_one :sell_trade, class_name: 'BF::MyTrade', through: :trade_ship, source: :sell_trade
    has_one :buy_trade, class_name: 'BF::MyTrade', through: :trade_ship, source: :buy_trade

    def self.find_by_sell(trade_id)
      find_by(kind: :sell, id: trade_id)
    end

    def self.tries_count
      20
    end

    def self.last_sell_succeed_at
      where(kind: :sell, status: self.statuses[:succeed]).maximum(:updated_at)
    end

    def running?
      case kind.to_sym
      when :buy
        RUNNING_STATUS_FOR_BUY.include?(status.to_sym)
      when :sell
        RUNNING_STATUS_FOR_SELL.include?(status.to_sym)
      end
    end

    def run_buy_trade!(target_price, options={})
      update!(price: target_price, size: request_order_size, status: :waiting_to_request, kind: :buy, params: options.presence)
      begin
        create_sell_trade!
        order_acceptance_id = api_client.buy(target_price, request_order_size) # まだ約定していない
        update!(order_acceptance_id: order_acceptance_id, status: :requested)
      rescue => e
        update!(error_trace: e.inspect, status: :error)
        trade_ship.sell_trade.canceled!
        return self
      end
      SellingTradeWorker.perform_async(self.id)
      self
    end

    def run_sell_trade!
      self.sell_trade.reload
      return if canceled?
      begin
        order_acceptance_id = nil
        Retryable.retryable(tries: self.class.tries_count) do
          order_acceptance_id = sell_trade.api_client.sell(sell_trade.price, sell_trade.size)
        end
        sell_trade.update!(order_acceptance_id: order_acceptance_id, status: :selling)
      rescue => e
        sell_trade.update!(error_trace: e.inspect, status: :error)
        return sell_trade
      end
      OrderWaitingWorker.perform_async(sell_trade.id)
    end

    def request_order_range
      setting_record = BF::Setting.record
      if setting_record.respond_to?(:order_range)
        setting_record.order_range
      else
        400
      end
    end

    def request_order_size
      setting_record = BF::Setting.record
      if setting_record.respond_to?(:order_size)
        setting_record.order_size
      else
        0.01
      end
    end

    def api_client
      @client ||= BF::Client.new
    end

    def trade_sccessd?
      case
      when order_acceptance_id
        response = get_order
        return false if response.empty?
        current_total_size = response.map { |x| BigDecimal.new(x['size'].to_s) }.sum.to_f
        if self.size == current_total_size
          return true
        else
          return self.run_sccessd_or_nothing!(current_total_size)
        end
      else
        raise('order_acceptance_id がありません')
      end
    end

    # 部分取引のまま買値から1500円以上離れたら、買注文をキャンセルして部分買いのみの売り注文を出す
    def run_sccessd_or_nothing!(current_total_size)
      return false if sell?

      if ((self.price + 600) < BF::Trade.last.price) && BF::Monitor.new.store_status_green?
        BF.logger.info "部分取引中のBF::MyTrade(id: #{id})は、最終取引から1500円離れたので買い取り分のみで決済します"
        self.class.where(id: [self.id, sell_trade.id]).update_all(size: current_total_size)
        Retryable.retryable(tries: self.class.tries_count) do
          api_client.cancel_order(self.order_acceptance_id)
        end
        return true
      else
        self.parted_trading! unless parted_trading?
        return false
      end
    end

    def wait_to_sell(timeout: 15.minutes)
      loop do
        self.reload
        if created_at.localtime < timeout.ago
          BF.logger.info "買いポーリングしていましたがタイムアウトです。買い注文をキャンセルします。売り注文は出していません。"
          cancel_order_with_timeout!
          return
        end
        if canceled?
          BF.logger.info "買い注文をポーリングしていましたが#{status}だったので中止しました。売り注文を出していません。"
          sell_trade.canceled_before_request!
          return
        end
        if trade_sccessd?
          BF::logger.info '約定を確認しました。これから売りを発注します。'
          self.succeed!
          break
        end
        sleep(1)
      end
    end

    def cancel_order!
      api_client.cancel_order(self.order_acceptance_id)
      canceled!
      if kind == 'buy'
        sell_trade.canceled!
      end
    end

    # スワップ手数料を回避する時にorder_idが変わった時に注文IDの再紐付けを行う
    def resync!
      preorders = api_client.preorders
      found_preorders =
        preorders.select do |preorder|
          preorder['size'] == size &&
            preorder['price'] == price &&
            preorder['side'] == kind.upcase
        end
      case found_preorders.size
      when 0
        BF.logger.info('注文待ちから注文がヒットしませんでした')
      when 1
        found_preorder = found_preorders.first
        update!(order_acceptance_id: found_preorder['child_order_acceptance_id'])
      else
        BF.logger.info('注文待ちから複数の注文がヒットしました。何もしません')
      end
    end

    def cancel_order_with_timeout!
      api_client.cancel_order(self.order_acceptance_id)
      timeout!
      sell_trade.canceled_before_request!
    end

   def get_order
     api_client.get_order(order_acceptance_id: order_acceptance_id) || []
   end

    private

    def create_sell_trade!
      raise("invalid kind, because I called from sell") if self.sell?
      ship = create_trade_ship!
      sell_trade_id = BF::MyTrade.create!(price: self.price + request_order_range, size: ship.buy_trade.size, status: :waiting_to_sell, kind: :sell).id
      ship.update!(sell_trade_id: sell_trade_id)
    end
  end
end
