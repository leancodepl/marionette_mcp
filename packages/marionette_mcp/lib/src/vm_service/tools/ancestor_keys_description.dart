/// Shared description of the `ancestor_keys` field across every matcher-based
/// tool.
///
/// Kept short on purpose: it is repeated in every schema, so its length is
/// paid on every connection. The full contract — strict nesting, the failure
/// rule, the `scroll_to` timing, what ignores the field — is stated once in
/// the server instructions.
const ancestorKeysDescription =
    'Optional wrapper keys (ValueKey<String>), outermost first; each is '
    'looked up inside the previous one. Limits the search to that subtree. '
    'Fails if a key has no element.';
