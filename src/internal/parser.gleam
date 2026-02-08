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
pub fn in_context(ctx: ctx, parser: Parser(ctx, a, err)) -> Parser(ctx, a, err) {
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

/// Transform the error of a parser.
pub fn map_error(
  parser: Parser(ctx, a, err1),
  f: fn(err1) -> err2,
) -> Parser(ctx, a, err2) {
  let Parser(parse) = parser

  Parser(fn(reader, ctx) {
    parse(reader, ctx)
    |> result.map_error(f)
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
