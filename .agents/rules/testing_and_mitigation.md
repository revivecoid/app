# Mitigate Effects to Other Functions

- BEFORE CHANGING ANYTHING, MITIGATE THE EFFECT TO OTHER FUNCTIONS.
- ALWAYS TEST FIRST THE FUNCTIONS IN THE SAME PAGE/ENVIRONMENT BEFORE CONSIDERING THE TASK DONE.
- DO NOT OVERWRITE / REPLACE CODES BEFORE KNOWING EXACTLY WHAT IT DOES AND WHERE IT CONNECTS TO.

When modifying core utilities, datasets, or shared scripts, trace all usages of the modified components to ensure downstream functions do not break due to unexpected output formats, missing properties, or invalid references. Wait and perform verification on the modified features before informing the user.
