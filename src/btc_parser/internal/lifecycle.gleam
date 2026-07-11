/// Phantom type marking a value that was successfully decoded from its wire
/// representation.
///
/// A decoded value has not necessarily passed any consensus validation.
pub type Decoded

/// Phantom type marking a decoded value that passed its available
/// context-free consensus validation.
///
/// This state does not guarantee full consensus validity, which may require
/// context not contained in the value itself.
pub type ContextFreeValidated
