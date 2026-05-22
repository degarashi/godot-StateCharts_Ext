# Godot StateCharts Extension (StateChartExt)

[godot-statecharts](https://github.com/derkork/godot-statecharts) ライブラリを拡張する GDScript 2.0 プラグインである。
このプラグインは、プロキシオブジェクトを通じて、ステートマシンのパラメータ管理とイベント送信をより安全かつ直感的にし、強力な補完機能を提供することを目的としている。

## 特徴

- **静的な型安全性**: イベントとパラメータをインナークラス内の静的変数として定義することで、IDEの補完とコンパイル時のチェックを最大限に活用できる。
- **プロキシベースの API**: 
    - `sc.e.event_name.call()`: 定義したイベント名で直感的にイベントを送信できる。
    - `sc.p.param_name = value`: パラメータへの直接アクセスと代入が可能。内部で自動的な型チェックが行われる。
- **自動通知機能**: パラメータの値が変更された際に、自動的に特定のイベントをトリガーするように設定できる。
- **ステート・ローカルパラメータ**: 特定のステートがアクティブな間だけ存在するパラメータを管理できる。
- **初期値のサポート**: 定義ファイルでパラメータの初期値を指定できる。
- **エディタ統合**: 定義名や型が一致しない場合、Godot エディタ上に設定警告（Configuration Warnings）を表示するバリデーション機能を備えている。
- **インスペクタ表示**: StateChart のパラメータを Godot のインスペクタから直接確認・編集できる（実行時のデバッグに便利）。
- **遷移イベントのドロップダウン選択**: `Transition` ノードのインスペクタ上の `event` プロパティにおいて、定義されたイベントが自動的にドロップダウン形式で選択可能になり、タイポや文字列の手動入力を防ぐことができる。


## インストール方法

- [godot-statecharts](https://github.com/derkork/godot-statecharts) がプロジェクトにインストールされ、有効化されていることを確認する。
- `addons/godot-statecharts_ext` フォルダをプロジェクトの `addons/` ディレクトリにコピーする。
- **プロジェクト設定 > プラグイン** から "Godot StateCharts Extension" を有効にする。

## 使い方ガイド

### StateChart の定義 (自動生成)

シンプルなテキスト形式の定義ファイル (`.scdef`) を使用して、GDScript のボイラープレートを自動生成できる。

`player.scdef` という名前でファイルを作成する：
```text
class PlayerSC

event jump
event crouch
event health_changed

# 初期値 100.0、変更時に health_changed をトリガー
param health float = 100.0 { health_changed: true }

# ステート "Move" の間だけ存在し、かつ変更時に speed_changed をトリガーする
param speed float = 5.0 { local: Move, speed_changed: true }

param ammo int = 10
event speed_changed
```

このファイルを保存すると、プラグインが自動的に `player.gd` を生成・更新する。

---

### 代替方法：手動での定義
`StateChartExt` を継承した新しいスクリプトを作成し、インナークラス内でイベントとパラメータを定義する。

```gdscript
@tool
class_name PlayerSC extends StateChartExt

# イベントの定義
class Event:
    extends StateChartExt.Event
    static var jump := e()
    static var attack := e()
    static var health_changed := e()

# パラメータの定義
class Param:
    extends StateChartExt.Param
    # p(type, notify_map, initial_value, local_state_name)
    static var health := p(TYPE_FLOAT, { PlayerSC.Event.health_changed: true }, 100.0)
    static var speed := p(TYPE_FLOAT, {}, 5.0, &"Move")

# StateChart と紐付ける
func get_sc_info() -> SCInfo:
    return SCInfo.new(Param, Event)
```

### ノードの配置と設定

シーン内のノードに作成したスクリプトをアタッチする（標準の `StateChart` ノードの代わりに使用する）。プラグインが自動的に定義をスキャンする。

ステート配下の `Transition` ノードを設定する際、インスペクタの `event` プロパティには、`StateChartExt` で定義されたイベントがドロップダウンとして自動的に表示され、選択できるようになります。


### コードからのアクセス

`e` (events) と `p` (parameters) プロキシを使用して操作する。

```gdscript
@onready var sc: PlayerSC = $StateChart

func _ready():
    # 非ローカルパラメータは定義時の初期値で自動初期化される
    print(sc.p.health) # 100.0
    
    # パラメータの設定（自動イベントがトリガーされる）
    sc.p.health = 90.0
    
    # インスペクタからパラメータを直接変更することも可能（p/health など）

    # アクセス前の存在チェック
    if sc.p.has("speed"):
        print(sc.p.speed)

func take_damage(amount: float):
    sc.p.health -= amount
    if sc.p.health <= 0:
        sc.e.die.call()
```

### ローカルパラメータ

`.scdef` で `{ local: StateName }` を指定した場合、そのステートに進入した際に**自動的に**初期値でパラメータが登録され、ステートを抜ける際に自動的に削除される。

手動で動的なローカルパラメータを設定する場合：
```gdscript
# 指定したステートを抜ける際、StateChart から自動的に削除される
sc.local().set_param(PlayerSC.Param.speed, 10.0)
```

## ライセンス

このプロジェクトは MIT ライセンスの下で公開されている。詳細は LICENSE ファイルを参照すること。
