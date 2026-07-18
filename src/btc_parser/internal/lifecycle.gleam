/// Phantom type marking a value that was successfully parsed from its canonical
/// Bitcoin wire-format serialization.
///
/// A parsed value has not necessarily passed any consensus validation.
pub type Parsed

/// Phantom type marking a parsed value that passed its available
/// context-free consensus validation.
///
/// This state does not guarantee full consensus validity, which may require
/// context not contained in the value itself.
pub type ContextFreeValidated
