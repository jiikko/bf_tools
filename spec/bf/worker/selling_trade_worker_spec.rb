require 'spec_helper'

RSpec.describe BF::SellingTradeWorker do
  describe '#perform' do
    context 'MyTrade.params[:timeout]が設定されている時' do
      context '買い約定済みの時' do
        it 'succeedになる(タイムアウトにならない)' do
          buy_trade  = BF::MyTrade.create!(price: 1, size: 0.001, status: :requested, kind: :buy,
                                           params: { timeout: 6.second })
          sell_trade = BF::MyTrade.create!(price: 1, size: 0.001, status: :waiting_to_sell, kind: :sell)
          allow(BF::MyTrade).to receive(:find).with(buy_trade.id).and_return(buy_trade)
          allow(buy_trade).to receive(:trade_sccessd?).and_return(true)
          allow(buy_trade).to receive(:run_sell_trade!)
          BF::MyTradeShip.create!(sell_trade: sell_trade, buy_trade: buy_trade)
          BF::SellingTradeWorker.perform(buy_trade.id)
          expect(buy_trade.reload.status).to eq('succeed')
        end
      end
      context 'タイムアウトをすでに迎える時' do
        it '注文をキャンセルすること' do
          buy_trade  = BF::MyTrade.create!(price: 1, size: 0.001, status: :requested, kind: :buy,
                                           params: { timeout: 0.second }, created_at: 1.second.ago)
          sell_trade = BF::MyTrade.create!(price: 1, size: 0.001, status: :waiting_to_sell, kind: :sell)
          BF::MyTradeShip.create!(sell_trade: sell_trade, buy_trade: buy_trade)
          BF::SellingTradeWorker.perform(buy_trade.id)
          expect(buy_trade.reload.status).to eq('timeout')
        end
      end
    end
  end
end
