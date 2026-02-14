import gleam/bool
import gleam/list
import gleam/result
import internal/reader.{type Reader}

pub opaque type Parser(ctx, a, err) {
  Parser(fn(Reader, List(ctx)) -> Result(#(Reader, a), err))
}

/// Execute a parser and continue with its result.
///
/// Runs the parser with the given reader and context, then passes the updated
/// reader and parsed value to a continuation function.
///
/// This is useful when you need to sequence parsing steps imperatively while
/// retaining access to intermediate results.
/// 
/// Use `run` instead if you only need the parser’s raw result.
pub fn run_then(
  reader: Reader,
  ctx: List(ctx),
  parser: Parser(ctx, a, err),
  next: fn(Reader, a) -> Result(b, err),
) -> Result(b, err) {
  use #(reader, value) <- result.try(run(reader, ctx, parser))
  next(reader, value)
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
  reader: Reader,
  ctx: List(ctx),
  parser: Parser(ctx, a, err),
) -> Result(#(Reader, a), err) {
  let Parser(parse) = parser
  parse(reader, ctx)
}

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
  ctx: ctx,
) -> Parser(ctx, a, err) {
  let Parser(parse) = parser
  Parser(fn(reader, outer_ctx) { parse(reader, [ctx, ..outer_ctx]) })
}

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

/// Transform the successful result of a parser.
pub fn map(parser: Parser(ctx, a, err), f: fn(a) -> b) -> Parser(ctx, b, err) {
  let Parser(parse) = parser

  Parser(fn(reader, ctx) {
    use #(reader, value) <- result.try(parse(reader, ctx))
    Ok(#(reader, f(value)))
  })
}

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
    use #(reader, val1) <- result.try(run(reader, ctx, parser1))
    use #(reader, val2) <- result.try(run(reader, ctx, parser2))
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
    use #(reader, val1) <- result.try(run(reader, ctx, parser1))
    use #(reader, val2) <- result.try(run(reader, ctx, parser2))
    use #(reader, val3) <- result.try(run(reader, ctx, parser3))
    Ok(#(reader, f(val1, val2, val3)))
  })
}

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
    run(reader, ctx, f(value))
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
    use #(reader, value) <- result.try(run(reader, ctx, parser1))
    use #(reader, _) <- result.try(run(reader, ctx, parser2))
    Ok(#(reader, value))
  })
}

/// Lift a value into a parser without consuming input.
pub fn return(value: a) -> Parser(ctx, a, err) {
  Parser(fn(reader, _) { Ok(#(reader, value)) })
}

/// Parse something exactly n times with indexed context.
pub fn indexed_repeat(
  count: Int,
  item_parser: Parser(ctx, a, err),
  index_to_context: fn(Int) -> ctx,
) -> Parser(ctx, List(a), err) {
  Parser(fn(reader, ctx) {
    use <- bool.guard(count <= 0, Ok(#(reader, [])))

    let indices = list.range(0, count - 1)
    let init = #(reader, [])

    indices
    |> list.try_fold(init, fn(acc, index) {
      let #(reader, items) = acc
      let contextualized = with_context(item_parser, index_to_context(index))
      use #(reader, item) <- result.try(run(reader, ctx, contextualized))
      Ok(#(reader, [item, ..items]))
    })
    |> result.map(fn(acc) { #(acc.0, list.reverse(acc.1)) })
  })
}

/// Parse items n times with indexed context and cumulative metric tracking.
///
/// Each item parser returns `#(item, metric_value)`. The metric values are
/// summed, and parsing fails fast if the cumulative sum exceeds `limit`.
///
/// The `on_limit_exceeded` callback receives the exceeded value, the reader
/// (after the item that caused the limit to be exceeded was parsed), and the
/// context stack, allowing for proper error construction with byte offsets.
///
/// Returns only the items (metric values are discarded after validation).
pub fn indexed_repeat_with_limit(
  count: Int,
  item_parser: Parser(ctx, #(a, Int), err),
  index_to_context: fn(Int) -> ctx,
  limit: Int,
  on_limit_exceeded: fn(Int, Reader, List(ctx)) -> err,
) -> Parser(ctx, List(a), err) {
  Parser(fn(reader, ctx) {
    use <- bool.guard(count <= 0, Ok(#(reader, [])))

    let indices = list.range(0, count - 1)
    let init = #(reader, [], 0)

    indices
    |> list.try_fold(init, fn(acc, index) {
      let #(reader, items, acc_val) = acc
      let contextualized = with_context(item_parser, index_to_context(index))

      use #(reader, #(item, item_val)) <- result.try(run(
        reader,
        ctx,
        contextualized,
      ))

      let acc_val = acc_val + item_val
      case acc_val > limit {
        True -> Error(on_limit_exceeded(acc_val, reader, ctx))
        False -> Ok(#(reader, [item, ..items], acc_val))
      }
    })
    |> result.map(fn(acc) { #(acc.0, list.reverse(acc.1)) })
  })
}
