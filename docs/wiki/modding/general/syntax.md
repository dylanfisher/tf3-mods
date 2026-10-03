---
title: Syntax
page_id: modding:general:syntax
source: https://wiki.transportfever3.com/doku.php?id=modding:general:syntax
---

# Syntax

This page gives a brief introduction into the used scripting language.
See the documentation of [resource types](../../modding/general/resourcetypes.md) for the internal structures of files.

## JSON

The static [JavaScript Object Notation](https://en.wikipedia.org/wiki/JSON) is used for the header files of mods to ensure a broken mod definition does not prevent the game from starting.

More details on the syntax rules for JSON can be found at [W3 Schools](https://www.w3schools.com/js/js_json.asp).

## LUA & Teal

For all scripts and the other external resources which are not hard coded into the game binary, the [LUA](https://en.wikipedia.org/wiki/Lua) language is used. LUA is a script language which is used by many programs to offer extendability and customization. To assist coding and reduce potential for errors, scripts usually use the [Teal](https://teal-language.org/) dialect for lua. It provides static typing annotations to better specify the data types of function parameters and arrays.

The most common syntax structures used for Transport Fever 3 are described briefly below. A full reference of the LUA syntax is available at the [website of LUA](https://www.lua.org/manual/5.2/).

Files with LUA content are plain textfiles and can be edited with any text editor. Common used editors are [Notepad++](https://notepad-plus-plus.org) and [Visual Studio Code](https://code.visualstudio.com/) which both support syntax highlighting of LUA code. The later also supports syntax highlighting for Teal.

### Functions

Functions can be called by their name from other functions or the game engine.

```lua
local function functionname(parametername1, parametername2)
  -- code
  return resultname
end
```

Functions are defined by the keyword `function` followed by a name for the function.
In brackets, some `parameters` may be required too. Then they can be called inside the function code below. If no parameters are needed, the brackets are left empty. If the function should return a result, the `return` keyword is used. The `end` marks the end of the function. All code between `function` and `end` belongs to the function.

An exemplaric function call looks like this:

```lua
multiply(5, 21)
```

When working with Teal, the parameter and return value types are assigned with `: <type>`.

```lua
local function functionname(parametername1: number, parametername2: number): number
  -- code
  return resultname
end
```

### Types

The basic types used in Teal are:

- `any` undefined type similar to lua default behavior
- `nil`
- `boolean`
- `integer` positive and negative full numbers
- `number` any decimal number.
- `string`

### Variables

Variables can be used to temporarily store some values or data structs in code.

```lua
--define variable
local variablename
 
--define and write variable
local variablename = -- content
 
--override variable
variablename = -- new content
```

To define a variable, the keyword `local` followed by an identifier is used. Transport Fever 3 does not support global variables, thus `local` is mandatory!
A variable can be filled with content by using the keyword `=` followed by the content.
To read content from a variable, simply call the variable by its name.

As with the functions, variables are typed in Teal:

```lua
--define variable
local variablename: number
```

### Data Structs / Arrays

In many places of Transport Fever 3, data structs are used to store more than single values or key-value paired contents. They are called **arrays** or **tables** too.

#### Structs with Keys

Most of the configurational data in Transport Fever uses keys for the different properties.

```lua
local structname = {
  key1 = value1,
  key2 = value2,
  key3 = value3,
  -- ...
}
```

These values later can be called by using `structname.keyname`, e.g. `structname.key2`.
To add a new key at a later point, use `structname[key] = value`.

In Teal, these structs are defined as a `record`:

```lua
local record ExampleParams
	record ExampleChildRecord
		exampleChildValue : number
	end
 
	exampleFunction : function(paramName: number) : number
	exampleValue : string
end
```

These records may then be referenced as types for parameters, return types or other data structs.

#### Structs without Keys

In many cases, the storage of a list of similar contents is needed.

```lua
local array = { value1, value2, value3 }
```

These values later can be called by using an index number. These structs are one-indexed, meaning the first index is 1. The total number of values can be gathered by using `#variablename`. In the above example, `#array` would return 3 and the indices 1,2 or 3 could be used.

### Loops

There are several solutions for looping code. The two common ones are while- and for-loops.

#### while

A while loop checks a condition and loops as long as the condition returns true

```lua
while condition do --condition could be something like #result < 10
  -- looped code
end
```

#### for

A for loop has an index that counts the number of loop runs. It's exit condition is determined by comparing the index to an end value

```lua
for i = startvalue, endvalue, stepwidth do
  -- looped code
end
```

The index starts with the startvalue and is modified by stepwidth every time it finishes a loop run. if stepwidth is omitted, the step is 1. As soon as the index is greater or equal to the endvalue, no new loop runs are started.

To iterate over all key-value pairs in a struct, it is possible to use the `pairs` function:

```lua
for k,v in pairs(t) do 
  -- looped code
end
```

In the looped code, the key can be used with `k` and the value can be used with `v`.

### Conditionals

To skip some code under certain circumstances, conditionals are used.

```lua
if condition then
  -- some code
elseif othercondition then
  -- some other code
else
  -- some default code
end
```

If the condition applies, some code is executed. Otherwise optional other conditions are checked. If no condition applies, optionally the default code applies. Otherwise the execution jumps below the `end`.

### Operators

In conditions as well as in some codes, operators are used for mathematical operations or compares. There are several other operators as well.

#### Mathematical Operators

- `+` for addition
- `-` for subtraction
- `*` for multiplication
- `/` for division
- `%` for modulo
- `^` for exponentiation

#### Comparators

- `==` equal
- `!=` not equal
- `~=` not equal
- `<` less
- `>` greater
- `⇐` less or equal
- `>=` greator or equal

#### Logic

- `and`
- `or`

#### String Concatenation

- `..` to combine strings: `"string a " .. "string b"` results in `"string a string b"`

### Imports

Some files use functions from other script files. These can be imported:

```lua
-- import
local scriptvariablename = ug_require "::/scripts/scriptname.lua"
 
-- use
scriptvariablename.functionname(parameter)
```

The file path for the imported script follows the pattern described on the page about [resource types](../../modding/general/resourcetypes.md#file_names_references).
