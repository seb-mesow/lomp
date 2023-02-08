local err_msg = {}

---@class err_msg
---@field package str string string of the error message
local __err_msg = {}

local __err_msg_meta = { __index = __err_msg }

--- constructs an empty `err_msg`, which indicates no error
---
---@nodiscard
---@return err_msg new_err_msg empty `err_msg`
function err_msg.new()
    return setmetatable({}, __err_msg_meta) --[[@as err_msg]]
end

---@private
---@param self err_msg
---@param str string
function __err_msg:__append(str)
    if rawequal(self.str, nil) then
        self.str = str
    else
        self.str = self.str.."\n\n"..str
    end
end

--- appends a string to the error message on a new line
--- 
---@param self err_msg
---@param str_or_err_msg string|err_msg|nil another string for the error message
function __err_msg:append(str_or_err_msg)
    if rawequal(str_or_err_msg, nil) then
        return
    end
    ---@cast str_or_err_msg -nil
    if rawequal(getmetatable(str_or_err_msg), __err_msg_meta) then
        ---@cast str_or_err_msg err_msg
        str_or_err_msg = str_or_err_msg.str
    end
    ---@cast str_or_err_msg -err_msg
    self:__append(str_or_err_msg)
end

--- appends a formatted string to the error message on a new line
--- 
---@param self err_msg
---@param fmt string printf format for annother string for the error message
---@param ... any arguments to the printf format
function __err_msg:appendf(fmt, ...)
    self:__append(string.format(fmt, ...))
end

--- returns whether the `err_msg` represents an error or not
---
---@param self err_msg
---
---@nodiscard
---@return boolean has_error whether the `err_msg` represents an error
function __err_msg:has_error()
    return not rawequal(self.str, nil)
end

--- returns whether the `err_msg` represents an error or not
---
--- Usage: (or similar)
---```lua
---local em = err_msg.new()
---...
---em:append("error message")
---...
---assert( em:pass_to_assert() )`
---```
---
---@param self err_msg
---
---@nodiscard
---@return boolean has_succeeded whether the `err_msg` represents *no* error
---@return err_msg|nil err_msg concrete error message if has failed
function __err_msg:pass_to_assert()
    if rawequal(self.str, nil) then
        return true
    end
    return false, self
end

--- returns the `err_msg` known to represent an error
---
--- Usage: (or similar)
---```lua
---function may_failing_func()
---    ...
---    if <error condition> then
---        local em = err_msg.new()
---        em:append("error message")
---        return em:pass_error_to_assert()
---    end
---    ...
---end
---```
---
---@param self err_msg
---
---@nodiscard
---@return false has_succeeded whether the `err_msg` represents *no* error, always `false`
---@return err_msg err_msg concrete error message if has failed
function __err_msg:pass_error_to_assert()
    if rawequal(self.str, nil) then
        local em = err_msg.new()
        em:append("err_msg at err_msg:pass_error_to_assert() does not represent an error")
        return em:pass_error_to_assert()
    end
    return false, self
end

--- converts the `err_msg` to a string
--- 
---@param self err_msg
function __err_msg_meta:__tostring()
    return self.str
end

return err_msg
