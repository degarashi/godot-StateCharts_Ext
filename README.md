# Godot StateCharts Extension (StateChartExt)

A Godot plugin that extends the [godot-statecharts](https://github.com/derkork/godot-statecharts) library.
This extension provides a statically typed wrapper to make state machine parameters and events safer, more discoverable, and easier to use through proxy objects.

## Features

- **Static Type Safety**: Define your events and parameters as static variables in inner classes for IDE completion and compile-time checks.
- **Proxy-based API**: 
    - `sc.e.event_name.call()`: Dispatch events with a clean, functional syntax.
    - `sc.p.param_name = value`: Access and modify parameters directly with automatic type checking.
- **Auto-Notifications**: Parameters can automatically trigger events when their values change.
- **State-Local Parameters**: Easily manage parameters that exist only while a specific state is active.
- **Initial Value Support**: Specify initial values for parameters directly in the definition file.
- **Editor Integration**: Validation logic that provides configuration warnings in the Godot editor if names or types don't match.
- **Inspector Display**: View and edit StateChart parameters directly in the Godot Inspector (useful for real-time debugging).
- **Transition Event Dropdown**: Avoid typing event names manually as strings on `Transition` nodes. The inspector automatically displays a dropdown list populated with all events defined in your `StateChartExt`.


## Installation

- Ensure you have [godot-statecharts](https://github.com/derkork/godot-statecharts) installed and enabled in your project.
- Copy the `addons/godot-statecharts_ext` folder into your project's `addons/` directory.
- Enable the "Godot StateCharts Extension" plugin in **Project Settings > Plugins**.

## Usage Guide

### Define your StateChart (Auto-generation)

You can now use a simple text-based definition file (`.scdef`) to automatically generate the GDScript boilerplate.

Create a file named `player.scdef`:
```text
class PlayerSC

event jump
event crouch
event health_changed

# Initial value 100.0, triggers health_changed on change
param health float = 100.0 { health_changed: true }

# Exists only during "Move" state AND triggers speed_changed on change
param speed float = 5.0 { local: Move, speed_changed: true }

param ammo int = 10
event speed_changed
```

When you save this file, the plugin will automatically generate/update `player.gd`.

---

### Alternative: Manual Definition
Create a new script that extends `StateChartExt`. Define your events and parameters inside inner classes:

```gdscript
@tool
class_name PlayerSC extends StateChartExt

# Define Events
class Event:
    extends StateChartExt.Event
    static var jump := e()
    static var attack := e()
    static var health_changed := e()

# Define Parameters
class Param:
    extends StateChartExt.Param
    # p(type, notify_map, initial_value, local_state_name)
    static var health := p(TYPE_FLOAT, { PlayerSC.Event.health_changed: true }, 100.0)
    static var speed := p(TYPE_FLOAT, {}, 5.0, &"Move")

# Link them to the StateChart
func get_sc_info() -> SCInfo:
    return SCInfo.new(Param, Event)
```

### Attach and Configure

Attach your script to a node in your scene (replacing the standard `StateChart` node). The extension will automatically discover your definitions.

When configuring `Transition` nodes, the inspector's `event` property will automatically display a dropdown populated with all events defined in your `StateChartExt`, making configuration easy and preventing typos.


### Access in Code

Use the `e` (events) and `p` (parameters) proxies for a clean API:

```gdscript
@onready var sc: PlayerSC = $StateChart

func _ready():
    # Non-local parameters are auto-initialized with their initial values
    print(sc.p.health) # 100.0
    
    # Set a parameter (triggers auto-events)
    sc.p.health = 90.0
    
    # Parameters can also be modified directly in the Inspector (under p/ category)

    # Safe check before access
    if sc.p.has("speed"):
        print(sc.p.speed)

func take_damage(amount: float):
    sc.p.health -= amount
    if sc.p.health <= 0:
        sc.e.die.call()
```

### Local Parameters

If you specify `{ local: StateName }` in `.scdef`, the parameter is **automatically** registered with its initial value when entering that state and automatically removed when leaving.

To manually set dynamic local parameters:
```gdscript
# These will be automatically erased from the StateChart when exiting the current state
sc.local().set_param(PlayerSC.Param.speed, 10.0)
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
