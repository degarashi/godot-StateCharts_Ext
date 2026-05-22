# Godot StateCharts Extension (StateChartExt)

[godot-statecharts](https://github.com/derkork/godot-statecharts) ライブラリを拡張する Godot 4.6+ 向けプラグインである。
このプラグインは、自動コード生成とプロキシオブジェクトを通じて、ステートマシンのパラメータ管理とイベント送信をより安全、直感的、かつ型安全にすることを目的としている。

## 特徴

- **静的な型安全性**: `.scdef` ファイルから GDScript のボイラープレートを自動生成する。生成されたコードには明示的なメンバが含まれるため、IDE の補完機能を最大限に活用できる。
- **プロキシベースの API**: 
    - `sc.e.event_name.call()`: 定義したイベント名で直感的にイベントを送信できる。
    - `sc.p.param_name = value`: パラメータへの直接アクセスと代入が可能。内部で自動的な型チェックが行われる。
- **自動通知機能**: パラメータの値が変更された際に、自動的に特定のイベントをトリガーするように設定できる（変更検知ロジックのカスタマイズも可能）。
- **ステート・ローカルパラメータ**: 特定のステートがアクティブな間だけ存在するパラメータを管理できる。ステート進入時に自動初期化され、退出時に自動クリーンアップされる。
- **初期値のサポート**: 定義ファイルでパラメータの初期値を指定できる。
- **エディタ統合**: 
    - **設定警告 (Configuration Warnings)**: イベント名、パラメータ型、エクスプレッションの構文などをリアルタイムでバリデーションする。
    - **インスペクタ統合**: StateChart のパラメータを Godot のインスペクタ上の `p/` グループから直接確認・編集できる。
    - **遷移イベントのドロップダウン選択**: `Transition` ノードのインスペクタ上の `event` プロパティにおいて、定義されたイベントが自動的にドロップダウン形式で選択可能になる。
    - **エラーチェックボタン**: インスペクタ上のボタンから、手動でバリデーションをトリガーできる。
- **デバッグツール**: ステート遷移ログ (`debug_log`) やイベント受信ログ (`debug_event`) をトグルで切り替え可能。


## インストール方法

- [godot-statecharts](https://github.com/derkork/godot-statecharts) がプロジェクトにインストールされ、有効化されていることを確認する。
- `addons/godot-statecharts_ext` フォルダをプロジェクトの `addons/` ディレクトリにコピーする。
- **プロジェクト設定 > プラグイン** から "Godot StateCharts Extension" を有効にする。

## 使い方ガイド

### StateChart の定義 (.scdef)

`.scdef` ファイルを使用して、ステートチャートのインターフェースを定義する。ドキュメントコメント (`##`) は生成されたコードにも引き継がれる。

`player.scdef` という名前でファイルを作成する：
```text
class PlayerSC

## プレイヤーがジャンプした時にトリガーされる
event jump
event crouch
event health_changed

# 初期値 100.0、値が実際に変更された時のみ health_changed をトリガー
param health float = 100.0 { health_changed: true }

# ステート "Move" の間だけ存在し、かつ変更時に speed_changed をトリガーする
param speed float = 5.0 { local: Move, speed_changed: true }

param ammo int = 10
param items array = []
param stats dict = {}
event speed_changed

```

このファイルを保存すると、プラグインが自動的に `player.gd` を生成・更新する。

### ノードの配置と設定

> 生成されたスクリプト（例: `player.gd`）をシーン内のノードにアタッチする（標準の `StateChart` ノードの代わりに使用する）。
> インスペクタから、`Debug Log` や `Debug Event` を有効にしてデバッグに役立てることができる。
> 未使用のイベント警告を無視したい場合は `Exclude Unused Event` リストを、未知のイベント警告を無視したい場合は `Exclude Warn Unknown Events` リストを使用する。

### コードからのアクセス

生成された `e` (events) と `p` (parameters) プロキシを使用することで、快適なコーディングが可能になる。

```gdscript
@onready var sc: PlayerSC = $StateChart

func _ready():
    # パラメータは自動的に初期化される
    print(sc.p.health) # 100.0
    
    # パラメータの設定（自動通知がトリガーされる）
    sc.p.health = 90.0
    
    # イベントはメソッドとして呼び出す
    sc.e.jump.call()

    # パラメータの存在チェック（ローカルパラメータなどに便利）
    if sc.p.has("speed"):
        print(sc.p.speed)

func take_damage(amount: float):
    sc.p.health -= amount
    if sc.p.health <= 0:
        sc.e.die.call()
```

### ローカルパラメータ

`.scdef` で `{ local: StateName }` を指定した場合、そのステートに進入した際に**自動的に**パラメータが登録され、ステートを抜ける際に自動的に削除される。

また、`local()` ヘルパーを使用して、アドホックにローカルパラメータを管理することもできる：
```gdscript
# 現在のアクティブなステートを抜ける際、自動的に削除される
sc.local().set_param(PlayerSC.Param.speed, 10.0)
```

## ユーティリティ (STAux)

`STAux` クラスは、一般的なタスクのための追加のヘルパーを提供する。

```gdscript
# 複数のシグナルをイベントに一括でバインドする
STAux.bind_signals_to_events(sc, {
    button.pressed: PlayerSC.Event.jump,
    timer.timeout: PlayerSC.Event.crouch
})

# 型安全なコレクション操作
STAux.st_add_array(sc, PlayerSC.Param.items, "Sword")
STAux.st_insert_dict(sc, PlayerSC.Param.stats, "strength", 10)
```

## アドバンス：手動での定義

`.scdef` を使用したくない場合は、手動で `StateChartExt` を継承して定義することも可能である。

```gdscript
@tool
class_name MySC extends StateChartExt

class Event:
    extends StateChartExt.Event
    static var jump := e()

class Param:
    extends StateChartExt.Param
    # p(type, notify_map, initial_value, local_state_name)
    static var health := p(TYPE_FLOAT, { MySC.Event.health_changed: true }, 100.0)

func get_sc_info() -> SCInfo:
	return SCInfo.new(Param, Event)
```

## ライセンス

このプロジェクトは MIT ライセンスの下で公開されている。詳細は LICENSE ファイルを参照すること。
