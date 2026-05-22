# Godot StateCharts Extension (StateChartExt)

A Godot 4.6+ plugin that extends the [godot-statecharts](https://github.com/derkork/godot-statecharts) library.
This extension provides a statically typed wrapper to make state machine parameters and events safer, more discoverable, and easier to use through proxy objects and automatic code generation.

## Features

- **Static Type Safety**: Define your events and parameters in a simple `.scdef` file to automatically generate GDScript boilerplate with explicit members for maximum IDE completion.
- **Proxy-based API**: 
    - `sc.e.event_name.call()`: Dispatch events with a clean, functional syntax.
    - `sc.p.param_name = value`: Access and modify parameters directly with automatic type checking.
- **Auto-Notifications**: Parameters can automatically trigger events when their values change (customizable with change-detection logic).
- **State-Local Parameters**: Manage parameters that exist only while a specific state is active. They are automatically initialized on entry and cleaned up on exit.
- **Initial Value Support**: Specify initial values for parameters directly in the definition file.
- **Editor Integration**: 
    - **Configuration Warnings**: Real-time validation for event names, parameter types, and expression syntax.
    - **Inspector Integration**: View and edit StateChart parameters directly in the Godot Inspector under the `p/` group.
    - **Transition Event Dropdown**: Automatic dropdown for the `event` property on `Transition` nodes, populated from your definitions.
    - **Check Errors Button**: A handy button in the inspector to trigger a full validation pass.
- **Debug Tools**: Toggleable logs for state transitions (`debug_log`) and event reception (`debug_event`).

## Installation

- Ensure you have [godot-statecharts](https://github.com/derkork/godot-statecharts) installed and enabled in your project.
- Copy the `addons/godot-statecharts_ext` folder into your project's `addons/` directory.
- Enable the "Godot StateCharts Extension" plugin in **Project Settings > Plugins**.

## Usage Guide

### Define your StateChart (.scdef)

Use a `.scdef` file to define your state chart's interface. Documentation comments (`##`) will be carried over to the generated code.

Create a file named `player.scdef`:
```text
class PlayerSC

## Triggered when the player jumps
event jump
event crouch
event health_changed

# Initial value 100.0, triggers health_changed only when the value actually changes
param health float = 100.0 { health_changed: true }

# Exists only during "Move" state AND triggers speed_changed on change
param speed float = 5.0 { local: Move, speed_changed: true }

param ammo int = 10
param items array = []
param stats dict = {}
event speed_changed
```

When you save this file, the plugin automatically generates `player.gd`.

### Attach and Configure

> Attach the generated script (e.g., `player.gd`) to a node in your scene (replacing the standard `StateChart` node).
> In the inspector, you can toggle `Debug Log` or `Debug Event` for troubleshooting.
> If you have unused events or want to ignore certain unknown events, use the `Exclude Unused Event` or `Exclude Warn Unknown Events` lists.

### Access in Code

The generated `e` (events) and `p` (parameters) proxies provide a first-class coding experience:

```gdscript
@onready var sc: PlayerSC = $StateChart

func _ready():
    # Parameters are auto-initialized
    print(sc.p.health) # 100.0
    
    # Set a parameter (triggers auto-notifications)
    sc.p.health = 90.0
    
    # Events are called as methods
    sc.e.jump.call()

    # Check for parameter existence (useful for local parameters)
    if sc.p.has("speed"):
        print(sc.p.speed)

func take_damage(amount: float):
    sc.p.health -= amount
    if sc.p.health <= 0:
        sc.e.die.call()
```

### Local Parameters

Parameters defined with `{ local: StateName }` are **automatically** registered when entering that state and removed when leaving.

You can also use the `local()` helper for ad-hoc local parameter management:
```gdscript
# These will be automatically erased when exiting the current active state
sc.local().set_param(PlayerSC.Param.speed, 10.0)
```

## Utilities (STAux)

The `STAux` class provides additional helpers for common tasks:

```gdscript
# Bind multiple signals to events at once
STAux.bind_signals_to_events(sc, {
    button.pressed: PlayerSC.Event.jump,
    timer.timeout: PlayerSC.Event.crouch
})

# Type-safe collection manipulation
STAux.st_add_array(sc, PlayerSC.Param.items, "Sword")
STAux.st_insert_dict(sc, PlayerSC.Param.stats, "strength", 10)
```

## Advanced: Manual Definition

If you prefer not to use `.scdef`, you can extend `StateChartExt` manually:

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

## License

This project is licensed under the MIT License - see the LICENSE file for details.
