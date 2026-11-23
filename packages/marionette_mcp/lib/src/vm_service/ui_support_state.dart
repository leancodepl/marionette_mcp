/// Whether the app's Marionette configuration covers the UI libraries it
/// needs, as derived by `UiSupportReport.state`.
enum UiSupportState {
  /// Every library of the confirmed scope has its integration configured.
  configured,

  /// A library of the confirmed scope has no integration configured.
  missing,

  /// Coverage cannot be established: the scope is unconfirmed or the
  /// binding does not declare its integrations.
  unknown,
}
