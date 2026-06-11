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
