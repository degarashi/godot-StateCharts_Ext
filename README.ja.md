# Godot StateCharts Extension (StateChartExt)

[godot-statecharts](https://github.com/derkork/godot-statecharts) ライブラリを拡張する Godot 4.6+ 向けプラグインである。
このプラグインは、自動コード生成とプロキシオブジェクトを通じて、ステートマシンのパラメータ管理とイベント送信をより安全、直感的、かつ型安全にすることを目的としている。

## 特徴

- **静的な型安全性**: `.scdef` ファイルから型付けされた GDScript ボイラープレートを自動生成する。IDE の補完機能を最大限に活用できる。
- **プロキシベースの API**: 
    - `sc.e.jump.call()`: イベントを直感的に送信。
    - `sc.p.health = 90.0`: パラメータに直接アクセス・代入。型チェック付き。
- **自動通知機能**: パラメータ変更時にイベントを自動トリガー（変更検知ロジックは bool または Callable でカスタマイズ可能）。
- **ステート・ローカルパラメータ**: 特定ステートがアクティブな間だけ存在するパラメータ。自動初期化・クリーンアップ。
- **エディタ統合**: 
    - **設定警告**: イベント名、パラメータ型、ガード式、重複トランジション、重複ステート名、未使用イベント/パラメータ、不正な並列遷移などをリアルタイム検証。
    - **インスペクタパラメータ**: `p/` グループから直接編集。ローカルパラメータは `[L: Move] speed` のように表示。
    - **遷移イベントドロップダウン**: `Transition` ノードの `event` プロパティに定義済みイベントが自動表示。
    - **SCXML コントロール**: インスペクタに Export/Import/Re-import ボタンとドラッグ＆ドロップゾーン。
    - **エラーチェック / メタデータクリア**: ボタン一つで全検証 or メタデータ削除。
    - **除外設定（イベント個別）**: 未使用イベント警告・不明イベント警告をイベント単位で除外可能。
    - **ファイルシステムアイコン**: `.scdef` / `.scxml` ファイルにカスタムアイコン。
    - **シーンツリーアイコン**: ステートのシグナル接続状態をバッジ表示。クリックでコードへジャンプ。
    - **コンテキストメニュー**: ファイルシステムで右クリック → SCXML変換/GDScript再生成。シーンツリーで右クリック → SCXML エクスポート/インポート/scdef を開く。
    - **外部エディタ**: `.scdef` は Godot 設定の外部テキストエディタで、`.scxml` は専用エディタパス設定で開く。
- **ランタイム可視化**: `runtime_visualization` でアクティブなステート名を画面上にオーバーレイ表示。
- **ランタイム履歴**: ステート遷移の履歴をタイムスタンプ付きで記録（インスペクタで表示）。
- **デバッグツール**: ステート遷移ログ (`debug_log`) とイベント受信ログ (`debug_event`) をトグル可能。

## SCXML 連携

本格的な SCXML インポート/エクスポート（Qt Creator 等とのラウンドトリップ対応）。

- **高度なラウンドトリップ**: メタデータ、カスタム属性、名前空間付きタグ（`qt:editorinfo` 等）、ステート UID を完全保存。
- **History ステート**: `<history>` タグ (`shallow`/`deep`) → `HistoryState`。
- **ガード条件**: `cond` 属性を構文解析し、複合ガード木（In, &&, ||, !, 式）に変換。エクスポート時も復元。
- **Entry/Exit アクション**: `<onentry>`/`<onexit>` 内の `<send>` / `<assign>` を保持。
- **イベント遅延**: `event@delay` 構文（例: `shoot@500` = 500ms 遅延）。
- **複数イベント**: スペース区切りのイベントを個別の Transition ノードに分割。エクスポート時に同一設定の遷移を統合。
- **自動命名**: 名前未指定の遷移に `JumpToAirborne` のような自動命名。
- **カスタム名前空間**: 全ての `xmlns` 宣言をキャプチャ・復元。
- **.scdef 自動生成**: SCXML インポート時に対応する `.scdef` / `.gd` を自動生成。
- **接続保存**: ユーザーのシグナル接続を UID ベースで保存・復元。


## インストール方法

- [godot-statecharts](https://github.com/derkork/godot-statecharts) がプロジェクトにインストールされ、有効化されていることを確認する。
- `addons/godot-statecharts_ext` フォルダをプロジェクトの `addons/` ディレクトリにコピーする。
- **プロジェクト設定 > プラグイン** で有効化する。

## 使い方ガイド

### StateChart の定義 (.scdef)

`.scdef` ファイルでステートチャートのインターフェースを定義する。ドキュメントコメント (`##`) は生成コードに引き継がれる。

`player.scdef`:
```text
class PlayerSC

## プレイヤーがジャンプした時にトリガーされる
event jump
event crouch
event health_changed

# 初期値 100.0、値が実際に変更された時のみ health_changed をトリガー
param health float = 100.0 { health_changed: true }

# ステート "Move" の間だけ存在し、変更時に speed_changed をトリガー
param speed float = 5.0 { local: Move, speed_changed: true }

param ammo int = 10
param items array = []
param stats dict = {}
event speed_changed
```

保存すると自動的に `player.gd` が生成される。

### サポートされる型

`float`, `int`, `bool`, `string`, `vector2`, `vector2i`, `vector3`, `vector3i`, `vector4`, `vector4i`, `rect2`, `rect2i`, `plane`, `quaternion`, `aabb`, `basis`, `transform2d`, `transform3d`, `projection`, `color`, `stringname`, `nodepath`, `rid`, `object`, `callable`, `signal`, `array`, `dict`, `dictionary`, `variant`。

### ノードの配置と設定

生成されたスクリプト（例: `player.gd`）をノードにアタッチする（`StateChart` ノードの代わりに使用）。

インスペクタで設定可能な項目:
- **Debug Log / Debug Event**: 遷移ログ / イベントログの切り替え。
- **Runtime Visualization**: アクティブなステートを画面上に表示。
- **Exclude Unused / Unknown Event Warnings**: イベント単位で警告除外。
- **Check Errors / Clear All Metadata**: 検証ボタン / メタデータ一括削除。
- **Export/Import SCXML**: ボタンとドラッグ＆ドロップゾーン。
- **p/ グループ**: パラメータの直接編集。

### コードからのアクセス

```gdscript
@onready var sc: PlayerSC = $StateChart

func _ready():
    print(sc.p.health) # 100.0
    sc.p.health = 90.0    # health_changed がトリガーされる
    sc.e.jump.call()

    if sc.p.has("speed"):
        print(sc.p.speed)

func take_damage(amount: float):
    sc.p.health -= amount
    if sc.p.health <= 0:
        sc.e.die.call()
```

### ローカルパラメータ

`param speed float = 5.0 { local: Move, speed_changed: true }` — `Move` ステート進入時に自動登録、退出時に自動削除。

アドホックなローカルパラメータ:
```gdscript
sc.local().set_param(PlayerSC.Param.speed, 10.0)
# 現在のアクティブステート退出時に自動消滅
```

### イベント遅延

SCXML の `event@delay_ms` 構文で遅延指定可能。コード上では `Transition.delay_in_seconds` で設定。

## ユーティリティ (STAux)

```gdscript
# 複数シグナルをイベントに一括バインド
STAux.bind_signals_to_events(sc, {
    button.pressed: PlayerSC.Event.jump,
    timer.timeout: PlayerSC.Event.crouch
})

# 型安全なコレクション操作
STAux.st_add_array(sc, PlayerSC.Param.items, "Sword")
STAux.st_insert_dict(sc, PlayerSC.Param.stats, "strength", 10)
STAux.st_init_dict(sc, PlayerSC.Param.stats)
STAux.st_init_array(sc, PlayerSC.Param.items)
STAux.st_add_value(sc, PlayerSC.Param.health, -10.0) # [prev, new] を返す

# ステートアクティブ状態の確認
STAux.is_state_active(sc, $MoveState)

# 全パラメータのスナップショット（セーブ/デバッグ用）
var snapshot := STAux.st_get_all_params_as_dict(sc)
```

## アドバンス：手動での定義

```gdscript
@tool
class_name MySC extends StateChartExt

class Event:
    extends StateChartExt.Event
    static var jump := e()

class Param:
    extends StateChartExt.Param
    static var health := p(TYPE_FLOAT, { MySC.Event.health_changed: true }, 100.0)

func get_sc_info() -> SCInfo:
    return SCInfo.new(Param, Event)
```

## ライセンス

このプロジェクトは MIT ライセンスの下で公開されている。詳細は LICENSE ファイルを参照すること。
