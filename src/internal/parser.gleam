import gleam/result
import internal/reader.{type Reader}

pub opaque type Parser(ctx, a, err) {
  Parser(fn(Reader, List(ctx)) -> Result(#(Reader, a), err))
}

/// Execute a parser and pass its result to a continuation function.
///
/// This is the primary way to sequence parser operations when you need access to 
/// intermediate parsed values. The continuation receives both the updated reader 
/// (with consumed input) and the parsed value.
///
/// Use `execute` instead if you just need the final result without further chaining.
pub fn run(
  reader: Reader,
  ctx: List(ctx),
  parser: Parser(ctx, a, err),
  next: fn(Reader, a) -> Result(b, err),
) {
  let Parser(parse) = parser

  use #(reader, value) <- result.try(parse(reader, ctx))
  next(reader, value)
}

/// For direct execution when you need to immediately pattern match on results (like in folds, branches, etc.)
pub fn execute(
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
pub fn new(
  f: fn(Reader, List(ctx)) -> Result(#(Reader, a), err),
) -> Parser(ctx, a, err) {
  Parser(f)
}

// /// Lift a value into a parser that always succeeds without consuming input.
// pub fn pure(value: a) -> Parser(ctx, a, err) {
//   Parser(fn(reader, _ctx) { Ok(#(reader, value)) })
// }

// /// Create a parser that always fails with the given error.
// pub fn fail(error: err) -> Parser(ctx, a, err) {
//   Parser(fn(_reader, _ctx) { Error(error) })
// }

/// Transform the successful result of a parser.
pub fn map(parser: Parser(ctx, a, err), f: fn(a) -> b) -> Parser(ctx, b, err) {
  let Parser(parse) = parser

  Parser(fn(reader, ctx) {
    use #(reader, value) <- result.try(parse(reader, ctx))
    Ok(#(reader, f(value)))
  })
}

pub fn map2(
  parser1: Parser(ctx, a, err),
  parser2: Parser(ctx, b, err),
  f: fn(a, b) -> c,
) -> Parser(ctx, c, err) {
  Parser(fn(reader, ctx) {
    use #(reader, val1) <- result.try(execute(reader, ctx, parser1))
    use #(reader, val2) <- result.try(execute(reader, ctx, parser2))
    Ok(#(reader, f(val1, val2)))
  })
}

pub fn map3(
  parser1: Parser(ctx, a, err),
  parser2: Parser(ctx, b, err),
  parser3: Parser(ctx, c, err),
  f: fn(a, b, c) -> d,
) {
  Parser(fn(reader, ctx) {
    use #(reader, val1) <- result.try(execute(reader, ctx, parser1))
    use #(reader, val2) <- result.try(execute(reader, ctx, parser2))
    use #(reader, val3) <- result.try(execute(reader, ctx, parser3))
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
/// Named `try` to align with Gleam standard library conventions (`result.try`, `option.try`).
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
pub fn then(
  parser: Parser(ctx, a, err),
  f: fn(a) -> Parser(ctx, b, err),
) -> Parser(ctx, b, err) {
  let Parser(parse) = parser

  Parser(fn(reader, ctx) {
    use #(reader, value) <- result.try(parse(reader, ctx))
    execute(reader, ctx, f(value))
  })
}
