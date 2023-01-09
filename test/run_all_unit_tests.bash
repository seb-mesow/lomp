#!/usr/bin/env bash 

# Usage:
# $ cd <repository>
# $ ./test/run_all_unit_tests.bash

declare m_main___repo_root_dirpath="$PWD"

# must end with dir sep !
declare m_main___repo_test_dirpath="${m_main___repo_root_dirpath}/test/" \
         m_main___repo_src_dirpath="${m_main___repo_root_dirpath}/src/" \
        m_main___repo_root_dirpath="${m_main___repo_root_dirpath}/"

# ----- copied from lua-wrapper-shell/modules/auxillary.bash
function __aux___declare___m_aux____root_path_win() {
    declare -g m_aux____root_path_win="$(cygpath -w '/')"
}

# faster than cygpath (and a bit more correct)
# $1 - ret str var name
# $2 - absolute path in unix style to convert
function convert_path_to_win() {
    if [[ "$1" != "l_aux___ret_path" ]] ; then
        local -n l_aux___ret_path="$1"
    fi
    if [[ "$2" =~ ^'/' ]] ; then
        if [[ "$2" =~ ^'/'([a-zA-Z])'/' ]] ; then
            l_aux___ret_path="${BASH_REMATCH[1]@U}:${2:2}"
        elif [[ "$2" =~ ^'/'([a-zA-Z])$ ]] ; then
            l_aux___ret_path="${BASH_REMATCH[1]@U}:"
        else
            if [[ ! -v m_aux____root_path_win ]] ; then
                __aux___declare___m_aux____root_path_win
            fi
            l_aux___ret_path="${m_aux____root_path_win}${2:1}"
        fi
    else
        l_aux___ret_path="$2"
    fi
    l_aux___ret_path="${l_aux___ret_path//'/'/'\'}"
}
# ----- end copied from lua-wrapper-shell/modules/auxillary.bash

# $1 - env var name
# uses from calling context:
# l_main___prepend_LUA_PATH
function __main__export_prepended_lua_path_env_var() {
    local -n l_env_var="$1"
    export "$1"="${l_main___prepend_LUA_PATH};${l_env_var}"
}

function __main() {
    if declare -p MSYSTEM &> /dev/null ; then
        # MSYS2 detected
        convert_path_to_win m_main___repo_test_dirpath "$m_main___repo_test_dirpath"
        convert_path_to_win m_main___repo_src_dirpath  "$m_main___repo_src_dirpath"
        convert_path_to_win m_main___repo_root_dirpath "$m_main___repo_root_dirpath"
    fi
    
    m_main___repo_test_dirpath="${m_main___repo_test_dirpath}/?.lua"
    m_main___repo_src_dirpath="${m_main___repo_src_dirpath}/?.lua"
    m_main___repo_root_dirpath="${m_main___repo_root_dirpath}/?.lua"
    
    local l_main___prepend_LUA_PATH="\
${m_main___repo_test_dirpath};\
${m_main___repo_src_dirpath};\
${m_main___repo_root_dirpath}"
    
    __main__export_prepended_lua_path_env_var LUA_PATH
    __main__export_prepended_lua_path_env_var LUA_PATH_5_3
    __main__export_prepended_lua_path_env_var LUA_PATH_5_4
    
    cd test
    lua run_all_unit_tests.lua # must be the very last command to execute for proper exit status
}

__main "$@"
