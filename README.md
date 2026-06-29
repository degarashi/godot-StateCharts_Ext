# Godot StateCharts Extension (StateChartExt)

A Godot 4.6+ plugin that extends the [godot-statecharts](https://github.com/derkork/godot-statecharts) library.
This extension provides a statically typed wrapper to make state machine parameters and events safer, more discoverable, and easier to use through proxy objects and automatic code generation.

## Features

- **Static Type Safety**: Define your events and parameters in a simple `.scdef` file to automatically generate GDScript boilerplate with explicit typed members for maximum IDE completion.
- **Proxy-based API**: 
    - `sc.e.jump.call()`: Dispatch events with a clean functional syntax.
    - `sc.p.health = 90.0`: Access and modify parameters directly.
- **Auto-Notifications**: Parameters can automatically trigger events when their values change (customizable with change-detection logic using booleans or custom Callables).
- **State-Local Parameters**: Parameters that exist only while a specific state is active — automatically initialized on entry and cleaned up on exit.
- **Editor Integration**: 
    - **Configuration Warnings**: Real-time validation for event names, parameter types, guard expressions, transition overlaps, duplicate state names, unused events/params, and illegal parallel transitions.
    - **Inspector Parameters**: View and edit parameters directly in the inspector under the `p/` group. Local params show their owning state, e.g. `[L: Move] speed`.
    - **Transition Event Dropdown**: Automatic dropdown for the `event` property on `Transition` nodes, populated from your definitions.
    - **SCXML Controls**: Export/Import/Re-import buttons and a drag-and-drop zone in the inspector.
    - **Check Errors / Clear Metadata**: Buttons to trigger validation or strip all custom metadata.
    - **Exclude Warnings Per-Event**: Individual toggles for excluding unused-event and unknown-event warnings per event.
    - **File System Icons**: Custom icons for `.scdef` and `.scxml` files in the FileSystem dock.
    - **Scene Tree Icons**: Signal connection badges on states (event_received, state_entered, etc.) — click to jump to the connected method.
    - **Context Menus**: Right-click `.scdef`/`.scxml` files to convert/regenerate; right-click `StateChartExt` nodes to export/import/open `.scdef`.
    - **External Editor**: `.scdef` files open in the configured external text editor; `.scxml` files open in a configurable SCXML editor.
- **Runtime Visualization**: Overlays active state names on the game viewport with `runtime_visualization`.
- **Runtime History**: Tracks state enter/exit events with timestamps (viewable in the inspector).
- **Debug Tools**: Toggleable logs for state transitions (`debug_log`) and event reception (`debug_event`).

## SCXML Integration

Full round-trip SCXML import/export with external editors like Qt Creator.

- **Advanced Round-Trip**: Metadata, custom attributes, namespaced tags (`qt:editorinfo` etc.), and state UIDs are fully preserved.
- **History States**: SCXML `<history>` tags (`shallow`/`deep`) mapped to `HistoryState`.
- **Guard Conditions**: `cond` attributes parsed into compound guard trees (In, &&, ||, !, expressions) and back.
- **Entry/Exit Actions**: `<onentry>`/`<onexit>` with `<send>` and `<assign>` elements are preserved.
- **Event Delay**: `event@delay` syntax (e.g. `shoot@500` for 500ms delay).
- **Multiple Events**: Space-separated events on import split into individual `Transition` nodes; identical transitions merged back on export.
- **Descriptive Naming**: Auto-generated node names (e.g. `JumpToAirborne`) for unnamed transitions.
- **Custom Namespaces**: All `xmlns` declarations captured and restored.
- **Auto-generated .scdef**: Importing an SCXML file automatically generates a corresponding `.scdef` and `.gd` file.
- **Connection Preservation**: User signal connections are saved and restored across re-imports using UIDs.

## Installation

- Ensure you have [godot-statecharts](https://github.com/derkork/godot-statecharts) installed and enabled in your project.
- Copy the `addons/godot-statecharts_ext` folder into your project's `addons/` directory.
- Enable the plugin in **Project Settings > Plugins**.

## Usage Guide

### Define your StateChart (.scdef)

Create a `.scdef` file to define your state chart's interface. Documentation comments (`##`) are carried over to the generated code.

`player.scdef`:
```text
class PlayerSC

## Triggered when the player jumps
event jump
event crouch
event health_changed

# Initial value 100.0, triggers health_changed only on actual change
param health float = 100.0 { health_changed: true }

# Exists only during "Move" state, triggers speed_changed on change
param speed float = 5.0 { local: Move, speed_changed: true }

param ammo int = 10
param items array = []
param stats dict = {}
event speed_changed
```

Saving the file automatically generates `player.gd` with typed proxies.

### Supported Types

`float`, `int`, `bool`, `string`, `vector2`, `vector2i`, `vector3`, `vector3i`, `vector4`, `vector4i`, `rect2`, `rect2i`, `plane`, `quaternion`, `aabb`, `basis`, `transform2d`, `transform3d`, `projection`, `color`, `stringname`, `nodepath`, `rid`, `object`, `callable`, `signal`, `array`, `dict`, `dictionary`, `variant`.

### Attach and Configure

Attach the generated script (e.g. `player.gd`) to a node (replacing the standard `StateChart` node).

Inspector options:
- **Debug Log / Debug Event**: Toggle state transition / event logs.
- **Runtime Visualization**: Overlays the active state chain on the viewport.
- **Exclude Unused / Unknown Event Warnings**: Per-event toggles.
- **Check Errors / Clear All Metadata**: Buttons for validation and cleanup.
- **Export/Import SCXML**: Buttons and a drag-and-drop zone.
- **p/ group**: Direct parameter editing.

### Access in Code

```gdscript
@onready var sc: PlayerSC = $StateChart

func _ready():
    print(sc.p.health) # 100.0
    sc.p.health = 90.0    # triggers health_changed
    sc.e.jump.call()

    if sc.p.has("speed"):
        print(sc.p.speed)

func take_damage(amount: float):
    sc.p.health -= amount
    if sc.p.health <= 0:
        sc.e.die.call()
```

### Local Parameters

`param speed float = 5.0 { local: Move, speed_changed: true }` — automatically registered on entering `Move`, removed on exit.

Ad-hoc local params:
```gdscript
sc.local().set_param(PlayerSC.Param.speed, 10.0)
# Auto-erased when the current active state exits
```

### Events with Delay

Events can include a delay using the `event@delay_ms` syntax in SCXML. In code, use the `delay_in_seconds` property on `Transition` nodes.

## Utilities (STAux)

```gdscript
# Bind multiple signals to events at once
STAux.bind_signals_to_events(sc, {
    button.pressed: PlayerSC.Event.jump,
    timer.timeout: PlayerSC.Event.crouch
})

# Type-safe collection operations
STAux.st_add_array(sc, PlayerSC.Param.items, "Sword")
STAux.st_insert_dict(sc, PlayerSC.Param.stats, "strength", 10)
STAux.st_init_dict(sc, PlayerSC.Param.stats)
STAux.st_init_array(sc, PlayerSC.Param.items)
STAux.st_add_value(sc, PlayerSC.Param.health, -10.0) # returns [prev, new]

# Check if a state is active
STAux.is_state_active(sc, $MoveState)

# Dump all current params (useful for save/debug)
var snapshot := STAux.st_get_all_params_as_dict(sc)
```

## Advanced: Manual Definition

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

## License

This project is licensed under the MIT License - see the LICENSE file for details.
