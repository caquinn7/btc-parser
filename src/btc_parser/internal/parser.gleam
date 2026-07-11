import btc_parser/internal/reader.{type Reader}
import gleam/list
import gleam/result

pub opaque type Parser(ctx, a, err) {
  Parser(fn(Reader, List(ctx)) -> Result(#(Reader, a), err))
}

// ============================================================================
// Core Construction & Execution
// ============================================================================

/// Create a parser from a function.
///
/// This is the low-level constructor used when you need full control over parsing
/// logic. Most of the time you'll use higher-level combinators like `map`, `then`,
/// or `try` instead.
pub fn new(
  f: fn(Reader, List(ctx)) -> Result(#(Reader, a), err),
) -> Parser(ctx, a, err) {
  Parser(f)
}

/// Create a parser from a reader function, mapping its low-level error.
///
/// The mapper receives the error, the reader offset from before the read, and
/// the current parser context stack.
pub fn from_reader(
  read: fn(Reader) -> Result(#(Reader, a), e),
  map_error: fn(e, Int, List(ctx)) -> err,
) -> Parser(ctx, a, err) {
  Parser(fn(reader, ctx) {
    let start_offset = reader.get_offset(reader)

    reader
    |> read
    |> result.map_error(map_error(_, start_offset, ctx))
  })
}

/// Execute a parser and return its raw result.
///
/// This is the primitive evaluator for `Parser`. It runs the parser with the given
/// reader and context, returning the updated reader and parsed value, or an error.
///
/// Prefer building parsers with combinators like `map`, `then`, and `try`.
/// Use `run` when you need to evaluate a parser immediately, such as at the
/// top level or inside imperative control flow.
/// 
/// Use `run_then` to execute a parser and continue with its result.
pub fn run(
  parser: Parser(ctx, a, err),
  reader: Reader,
  context: List(ctx),
) -> Result(#(Reader, a), err) {
  let Parser(parse) = parser
  parse(reader, context)
}

/// Execute a parser and continue with its result.
///
/// Runs the parser with the given reader and context, then passes the updated
/// reader and parsed value to a continuation function.
///
/// This is useful when you need to sequence parsing steps imperatively while
/// retaining access to intermediate results.
/// 
/// Use `run` instead if you only need the parser's raw result.
pub fn run_then(
  parser: Parser(ctx, a, err),
  reader: Reader,
  context: List(ctx),
  next: fn(Reader, a) -> Result(b, err),
) -> Result(b, err) {
  use #(reader, value) <- result.try(run(parser, reader, context))
  next(reader, value)
}

// ============================================================================
// Basic Building Blocks
// ============================================================================

/// Lift a value into a parser without consuming input.
pub fn return(value: a) -> Parser(ctx, a, err) {
  Parser(fn(reader, _) { Ok(#(reader, value)) })
}

/// Transform the successful result of a parser.
pub fn map(parser: Parser(ctx, a, err), f: fn(a) -> b) -> Parser(ctx, b, err) {
  let Parser(parse) = parser

  Parser(fn(reader, ctx) {
    use #(reader, value) <- result.try(parse(reader, ctx))
    Ok(#(reader, f(value)))
  })
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
  Parser(fn(reader, ctx) {
    use #(reader, val1) <- result.try(run(parser1, reader, ctx))
    use #(reader, val2) <- result.try(run(parser2, reader, ctx))
    Ok(#(reader, f(val1, val2)))
  })
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
  Parser(fn(reader, ctx) {
    use #(reader, val1) <- result.try(run(parser1, reader, ctx))
    use #(reader, val2) <- result.try(run(parser2, reader, ctx))
    use #(reader, val3) <- result.try(run(parser3, reader, ctx))
    Ok(#(reader, f(val1, val2, val3)))
  })
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
/// Use `try` instead if your transformation returns a `Result` rather than a `Parser`.
pub fn then(
  parser: Parser(ctx, a, err),
  f: fn(a) -> Parser(ctx, b, err),
) -> Parser(ctx, b, err) {
  let Parser(parse) = parser

  Parser(fn(reader, ctx) {
    use #(reader, value) <- result.try(parse(reader, ctx))
    run(f(value), reader, ctx)
  })
}

/// Run two parsers in sequence, keeping only the first result.
///
/// Useful when you need to parse something followed by a delimiter or 
/// separator that you want to discard.
pub fn keep_left(
  parser1: Parser(ctx, a, err),
  parser2: Parser(ctx, b, err),
) -> Parser(ctx, a, err) {
  Parser(fn(reader, ctx) {
    use #(reader, value) <- result.try(run(parser1, reader, ctx))
    use #(reader, _) <- result.try(run(parser2, reader, ctx))
    Ok(#(reader, value))
  })
}

// ============================================================================
// Error Handling & Validation
// ============================================================================

/// Chain a parser with a fallible transformation.
///
/// This function takes a parser's successful result and applies a transformation
/// that can fail (returns `Result`). If the transformation fails, the parser fails
/// with the resulting error. If it succeeds, the parser continues with the new value.
///
/// This is useful for validation, type conversion, and other operations that depend
/// on the parsed value and can produce errors with the same error type.
///
/// Use `then` instead if your transformation returns a `Parser` rather than a `Result`.
pub fn try(
  parser: Parser(ctx, a, err),
  f: fn(a) -> Result(b, err),
) -> Parser(ctx, b, err) {
  let Parser(parse) = parser

  Parser(fn(reader, ctx) {
    use #(reader, value) <- result.try(parse(reader, ctx))
    use new_value <- result.try(f(value))
    Ok(#(reader, new_value))
  })
}

/// Chain a parser with a fallible transformation that needs reader context.
///
/// Like `try`, but the transformation function receives the current reader state
/// and context stack in addition to the parsed value. This is useful for validation
/// that depends on:
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
  let Parser(parse) = parser

  Parser(fn(reader, ctx) {
    use #(reader, value) <- result.try(parse(reader, ctx))
    use new_value <- result.try(f(value, reader, ctx))
    Ok(#(reader, new_value))
  })
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
  let Parser(parse) = parser

  Parser(fn(reader, ctx) {
    let start_offset = reader.get_offset(reader)
    use #(reader, value) <- result.try(parse(reader, ctx))
    use new_value <- result.try(f(value, start_offset, reader, ctx))
    Ok(#(reader, new_value))
  })
}

/// Require the parser to have consumed all input.
pub fn end_of_input(
  make_error: fn(Int, Reader, List(ctx)) -> err,
) -> Parser(ctx, Nil, err) {
  Parser(fn(reader, contexts) {
    case reader.bytes_remaining(reader) {
      0 -> Ok(#(reader, Nil))
      remaining_bytes -> Error(make_error(remaining_bytes, reader, contexts))
    }
  })
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
  let Parser(parse) = parser
  Parser(fn(reader, outer_ctx) { parse(reader, [context, ..outer_ctx]) })
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
  Parser(fn(reader, ctx) {
    indexed_repeat_loop(
      0,
      count,
      reader,
      [],
      ctx,
      item_parser,
      index_to_context,
    )
  })
}

fn indexed_repeat_loop(
  index: Int,
  count: Int,
  reader: Reader,
  items: List(a),
  context: List(ctx),
  item_parser: Parser(ctx, a, err),
  index_to_context: fn(Int) -> ctx,
) -> Result(#(Reader, List(a)), err) {
  case index >= count {
    True -> Ok(#(reader, list.reverse(items)))
    False -> {
      let contextualized = with_context(item_parser, index_to_context(index))
      use #(reader, item) <- result.try(run(contextualized, reader, context))
      indexed_repeat_loop(
        index + 1,
        count,
        reader,
        [item, ..items],
        context,
        item_parser,
        index_to_context,
      )
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
  Parser(fn(reader, ctx) {
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
  })
}

fn indexed_repeat_with_limit_loop(
  index: Int,
  count: Int,
  reader: Reader,
  items: List(a),
  acc_val: Int,
  context: List(ctx),
  item_parser: Parser(ctx, #(a, Int), err),
  index_to_context: fn(Int) -> ctx,
  limit: Int,
  on_limit_exceeded: fn(Int, Int, List(ctx)) -> err,
) -> Result(#(Reader, List(a)), err) {
  case index >= count {
    True -> Ok(#(reader, list.reverse(items)))
    False -> {
      let index_ctx = index_to_context(index)
      let contextualized = with_context(item_parser, index_ctx)
      let start_offset = reader.get_offset(reader)

      use #(reader, #(item, item_val)) <- result.try(run(
        contextualized,
        reader,
        context,
      ))

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
            reader,
            [item, ..items],
            acc_val,
            context,
            item_parser,
            index_to_context,
            limit,
            on_limit_exceeded,
          )
      }
    }
  }
}
