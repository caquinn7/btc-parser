import btc_parser/internal/reader.{type Reader}
import gleam/list

/// A composable parser over a byte `Reader`.
///
/// A parser receives the current reader and parse-context stack. On success it
/// returns the advanced reader paired with the parsed value; on failure it
/// returns the parser's error type.
pub type Parser(ctx, value, error) =
  fn(Reader, List(ctx)) -> Result(#(Reader, value), error)

// ============================================================================
// Core Construction & Execution
// ============================================================================

/// Create a parser from a reader function, mapping its low-level error.
///
/// The mapper receives the error, the reader offset from before the read, and
/// the current parser context stack.
pub fn from_reader(
  read: fn(Reader) -> Result(#(Reader, a), e),
  map_error: fn(e, Int, List(ctx)) -> err,
) -> Parser(ctx, a, err) {
  fn(reader, ctx) {
    let start_offset = reader.get_offset(reader)

    case read(reader) {
      Ok(result) -> Ok(result)
      Error(error) -> Error(map_error(error, start_offset, ctx))
    }
  }
}

/// Execute a parser and return its raw result.
///
/// This is the primitive evaluator for `Parser`. It runs the parser with the given
/// reader and context, returning the updated reader and parsed value, or an error.
///
/// Prefer building parsers with combinators like `map` and `then`.
/// Use `run` when you need to evaluate a parser immediately, such as at the
/// top level or inside imperative control flow.
pub fn run(
  parser: Parser(ctx, a, err),
  reader: Reader,
  context: List(ctx),
) -> Result(#(Reader, a), err) {
  parser(reader, context)
}

// ============================================================================
// Basic Building Blocks
// ============================================================================

/// Lift a value into a parser without consuming input.
pub fn return(value: a) -> Parser(ctx, a, err) {
  fn(reader, _) { Ok(#(reader, value)) }
}

/// Transform the successful result of a parser.
pub fn map(parser: Parser(ctx, a, err), f: fn(a) -> b) -> Parser(ctx, b, err) {
  fn(reader, ctx) {
    case parser(reader, ctx) {
      Ok(#(next_reader, value)) -> Ok(#(next_reader, f(value)))
      Error(error) -> Error(error)
    }
  }
}

// ============================================================================
// Combining Parsers
// ============================================================================

/// Combine two independent parsers and transform their results.
///
/// Runs both parsers in sequence and applies a function to both results.
/// This is useful when you need to parse two values that don't depend on each other
/// and combine them into a single result.
pub fn map2(
  parser1: Parser(ctx, a, err),
  parser2: Parser(ctx, b, err),
  f: fn(a, b) -> c,
) -> Parser(ctx, c, err) {
  fn(reader, ctx) {
    case parser1(reader, ctx) {
      Ok(#(next_reader, value1)) ->
        case parser2(next_reader, ctx) {
          Ok(#(final_reader, value2)) -> Ok(#(final_reader, f(value1, value2)))
          Error(error) -> Error(error)
        }
      Error(error) -> Error(error)
    }
  }
}

/// Combine three independent parsers and transform their results.
///
/// Runs all three parsers in sequence and applies a function to all results.
/// This is useful when you need to parse three values that don't depend on each other
/// and combine them into a single result.
pub fn map3(
  parser1: Parser(ctx, a, err),
  parser2: Parser(ctx, b, err),
  parser3: Parser(ctx, c, err),
  f: fn(a, b, c) -> d,
) -> Parser(ctx, d, err) {
  fn(reader, ctx) {
    case parser1(reader, ctx) {
      Ok(#(reader_after_first, value1)) ->
        case parser2(reader_after_first, ctx) {
          Ok(#(reader_after_second, value2)) ->
            case parser3(reader_after_second, ctx) {
              Ok(#(final_reader, value3)) ->
                Ok(#(final_reader, f(value1, value2, value3)))
              Error(error) -> Error(error)
            }
          Error(error) -> Error(error)
        }
      Error(error) -> Error(error)
    }
  }
}

// ============================================================================
// Sequencing & Chaining
// ============================================================================

/// Chain two parsers where the second depends on the first's result.
///
/// This is the monadic bind operation for parsers. It runs the first parser,
/// then uses its result to determine which parser to run next.
///
/// This is useful when you need to parse something based on a previously parsed value,
/// such as reading a count then reading that many items.
///
/// For fallible transformations that need parser state, use `try_with_reader`
/// or `try_with_start_offset`.
pub fn then(
  parser: Parser(ctx, a, err),
  f: fn(a) -> Parser(ctx, b, err),
) -> Parser(ctx, b, err) {
  fn(reader, ctx) {
    case parser(reader, ctx) {
      Ok(#(next_reader, value)) -> {
        let next_parse = f(value)
        next_parse(next_reader, ctx)
      }
      Error(error) -> Error(error)
    }
  }
}

/// Run two parsers in sequence, keeping only the first result.
///
/// Useful when you need to parse something followed by a delimiter or 
/// separator that you want to discard.
pub fn keep_left(
  parser1: Parser(ctx, a, err),
  parser2: Parser(ctx, b, err),
) -> Parser(ctx, a, err) {
  fn(reader, ctx) {
    case parser1(reader, ctx) {
      Ok(#(reader_after_first, value)) ->
        case parser2(reader_after_first, ctx) {
          Ok(#(final_reader, _)) -> Ok(#(final_reader, value))
          Error(error) -> Error(error)
        }
      Error(error) -> Error(error)
    }
  }
}

// ============================================================================
// Error Handling & Validation
// ============================================================================

/// Chain a parser with a fallible transformation that needs reader context.
///
/// The transformation function receives the current reader state and context
/// stack in addition to the parsed value. This is useful for validation that
/// depends on:
/// - Remaining bytes in the input
/// - Position information for error reporting
/// - Context stack for creating properly located errors
///
/// The reader state passed to the function reflects the state *after* parsing
/// the value, so you can check how many bytes remain or get the current offset.
pub fn try_with_reader(
  parser: Parser(ctx, a, err),
  f: fn(a, Reader, List(ctx)) -> Result(b, err),
) -> Parser(ctx, b, err) {
  fn(reader, ctx) {
    case parser(reader, ctx) {
      Ok(#(next_reader, value)) ->
        case f(value, next_reader, ctx) {
          Ok(new_value) -> Ok(#(next_reader, new_value))
          Error(error) -> Error(error)
        }
      Error(error) -> Error(error)
    }
  }
}

/// Chain a parser with a fallible transformation that needs the start offset.
///
/// Like `try_with_reader`, but also captures the byte offset from before parsing.
/// This is useful for validation errors that should point to the beginning of the
/// field being parsed rather than to the position after parsing.
///
/// The function receives:
/// - The parsed value
/// - The byte offset from *before* parsing (start of the field)
/// - The reader state *after* parsing
/// - The context stack
///
/// This is particularly useful for semantic validation errors where you want the
/// error location to point to the problematic field itself.
pub fn try_with_start_offset(
  parser: Parser(ctx, a, err),
  f: fn(a, Int, Reader, List(ctx)) -> Result(b, err),
) -> Parser(ctx, b, err) {
  fn(reader, ctx) {
    let start_offset = reader.get_offset(reader)

    case parser(reader, ctx) {
      Ok(#(next_reader, value)) ->
        case f(value, start_offset, next_reader, ctx) {
          Ok(new_value) -> Ok(#(next_reader, new_value))
          Error(error) -> Error(error)
        }
      Error(error) -> Error(error)
    }
  }
}

/// Require the parser to have consumed all input.
pub fn end_of_input(
  make_error: fn(Int, Reader, List(ctx)) -> err,
) -> Parser(ctx, Nil, err) {
  fn(reader, contexts) {
    case reader.bytes_remaining(reader) {
      0 -> Ok(#(reader, Nil))
      remaining_bytes -> Error(make_error(remaining_bytes, reader, contexts))
    }
  }
}

// ============================================================================
// Context Management
// ============================================================================

/// Run a parser with additional context information.
///
/// This adds a context value to the context stack when executing the parser, which 
/// is useful for error reporting and tracking where in a nested structure parsing 
/// occurs. The context is implemented as a stack (list) so nested parsers can add 
/// their own context while preserving parent context.
///
/// Common uses include tracking array indices, field names, or structural locations
/// to provide better error messages when parsing fails.
pub fn with_context(
  parser: Parser(ctx, a, err),
  context: ctx,
) -> Parser(ctx, a, err) {
  fn(reader, outer_ctx) { parser(reader, [context, ..outer_ctx]) }
}

// ============================================================================
// List Parsing (Repeated Items)
// ============================================================================

/// Parse items exactly n times with indexed context.
/// 
/// For each iteration from 0 to n-1, the item_parser is wrapped with context 
/// derived from index_to_context(index), allowing each parsed item to be 
/// associated with its index. Results are accumulated and returned as a List.
pub fn indexed_repeat(
  count: Int,
  item_parser: Parser(ctx, a, err),
  index_to_context: fn(Int) -> ctx,
) -> Parser(ctx, List(a), err) {
  fn(reader, ctx) {
    indexed_repeat_loop(
      0,
      count,
      reader,
      [],
      ctx,
      item_parser,
      index_to_context,
    )
  }
}

fn indexed_repeat_loop(
  index: Int,
  count: Int,
  reader: Reader,
  items: List(a),
  context: List(ctx),
  parse_item: fn(Reader, List(ctx)) -> Result(#(Reader, a), err),
  index_to_context: fn(Int) -> ctx,
) -> Result(#(Reader, List(a)), err) {
  case index >= count {
    True -> Ok(#(reader, list.reverse(items)))
    False -> {
      let index_context = index_to_context(index)

      case parse_item(reader, [index_context, ..context]) {
        Ok(#(next_reader, item)) ->
          indexed_repeat_loop(
            index + 1,
            count,
            next_reader,
            [item, ..items],
            context,
            parse_item,
            index_to_context,
          )
        Error(err) -> Error(err)
      }
    }
  }
}

/// Parse items n times with indexed context and cumulative metric tracking.
///
/// Each item parser returns `#(item, metric_value)`. The metric values are
/// summed, and parsing fails fast if the cumulative sum exceeds `limit`.
///
/// The `on_limit_exceeded` callback receives:
/// - The exceeded cumulative value
/// - The byte offset of the start of the item that caused the limit to be exceeded
/// - The context stack
///
/// This allows for proper error construction with precise byte offsets pointing
/// to the problematic item.
///
/// Returns only the items (metric values are discarded after validation).
pub fn indexed_repeat_with_limit(
  count: Int,
  item_parser: Parser(ctx, #(a, Int), err),
  index_to_context: fn(Int) -> ctx,
  limit: Int,
  on_limit_exceeded: fn(Int, Int, List(ctx)) -> err,
) -> Parser(ctx, List(a), err) {
  fn(reader, ctx) {
    indexed_repeat_with_limit_loop(
      0,
      count,
      reader,
      [],
      0,
      ctx,
      item_parser,
      index_to_context,
      limit,
      on_limit_exceeded,
    )
  }
}

fn indexed_repeat_with_limit_loop(
  index: Int,
  count: Int,
  reader: Reader,
  items: List(a),
  acc_val: Int,
  context: List(ctx),
  parse_item: fn(Reader, List(ctx)) -> Result(#(Reader, #(a, Int)), err),
  index_to_context: fn(Int) -> ctx,
  limit: Int,
  on_limit_exceeded: fn(Int, Int, List(ctx)) -> err,
) -> Result(#(Reader, List(a)), err) {
  case index >= count {
    True -> Ok(#(reader, list.reverse(items)))
    False -> {
      let index_ctx = index_to_context(index)
      let start_offset = reader.get_offset(reader)

      case parse_item(reader, [index_ctx, ..context]) {
        Ok(#(next_reader, #(item, item_val))) -> {
          let acc_val = acc_val + item_val
          case acc_val > limit {
            True -> {
              let ctx = [index_ctx, ..context]
              Error(on_limit_exceeded(acc_val, start_offset, ctx))
            }
            False ->
              indexed_repeat_with_limit_loop(
                index + 1,
                count,
                next_reader,
                [item, ..items],
                acc_val,
                context,
                parse_item,
                index_to_context,
                limit,
                on_limit_exceeded,
              )
          }
        }
        Error(error) -> Error(error)
      }
    }
  }
}
