
v3debug is v3d's debugging tool. It's a program which runs a user's programs
with a modified copy of the `v3d` library. v3debug modifies all the functions
in `v3d` to add extra validation and record the functions being called.

There are two types of validations applied:
* Type checking - every parameter passed into a function is thoroughly
  type-checked according to the types in the documentation.
* Constraint checking - functions and types can have associated types, which are
  checked whenever a function is called. This includes checking the function's
  constraints, and the type constraints for any parameters passed in.

If any validations fail, v3d will throw an error and enter the 'capture' screen
to give the user more information about what function caused the error, where in
the user's code the function was called from, and what parameters it was called
with.

The other side of v3debug is function and instance recording. All tracked types
are stored in a list which can be seen by the user on the 'capture' screen. All
functions called this frame can also be seen in a tree view by the user,
including any parameters and return values, and nested arbitrarily within any
debug regions that the user code has entered.
