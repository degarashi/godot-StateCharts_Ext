class_name StateChartConstants
extends Object

# ------------- [Constants] -------------
const CAT := "state_chart"
const PATH_SEPARATOR := "/"
const SCDEF_EXTENSION := "scdef"
const GD_EXTENSION := "gd"
const SCXML_PATH_META_KEY := "statechart_ext__scxml_path"

const ACTION_TYPE_SEND := "send"
const ACTION_TYPE_ASSIGN := "assign"
const META_ON_ENTRY := "statechart_ext__onentry"
const META_ON_EXIT := "statechart_ext__onexit"

## Map from scdef type names to Godot TYPE_ constant names
const TYPE_MAP: Dictionary[String, String] = {
	"float": "TYPE_FLOAT",
	"int": "TYPE_INT",
	"bool": "TYPE_BOOL",
	"string": "TYPE_STRING",
	"vector2": "TYPE_VECTOR2",
	"vector2i": "TYPE_VECTOR2I",
	"vector3": "TYPE_VECTOR3",
	"vector3i": "TYPE_VECTOR3I",
	"vector4": "TYPE_VECTOR4",
	"vector4i": "TYPE_VECTOR4I",
	"rect2": "TYPE_RECT2",
	"rect2i": "TYPE_RECT2I",
	"plane": "TYPE_PLANE",
	"quaternion": "TYPE_QUATERNION",
	"aabb": "TYPE_AABB",
	"basis": "TYPE_BASIS",
	"transform2d": "TYPE_TRANSFORM2D",
	"transform3d": "TYPE_TRANSFORM3D",
	"projection": "TYPE_PROJECTION",
	"color": "TYPE_COLOR",
	"stringname": "TYPE_STRING_NAME",
	"nodepath": "TYPE_NODE_PATH",
	"rid": "TYPE_RID",
	"object": "TYPE_OBJECT",
	"node": "TYPE_OBJECT",
	"resource": "TYPE_OBJECT",
	"callable": "TYPE_CALLABLE",
	"signal": "TYPE_SIGNAL",
	"array": "TYPE_ARRAY",
	"dict": "TYPE_DICTIONARY",
	"dictionary": "TYPE_DICTIONARY",
	"variant": "TYPE_NIL"
}

## Map from scdef type names to GDScript type annotations
const GD_TYPE_MAP: Dictionary[String, String] = {
	"float": "float",
	"int": "int",
	"bool": "bool",
	"string": "String",
	"vector2": "Vector2",
	"vector2i": "Vector2i",
	"vector3": "Vector3",
	"vector3i": "Vector3i",
	"vector4": "Vector4",
	"vector4i": "Vector4i",
	"rect2": "Rect2",
	"rect2i": "Rect2i",
	"plane": "Plane",
	"quaternion": "Quaternion",
	"aabb": "AABB",
	"basis": "Basis",
	"transform2d": "Transform2D",
	"transform3d": "Transform3D",
	"projection": "Projection",
	"color": "Color",
	"stringname": "StringName",
	"nodepath": "NodePath",
	"rid": "RID",
	"object": "Object",
	"node": "Node",
	"resource": "Resource",
	"callable": "Callable",
	"signal": "Signal",
	"array": "Array",
	"dict": "Dictionary",
	"dictionary": "Dictionary",
	"variant": "Variant"
}


# ------------- [Defines] -------------
## Local parameter display configuration
class LocalParam:
	const PREFIX := "[L: "
	const SUFFIX := "] "


class PropGroup:
	const PARAM := "p/"
	const EXC_UNUSED := "exc_unused/"
	const EXC_UNKNOWN := "exc_unknown/"
	const HISTORY := "runtime_history/"
