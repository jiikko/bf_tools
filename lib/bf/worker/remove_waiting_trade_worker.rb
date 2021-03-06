# 通常、取引所にポーリングで注文の状態をチェックするのだけど不幸にもプロセスが停止してしまうと
# レコードのステータスを更新する人がいなくなるので、活動中ステータスの注文を再確認する非同期タスク
module BF
  class RemoveWaitingTradeWorker < BaseWorker
    def perform
      BF::MyTradeShip.running.each do |ship|
        # TODO buy_tradeがrequestedのままだったらキャンセルにする
        # ship.buy_trade
        if ship.buy_trade.error?
          ship.sell_trade.canceled!
        end
        is_trade_sccessd =
          begin
            ship.sell_trade.trade_sccessd?
          rescue => e
            puts e.full_message
            false
          end
        if is_trade_sccessd
          ship.sell_trade.succeed!
        end
      end
    end
  end
end
