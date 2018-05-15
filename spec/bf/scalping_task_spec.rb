require 'spec_helper'

RSpec.describe BF::ScalpingTask do
  before(:each) do
    BF::MyTradeShip.delete_all
    BF::MyTrade.delete_all
    BF::ScalpingTask.delete_all
    ResqueSpec.reset!
    allow_any_instance_of(BF::Client).to receive(:buy).and_return(1)
  end

  describe '.running?' do
    context '実行中ステータスのtaskがある時' do
      context '注文した直後の時' do
        it 'return true' do
          buy_trade = BF::MyTrade.new.run_buy_trade!(10)
          BF::ScalpingTask.create!(trade_ship_id: buy_trade.trade_ship.id)
          expect(BF::ScalpingTask.running?).to eq(true)
        end
      end
    end
    context '買いが約定した直後(売り約定待ち)の時' do
      it 'return true' do
        buy_trade = BF::MyTrade.new.run_buy_trade!(10)
        BF::ScalpingTask.create!(trade_ship_id: buy_trade.trade_ship.id)
        buy_trade.succeed!
        buy_trade.trade_ship.sell_trade.waiting_to_sell!
        expect(BF::ScalpingTask.running?).to eq(true)
      end
    end

    context '実行中ステータスのtaskがない時' do
      context '売りが約定した直後の時' do
        it 'return false' do
          buy_trade = BF::MyTrade.new.run_buy_trade!(10)
          BF::ScalpingTask.create!(trade_ship_id: buy_trade.trade_ship.id)
          buy_trade.succeed!
          buy_trade.trade_ship.sell_trade.succeed!
          expect(BF::ScalpingTask.running?).to eq(false)
        end
      end
    end

    context 'BF::ScalpingTaskレコードが無い時' do
      it 'return false' do
        expect(BF::ScalpingTask.count).to eq(0)
        expect(BF::ScalpingTask.running?).to eq(false)
      end
    end
  end
end
