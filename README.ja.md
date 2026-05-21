# Godot StateCharts Extension (StateChartExt)

[godot-statecharts](https://github.com/derkork/godot-statecharts) ライブラリを拡張する GDScript 2.0 プラグインである。
このプラグインは、プロキシオブジェクトを通じて、ステートマシンのパラメータ管理とイベント送信をより安全かつ直感的にし、強力な補完機能を提供することを目的としている。

## 特徴

- **静的な型安全性**: イベントとパラメータをインナークラス内の静的変数として定義することで、IDEの補完とコンパイル時のチェックを最大限に活用できる。
- **プロキシベースの API**: 
    - `sc.e.event_name.call()`: 定義したイベント名で直感的にイベントを送信できる。
    - `sc.p.param_name = value`: パラメータへの直接アクセスと代入が可能。内部で自動的な型チェックが行われる。
- **自動通知機能**: パラメータの値が変更された際に、自動的に特定のイベントをトリガーするように設定できる。
- **ステート・ローカルパラメータ**: 特定のステートに紐付き、そのステートを抜ける際に自動的にクリーンアップされるパラメータを簡単に管理できる。
- **エディタ統合**: 定義名や型が一致しない場合、Godot エディタ上に設定警告（Configuration Warnings）を表示するバリデーション機能を備えている。
- **ログ統合**: 詳細な診断ログ出力をサポートしている（`DLogger` と互換）。

## インストール方法

1. [godot-statecharts](https://github.com/derkork/godot-statecharts) がプロジェクトにインストールされ、有効化されていることを確認する。
2. `addons/godot-statecharts_ext` フォルダをプロジェクトの `addons/` ディレクトリにコピーする。
3. **プロジェクト設定 > プラグイン** から "Godot StateCharts Extension" を有効にする。

## 使い方ガイド

### 1. StateChart の定義

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
    # health は値が実際に変更された時のみ 'health_changed' イベントをトリガーする
    static var health := p(TYPE_FLOAT, { PlayerSC.Event.health_changed: true })
    static var speed := p(TYPE_FLOAT)

# StateChart と紐付ける
func get_sc_info() -> SCInfo:
    return SCInfo.new(Param, Event)
```

### 2. ノードの配置と設定

シーン内のノードに作成したスクリプトをアタッチする（標準の `StateChart` ノードの代わりに使用する）。プラグインが自動的に定義をスキャンする。

### 3. コードからのアクセス

`e` (events) と `p` (parameters) プロキシを使用して、クリーンな API で操作する。

```gdscript
@onready var sc: PlayerSC = $StateChart

func _ready():
    # パラメータの設定（自動イベントがトリガーされる）
    sc.p.health = 100.0
    
    # アクセス前の安全な存在チェック
    if sc.p.has("speed"):
        print(sc.p.speed)

func take_damage(amount: float):
    sc.p.health -= amount
    if sc.p.health <= 0:
        # .call() を使用してイベントを送信
        sc.e.die.call()
```

### 4. ローカルパラメータ

特定のステートがアクティブな間だけ存在するパラメータを設定する。

```gdscript
# 現在のステートを抜ける際、StateChart から自動的に削除される
sc.local().set_param(PlayerSC.Param.speed, 10.0)
```

## 安全上の注意 (GDScript 2.0 プロキシ)

Godot 4 の動的プロパティアクセスの仕様により、以下の点に注意すること。
- イベントの送信には `sc.e.event_name.call()` を使用すること。
- パラメータが登録されているか不明な場合（ローカルパラメータなど）は、`sc.p.has("param_name")` を使用してチェックすること。
- プロキシ上の存在しないプロパティに直接アクセスすると、実行時エラーが発生する。

## ライセンス

このプロジェクトは MIT ライセンスの下で公開されている。詳細は LICENSE ファイルを参照すること。
