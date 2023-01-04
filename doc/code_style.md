# Code Style

## Files
- All files are encoded in UTF-8.
- Lines are terminated by a line feed (LF) (Unix-style)
  - Thus every file must end with an "empty line".

## Code Formatting

- 4 spaces for one intention
- All code is **formatted manually**.

## Identifiers
- There is no distinction between module-private, class-private and class-protected.
- In general *public* tables, methods, functions must not begin with an underscore.
- In general *private* Tables, variables, methods, functions must begin with two underscores.
- *private static variables* should by constants.
  Their identifiers should consists only of uppercase characters and the underscore.
  As an exception to those state prior their identifiers should *not* begin with an underscore.
- The identifiers of datafields should be as short as possible and may not begin with an underscore.

**TODO most of those module-private static variables are captured/copied as upvalues to the methods/functions**

The identifier `self` is reserved for
- the current table/object to operate on / whose data fields are accessed resp. changed
- or the first operand of a method/function

The identifier `other` is reserved for the second operand of a method/function

## Class Modules
There should be one module per class.


Each class module defines three tables with their names *derived* from the module name
- `module_name`
  - provides the *public and privtae static* methods/functions
    - especially the constructor, whose identifier must begin with `new`
  - declared as<br>
   `local __module_name = {}`
  - These methods/functions are declared with<br>
    `function module_name.func_identifer(...)`
  - This table is `return`ed at the very end of the module.
- `__module_name`
  - provides the *public and private member* methods/functions (excluding metamethods)
  - declared as<br>
   `local __module_name = {}`
  - The member methods/functions are declared with<br>
    `function __module_name:func_identifer(...)` .<br>
    This automatically provides the parameter `self` which refers to the object to operate on.
- `__module_name___meta`
  - metatable of any object of this class
  - provides the (always) *public* metamethods for the operands (which are considered *members*)
  - The field `__index` of this table refers to `__module_name`.
    Thus the member methods/functions are accessible via a constructed object.
  - declared *after* the declaration of the `__module_name` table as<br>
    `local __module_name___meta = { __index = __module_name }`
  - We can consider every table with this metatable as an object of this class. (**type checking**)
  - Metamethods with one operand are declared with<br>
    `function __module_name___meta:__meta_method()` .<br>
    This automatically provides the parameter `self` which refers to the operand.
  - metamethods with two or more operands are declared with<br>
    `function __module_name___meta:__meta_method(other, ...)` .<br>
    This automatically provides the parameter `self` which refers to the 1st operand.
    This provides the parameter `other` which refers to the 2nd operand.

No methods/functions should be defined outside of any of these three tables.

Data fields of an object can be accessed by any method or function definied in the module.
Thus datafields must not be public.

The **construction** of an object of a class follows the following pattern:
```lua
function module_name.new(...)
    ...
    local self = setmetatable({}, __module_name___meta)
                 -- declares the table self as an object of class module_name
    ...
    self.datafield = value
    ...
    return self
end
```
