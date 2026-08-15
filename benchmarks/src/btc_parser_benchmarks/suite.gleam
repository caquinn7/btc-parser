//// Combined performance suite selection and execution.

import btc_parser_benchmarks/block/suite as block_suite
import btc_parser_benchmarks/internal/benchmark.{
  type PerfSection, type PerfSectionDefinition, PerfSection,
}
import btc_parser_benchmarks/internal/metadata.{type PerfMetadata}
import btc_parser_benchmarks/transaction/suite as transaction_suite
import gleam/list
import gleam/string

/// Results for one invocation of the complete performance suite.
pub type PerfResult {
  PerfResult(metadata: PerfMetadata, sections: List(PerfSection))
}

/// A validated selection of performance report sections.
///
/// Create a selection with `select_sections`. The type is opaque so `run`
/// cannot be called with section selectors that have not been validated.
pub opaque type SectionSelection {
  SectionSelection(definitions: List(PerfSectionDefinition))
}

/// An error returned when selecting performance report sections.
pub type SelectSectionsError {
  /// One or more section selectors do not match any report section.
  UnknownSectionSelectors(selectors: List(String))
}

/// Returns all concrete leaf section IDs in canonical suite order.
///
/// Transaction sections run before block sections, and calling this function
/// never constructs benchmark inputs.
pub fn section_ids() -> List(String) {
  section_definitions()
  |> list.map(fn(definition) { definition.id })
}

/// Validates and resolves section selectors.
///
/// An exact selector matches one concrete leaf section ID. A group selector
/// matches every leaf ID that begins with the selector followed by a dot. An
/// empty list selects the complete suite. Repeated and overlapping selectors
/// select each leaf once, and selected sections always retain canonical suite
/// order. All unmatched selectors are returned before any benchmark input is
/// constructed or timed.
pub fn select_sections(
  selectors: List(String),
) -> Result(SectionSelection, SelectSectionsError) {
  let definitions = section_definitions()
  let unknown_selectors =
    selectors
    |> list.filter(fn(selector) {
      !list.any(definitions, selector_matches_definition(selector, _))
    })
    |> list.unique

  case unknown_selectors {
    [_, ..] -> Error(UnknownSectionSelectors(unknown_selectors))
    [] -> {
      let selected_definitions = case selectors {
        [] -> definitions
        [_, ..] ->
          list.filter(definitions, fn(definition) {
            list.any(selectors, selector_matches_definition(_, definition))
          })
      }

      Ok(SectionSelection(selected_definitions))
    }
  }
}

/// Returns the concrete leaf section IDs in a validated selection in execution
/// order.
pub fn selected_section_ids(selection: SectionSelection) -> List(String) {
  let SectionSelection(definitions) = selection
  definitions
  |> list.map(fn(definition) { definition.id })
}

/// Runs the selected performance report sections and returns their measurements.
///
/// Runtime metadata is captured exactly once for the combined report.
pub fn run(selection: SectionSelection) -> PerfResult {
  let metadata = metadata.current()
  let SectionSelection(definitions) = selection
  let sections =
    list.map(definitions, fn(definition) {
      PerfSection(definition.id, definition.measure())
    })

  PerfResult(metadata:, sections:)
}

fn section_definitions() -> List(PerfSectionDefinition) {
  list.append(
    transaction_suite.section_definitions(),
    block_suite.section_definitions(),
  )
}

fn selector_matches_definition(
  selector: String,
  definition: PerfSectionDefinition,
) -> Bool {
  definition.id == selector
  || string.starts_with(definition.id, selector <> ".")
}
