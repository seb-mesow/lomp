-- TODO get rid of copied message module
-- TODO instead use debugging tools

local msg = {}

-- ########## Message Auxillary ##########

local function __concat_to_string_func_default(k, v)
    -- return str_util.sprint_value(v)
    return tostring(v)
end

local function __concat(table, sep, to_string_func)
    if type(sep) ~= "string" then
        sep = ", "
    end
    if type(to_string_func) ~= "function" then
        to_string_func = __concat_to_string_func_default
    end
    local str
    for k, v in pairs(table) do
        if str then
            str = str..sep..to_string_func(k, v)
        else
            str = to_string_func(k, v)
        end
    end
    return str
end

-- ########## Messages ##########

local function __msg(line_prefix, ...)
    line_prefix = line_prefix..": "
    local msg_str = __concat({...}, "\n")
    msg_str = string.gsub(msg_str, "\n", "\n"..line_prefix)
    return line_prefix..msg_str
end

local callstack_indention = string.rep(" ", 8)

local function __msg_callstack(line_prefix, ...)
    line_prefix = line_prefix..": "
    local msg_str = __concat({...}, "\n")
    local callstack_str = string.gsub(debug.traceback("\n", 4), "\t", callstack_indention)
    msg_str = msg_str..callstack_str
    msg_str = string.gsub(msg_str, "\n", "\n"..line_prefix)
    return line_prefix..msg_str
end

-- This version of LuaTeX does not seem to have the warn basic function yet
local __warn  = warn or print

function msg.log(...)
    print(__msg("Log", ...))
end
function msg.info(...)
    print(__msg("Info", ...))
end
function msg.warn(...)
    __warn(__msg("WARNING", ...))
end
function msg.warn_callstack(...)
    __warn(__msg_callstack("WARNING", ...))
end
function msg.error(...)
    return error("\n"..__msg_callstack("ERROR", ...), 0)
end

function msg.logf(fmt, ...)
    msg.log(string.format(fmt, ...))
end
function msg.infof(fmt, ...)
    msg.info(string.format(fmt, ...))
end
function msg.warnf(fmt, ...)
    msg.warn(string.format(fmt, ...))
end
function msg.warnf_callstack(fmt, ...)
    msg.warn_callstack(string.format(fmt, ...))
end
function msg.errorf(fmt, ...)
    return msg.error(string.format(fmt, ...))
end

-- function msg.log_func_start(funcname, ...)
--     msg.logf("%s(%s) start", funcname, debug.sprint_values(...))
-- end

-- function msg.log_func_end(funcname, ...)
--     msg.logf("%s(%s) end", funcname, debug.sprint_values(...))
-- end

-- default error handler
function msg.msgh(err)
    return __warn(err)
end

return msg
