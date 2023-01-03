local lu  = require('luaunit')

function testPass()
    lu.assertEquals({1, 2, 3}, {1, 2, 3})
end

function testFail()
    lu.assertEquals({1, 2, 3}, {1, 2, 4})
end

os.exit( lu.LuaUnit.run())
