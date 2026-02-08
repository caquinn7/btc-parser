import gleam/result
import internal/reader.{type Reader}

pub opaque type Parser(ctx, a, err) {
  Parser(fn(Reader, List(ctx)) -> Result(#(Reader, a), err))
}

/// For continuation-passing style (use syntax) in sequential parser composition
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

/// Lift a value into a parser that always succeeds without consuming input.
pub fn pure(value: a) -> Parser(ctx, a, err) {
  Parser(fn(reader, _ctx) { Ok(#(reader, value)) })
}

/// Create a parser that always fails with the given error.
pub fn fail(error: err) -> Parser(ctx, a, err) {
  Parser(fn(_reader, _ctx) { Error(error) })
}

/// Transform the successful result of a parser.
pub fn map(parser: Parser(ctx, a, err), f: fn(a) -> b) -> Parser(ctx, b, err) {
  let Parser(parse) = parser

  Parser(fn(reader, ctx) {
    use #(reader, value) <- result.try(parse(reader, ctx))
    Ok(#(reader, f(value)))
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
