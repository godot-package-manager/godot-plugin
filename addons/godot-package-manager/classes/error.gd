
class_name GPMError

enum Code {
    NONE = 0,
    GENERIC,

    #region Http requests

    INITIATE_CONNECT_TO_HOST_FAILURE,
    UNABLE_TO_CONNECT_TO_HOST,

    UNSUCCESSFUL_REQUEST,
    MISSING_RESPONSE,
    UNEXPECTED_STATUS_CODE,

    GET_REQUEST_FAILURE,

    #endregion

    #region Config

    FILE_OPEN_FAILURE,
    PARSE_FAILURE,
    UNEXPECTED_DATA,

    NO_PACKAGES,
    PROCESS_PACKAGES_FAILURE

    REMOVE_PACKAGE_DIR_FAILURE

    #endregion

    #region GPMAdvancedExpression

    MISSING_SCRIPT,
    BAD_SCRIPT_TYPE,
    SCRIPT_COMPILE_FAILURE,

    #endregion
}

var _error: int
var _description: String

func _init(error: int, description: String = "") -> void:
    _error = error
    _description = description

func _to_string() -> String:
    return "Code: %d\nName: %s\nDescription: %s" % [_error, error_name(), _description]

func error_code() -> int:
    return _error

func error_name() -> int:
    return Code.keys()[_error]

func error_description() -> String:
    return _description