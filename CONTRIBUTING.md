# Conventions and Tips to Contribute to developing

## Dependencies

As of January 2023 this project relies on **Lua 5.3** .
(This is because as of mid 2022 MikTeX's luatex uses Lua 5.3 .)

Ensure that you can run a Lua interpreter from anywhere:
Open any terminal window an try to execute ``lua -v``.

## IDE

The maintainter recommends to use **Visual Studio Code** as the IDE.
You will need to install the following extentions:
- Lua by sumneko
- Lua Debug by actboy168
- Lua Test Adapter by Linus Sunde
These extensions are configured by the ``.json files`` in the ``.vscode`` directory.

### Tests

<!-- As of Januar 2022 the maintainer recommends to not use Visual Studio Code's native Testing UI.
Instead the Test Explorer UI provided by the extension Test Explorer UI from Holger Benl
should be used. This is because the extension Lua Test Adapter still uses the Test Explorer UI.
The conversion to the native Test API seems to not work satisfying. -->

## Code Formatting

All code is **formatted manually**. Please turn off any code formatting/refactoring features.
