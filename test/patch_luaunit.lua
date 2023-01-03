-- print(lfs.currentdir())

local SCRIPT_NAME = "patch_luaunit.lua"

local INFO = [[
This is %s .

This small script patches
the LuaUnit source file "%s" to "%s".

The aim is, that the internal function failure() for its extra_msg_or_nil 
argument instead of a string can also recieve a function,
that creates the error message /on demand/.]]

local ORG_FILENAME = "luaunit.lua"
local PATCHED_FILENAME = "luaunit-patched.lua"

local BEGIN_PATCH_AT_PATTERN =
        "local%s+function%s+failure%s*%("
local END_PATCH_AT_PATTERN =
        "^end" -- the aligning to the line start is important

local PATCH = [[
local function failure(main_msg, extra_msg_or_nil, level)
    -- raise an error indicating a test failure
    -- for error() compatibility we adjust "level" here (by +1), to report the
    -- calling context
    -- BEGIN ACTUAL PATCH
    if rawequal(type(extra_msg_or_nil), "function") then
        extra_msg_or_nil = extra_msg_or_nil()
    end
    -- END ACTUAL PATCH
    local msg
    if type(extra_msg_or_nil) == 'string' and extra_msg_or_nil:len() > 0 then
        msg = extra_msg_or_nil .. '\n' .. main_msg
    else
        msg = main_msg
    end
    error(M.FAILURE_PREFIX .. msg, (level or 1) + 1 + M.STRIP_EXTRA_ENTRIES_IN_STACK_TRACE)
end
]]



local function print_info()
    print()
    print(string.format(INFO,
                        SCRIPT_NAME, ORG_FILENAME, PATCHED_FILENAME))
    print()
end

local function write_patch(patch_fh)
    local date_time_str =
            os.date("%Y-%m-%d %H:%M:%S %z")-- alternatively: "%F %T %z"
    patch_fh:write(string.format("-- BEGIN PATCH by %s at %s\n",
                                 SCRIPT_NAME, date_time_str))
    patch_fh:write(PATCH)
    patch_fh:write(string.format("-- END PATCH by %s at %s\n",
                                 SCRIPT_NAME, date_time_str))
end

local function patch(org_fh, patch_fh)
    local never_patched = true
    local in_failure_func = false
    
    for org_line in org_fh:lines("L") do
        if in_failure_func then
            if string.match(org_line, "^end") then
                write_patch(patch_fh)
                in_failure_func = false
                never_patched = false
            end
        else
            if string.match(org_line, BEGIN_PATCH_AT_PATTERN) then
                in_failure_func = true
            else
                patch_fh:write(org_line)
            end
        end
    end
    
    if never_patched then
        error("ERROR: did not patched"
            .."\nERROR: probably because the BEGIN_PATCH_AT_PATTERN"
            .." is not up-to-date")
    end
end

local function main()
    print_info()
    
    local org_fh = io.open(ORG_FILENAME, "r")
    if not org_fh then
        error(string.format("ERROR: original file \"%s\" not found.", 
                            ORG_FILENAME))
    end
    
    local patch_fh = io.open(PATCHED_FILENAME, "w")
    
    patch(org_fh, patch_fh)
    
    org_fh:close()
    patch_fh:close()
end

main()
