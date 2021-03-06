module BF
  class Scalping
    class Makiami < Base
      include LowTechValidator

      def scalp(dry_run=false)
        if valid? && !dry_run
          BF.logger.info '注文しましょう！'
          last_price = BF::Trade.last.price
          maiami_times.times do |i|
            price = last_price - (makiami_range * i)
            buy_trade = BF::MyTrade.new.run_buy_trade!(price, timeout: 2.minutes)
            ScalpingTask.create!(trade_ship_id: buy_trade.trade_ship.id)
          end
          return true
        end
      end

      private

      def maiami_times
        4
      end

      def makiami_range
        500
      end
    end
  end
end
