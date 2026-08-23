import btc_parser/internal/parser.{type Parser}
import btc_parser/internal/reader

type TestContext {
  Outer
  Inner
  AtIndex(Int)
}

type TestError {
  ByteReadFailed
  FirstFailure
  ContinuationWasInvoked
  LaterItemWasInvoked
  WrongContext(List(TestContext))
  LimitExceeded(total: Int, start_offset: Int, context: List(TestContext))
  MappedReadFailure(start_offset: Int, context: List(TestContext))
}

fn byte_parser() -> Parser(TestContext, Int, TestError) {
  fn(reader, _) {
    case reader.read_u8(reader) {
      Ok(result) -> Ok(result)
      Error(_) -> Error(ByteReadFailed)
    }
  }
}

// from_reader

pub fn from_reader_maps_error_at_the_original_reader_offset_test() {
  let source_reader = reader.new(<<0x01>>)
  let assert Ok(#(advanced_reader, _)) = reader.read_u8(source_reader)

  let parser =
    parser.from_reader(reader.read_u8, fn(_, start_offset, context) {
      MappedReadFailure(start_offset:, context:)
    })

  assert parser.run(parser, advanced_reader, [Outer])
    == Error(MappedReadFailure(start_offset: 1, context: [Outer]))
}

// then

pub fn then_threads_the_advanced_reader_and_preserves_context_test() {
  let parser =
    parser.then(byte_parser(), fn(first) {
      fn(reader, context) {
        case context {
          [Outer] ->
            case reader.read_u8(reader) {
              Ok(#(next_reader, second)) -> Ok(#(next_reader, first + second))
              Error(_) -> Error(ByteReadFailed)
            }
          _ -> Error(WrongContext(context))
        }
      }
    })

  let assert Ok(#(final_reader, value)) =
    parser.run(parser, reader.new(<<0x05, 0x07>>), [Outer])

  assert value == 12
  assert reader.get_offset(final_reader) == 2
}

pub fn then_stops_before_its_continuation_test() {
  let failing = fn(_, _) { Error(FirstFailure) }

  let then_parser =
    parser.then(failing, fn(_) { fn(_, _) { Error(ContinuationWasInvoked) } })
  let source_reader = reader.new(<<0x01>>)

  assert parser.run(then_parser, source_reader, [Outer]) == Error(FirstFailure)
}

// indexed_repeat

pub fn indexed_repeat_preserves_context_order_result_order_and_reader_state_test() {
  let item_parser = fn(reader, context) {
    case context {
      [AtIndex(index), Inner, Outer] ->
        case reader.read_u8(reader) {
          Ok(#(next_reader, value)) -> Ok(#(next_reader, #(index, value)))
          Error(_) -> Error(ByteReadFailed)
        }
      _ -> Error(WrongContext(context))
    }
  }

  let parser =
    parser.indexed_repeat(3, item_parser, AtIndex)
    |> parser.with_context(Inner)

  let assert Ok(#(final_reader, values)) =
    parser.run(parser, reader.new(<<0x0A, 0x14, 0x1E>>), [Outer])

  assert values == [#(0, 10), #(1, 20), #(2, 30)]
  assert reader.get_offset(final_reader) == 3
}

pub fn indexed_repeat_stops_before_later_items_after_an_error_test() {
  let item_parser = fn(_, context) {
    case context {
      [AtIndex(0), ..] -> Error(FirstFailure)
      [AtIndex(_), ..] -> Error(LaterItemWasInvoked)
      _ -> Error(WrongContext(context))
    }
  }

  let parser = parser.indexed_repeat(2, item_parser, AtIndex)

  assert parser.run(parser, reader.new(<<>>), [Outer]) == Error(FirstFailure)
}

// indexed_repeat_with_limit

pub fn indexed_repeat_with_limit_reports_item_start_offset_and_context_test() {
  let item_parser = fn(reader, _) {
    case reader.read_u8(reader) {
      Ok(#(next_reader, value)) -> Ok(#(next_reader, #(value, 2)))
      Error(_) -> Error(ByteReadFailed)
    }
  }

  let parser =
    parser.indexed_repeat_with_limit(
      2,
      item_parser,
      AtIndex,
      3,
      fn(total, start_offset, context) {
        LimitExceeded(total:, start_offset:, context:)
      },
    )

  let source_reader = reader.new(<<0x00, 0x01, 0x02>>)
  let assert Ok(#(advanced_reader, _)) = reader.read_u8(source_reader)

  assert parser.run(parser, advanced_reader, [Outer])
    == Error(
      LimitExceeded(total: 4, start_offset: 2, context: [AtIndex(1), Outer]),
    )
}

pub fn indexed_repeat_with_limit_stops_before_later_items_after_an_error_test() {
  let item_parser = fn(_, context) {
    case context {
      [AtIndex(0), ..] -> Error(FirstFailure)
      [AtIndex(_), ..] -> Error(LaterItemWasInvoked)
      _ -> Error(WrongContext(context))
    }
  }

  let parser =
    parser.indexed_repeat_with_limit(
      2,
      item_parser,
      AtIndex,
      10,
      fn(total, start_offset, context) {
        LimitExceeded(total:, start_offset:, context:)
      },
    )

  assert parser.run(parser, reader.new(<<>>), [Outer]) == Error(FirstFailure)
}

pub fn indexed_repeat_with_limit_stops_before_later_items_after_limit_test() {
  let item_parser = fn(reader, context) {
    case context {
      [AtIndex(2), ..] -> Error(LaterItemWasInvoked)
      [AtIndex(_), ..] ->
        case reader.read_u8(reader) {
          Ok(#(next_reader, value)) -> Ok(#(next_reader, #(value, 2)))
          Error(_) -> Error(ByteReadFailed)
        }
      _ -> Error(WrongContext(context))
    }
  }

  let parser =
    parser.indexed_repeat_with_limit(
      3,
      item_parser,
      AtIndex,
      3,
      fn(total, start_offset, context) {
        LimitExceeded(total:, start_offset:, context:)
      },
    )

  assert parser.run(parser, reader.new(<<0x00, 0x01, 0x02>>), [Outer])
    == Error(
      LimitExceeded(total: 4, start_offset: 1, context: [AtIndex(1), Outer]),
    )
}
