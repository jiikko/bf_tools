# BF
* ビットフライヤーのpublic apiから取得した最終取引価格を1~60分の間隔で集計する
* 注文できる

```
1m: 932051 ~ 934133 (2082) 5m: 931161 ~ 933118 (1957) 10m: 931448 ~ 934133 (2685) 30m: 931983 ~ 934867 (2884) 60m: 931482 ~ 935966 (4484) 上 下 下 下
1m: 932051 ~ 934133 (2082) 5m: 931161 ~ 933341 (2180) 10m: 931448 ~ 934133 (2685) 30m: 931983 ~ 934867 (2884) 60m: 931482 ~ 935966 (4484) 上 下 下 下
1m: 932224 ~ 934133 (1909) 5m: 931161 ~ 933350 (2189) 10m: 931448 ~ 934133 (2685) 30m: 931983 ~ 934867 (2884) 60m: 931482 ~ 935966 (4484) 上 下 下 下
1m: 932276 ~ 934133 (1857) 5m: 931000 ~ 933378 (2378) 10m: 931448 ~ 934133 (2685) 30m: 931983 ~ 934867 (2884) 60m: 931482 ~ 935966 (4484) 上 下 下 下
```

## Installation
### Gemfile
```
gem 'bf', github: 'jiikko/bf', branch: :master
```

## Usage
```
bit/run.rb
```
```
COUNT=5 QUEUE=normal be rake resque:workers
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## TODO
* 連続して取得できていることを可視化したい
* 取引所のステータスをDBにいれる(いまレディス)
  * 30分以内に負荷が高いと注文を入れない、という機能をいれたい(注文が遅れるとつらい)
* redis のワーニングをけす
  * `The client method is deprecated as of redis-rb 4.0.0, please use the new _clientmethod instead. Support for the old method will be removed in redis-namespace 2.0.`
* 公式からキャンセルするとorder_idでとれなくなるので、一度order_idをとったらステータスを変えて、以降ステータスがとれなくなったら削除された、と判断するよう修正する
* 売りが失敗した場合retryをしたい
* ログ出力への出力もしつつ、ログテーブルにも出力したい
  * 買いが失敗した旨のログとか、アクションが必要な旨のログも見れるようにする
* タイムアウトを迎えて注文をキャンセルする時は、最終取引価格が近い時はキャンセルをしない
  * キャンセル注文と送った直後に成約すると売り注文が走らなくなるため
* 売り時に注文エラーになってもリトライをしていないので買いっぱなしになる
  * リトライして、リトライをしてもだめな旨を緊急的な通知煮出す

## 買い注文を入れるロジック
* 上上上上 かつ 1~5足の最小差額(赤いバー)(独自指標)が100の時は発注しない
* 100,100,100,100の時は発注しない
  * 高騰し続けていると下落が速いため高値を掴みやすいため
* 下下下上 かつ 0,0,0,100 は発注しない
  * 短時間で下落している
* 1,5,10で分散が一定値に収まるなら発注する
  * レンジで上下しているとみなす
* 下上xx   かつ 最小差額(赤いバー)(独自指標) が0の時に1分足最小価格で発注する

## デバッグ系
```
Resque.redis.lrange 'queue:normal', 0, 10
```
