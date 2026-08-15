import gleam/string

/// Runtime metadata recorded alongside one performance suite invocation.
pub type PerfMetadata {
  PerfMetadata(
    target: String,
    runtime: String,
    os: String,
    architecture: String,
  )
}

/// Collects runtime metadata without failing the performance suite.
pub fn current() -> PerfMetadata {
  PerfMetadata(
    target: runtime_target(),
    runtime: runtime_version(),
    os: os_name(),
    architecture: normalize_architecture(architecture_name()),
  )
}

fn normalize_architecture(value: String) -> String {
  case string.lowercase(value) {
    "" -> "unknown"
    "aarch64" -> "arm64"
    "arm64" -> "arm64"
    "x86_64" -> "x64"
    "amd64" -> "x64"
    "x64" -> "x64"
    value -> value
  }
}

@external(erlang, "metadata_ffi", "runtime_target")
@external(javascript, "./metadata_ffi.mjs", "runtimeTarget")
fn runtime_target() -> String

@external(erlang, "metadata_ffi", "runtime_version")
@external(javascript, "./metadata_ffi.mjs", "runtimeVersion")
fn runtime_version() -> String

@external(erlang, "metadata_ffi", "os_name")
@external(javascript, "./metadata_ffi.mjs", "osName")
fn os_name() -> String

@external(erlang, "metadata_ffi", "architecture_name")
@external(javascript, "./metadata_ffi.mjs", "architectureName")
fn architecture_name() -> String
