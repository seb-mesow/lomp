-- Usage:
--  $ cd tests
--  $ <set env var LUA_PATH=<repository>/test/?.lua;<LUA_PATH>
--  $ <lua-intepreter> run_all_unit_tests.lua

-- Unfortunately as of January 2023 neither the rocks "environ" nor "setenv" are buildable with MSYS2 on Windows.
-- Thus we must rely, that the caller of this script sets the env vars accordingly.

-- requires luafilesystem
local lfs = require("lfs")

---@param val_to_log any string to print
local function log(val_to_log)
    print("RUN UNIT TESTS: "..tostring(val_to_log))
end

---@class test_result
--- 
--- collects information about the result of a unit test
---
---@field filename string filename of the unit test
---@field kind_of_termination "exit"|"signal" how the unit test terminated
---@field exit_code? integer exit code, only defined if `kind_of_termination == "exit"`
---@field signal_num? integer number of signal, that interrupted the unit test, only defined if `kind_of_termination == "signal"`

local function main()
    local lua_interpreter_name = "lua"
    -- get interpreter name
    local i = 0
    while arg[i] do
        i = i + 1
    end
    if i < 0 then
        lua_interpreter_name = arg[i-1]
    end

    ---@type test_result[]
    local failed_test_results = {}

    -- iterate over files
    for filename in lfs.dir(lfs.currentdir()) do
        if  (filename ~= ".") 
        and (filename ~= "..")
        and string.match(filename, "^test_.+%.lua$")
        then
            local cmdline = lua_interpreter_name.." "..filename
            log("$ "..cmdline)
            local was_sucessfull, kind_of_termination, code = os.execute(cmdline)
            ---@type test_result
            local test_result = {
                filename = filename ;
                ---@diagnostic disable-next-line: assign-type-mismatch -- wrong return type of os.execute in language server
                kind_of_termination = kind_of_termination ;
            }
            if kind_of_termination == "exit"  then
                test_result.exit_code = code
            else
                test_result.signal_num = code
            end
            if not was_sucessfull then
                log(filename.." FAILED")
                table.insert(failed_test_results, test_result)
            end
            print()
        end
    end

    -- summarize results
    if #failed_test_results == 0 then
        log("All unit tests were successful. :-) ")
    else
        log("The following unit tests FAILED:")
        for _, test_result in ipairs(failed_test_results) do
            log("    "..test_result.filename)
        end
        log(":-(")
    end
    
    -- return proper exit status
    os.exit(#failed_test_results)
end

main()
