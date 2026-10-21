/// Help text for the `--ancestor-keys` option, shared by every matcher-based
/// command.
const ancestorKeysHelp = 'Limit the search to the subtree of the element with '
    'this key. Use it when the same key appears in several identical '
    'subtrees (grid cells, repeated cards). Repeat the option, outermost '
    'wrapper first, to go deeper: each key is looked up inside the previous '
    "one's subtree.";
