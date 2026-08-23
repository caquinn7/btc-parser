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
  InputRemaining(remaining: Int, offset: Int, context: List(TestContext))
  WrongContext(List(TestContext))
  WrongOffset(Int)
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

pub fn from_reader_preserves_a_successful_reader_result_test() {
  let parser =
    parser.from_reader(reader.read_u8, fn(_, _, _) { MappedReadFailure(0, []) })

  let assert Ok(#(advanced_reader, value)) =
    parser.run(parser, reader.new(<<0x2A, 0xFF>>), [Outer])

  assert value == 42
  assert reader.get_offset(advanced_reader) == 1
  assert reader.get_remaining(advanced_reader) == <<0xFF>>
}

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

// Basic building blocks

pub fn return_returns_its_value_without_consuming_input_test() {
  let source_reader = reader.new(<<0x2A>>)

  let assert Ok(#(final_reader, value)) =
    parser.run(parser.return(7), source_reader, [Outer])

  assert value == 7
  assert reader.get_offset(final_reader) == 0
  assert reader.get_remaining(final_reader) == <<0x2A>>
}

pub fn map_transforms_a_success_without_consuming_additional_input_test() {
  let mapped = parser.map(byte_parser(), fn(value) { value * 2 })

  let assert Ok(#(final_reader, value)) =
    parser.run(mapped, reader.new(<<0x15, 0xFF>>), [Outer])

  assert value == 42
  assert reader.get_offset(final_reader) == 1
  assert reader.get_remaining(final_reader) == <<0xFF>>
}

// Combining parsers

pub fn map2_threads_both_readers_and_combines_results_test() {
  let combined =
    parser.map2(byte_parser(), byte_parser(), fn(first, second) {
      first + second
    })

  let assert Ok(#(final_reader, value)) =
    parser.run(combined, reader.new(<<0x05, 0x07>>), [Outer])

  assert value == 12
  assert reader.get_offset(final_reader) == 2
}

pub fn map3_threads_all_readers_and_combines_results_test() {
  let combined =
    parser.map3(
      byte_parser(),
      byte_parser(),
      byte_parser(),
      fn(first, second, third) { first + second + third },
    )

  let assert Ok(#(final_reader, value)) =
    parser.run(combined, reader.new(<<0x05, 0x07, 0x0B>>), [Outer])

  assert value == 23
  assert reader.get_offset(final_reader) == 3
}

pub fn keep_left_discards_the_second_result_after_consuming_it_test() {
  let kept = parser.keep_left(byte_parser(), byte_parser())

  let assert Ok(#(final_reader, value)) =
    parser.run(kept, reader.new(<<0x2A, 0xFF>>), [Outer])

  assert value == 42
  assert reader.get_offset(final_reader) == 2
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

// Error handling and validation

pub fn try_with_reader_receives_the_advanced_reader_and_context_test() {
  let checked =
    parser.try_with_reader(byte_parser(), fn(value, next_reader, context) {
      case
        context,
        reader.get_offset(next_reader),
        reader.bytes_remaining(next_reader)
      {
        [Outer], 1, 1 -> Ok(value * 2)
        _, offset, _ -> Error(WrongOffset(offset))
      }
    })

  let assert Ok(#(final_reader, value)) =
    parser.run(checked, reader.new(<<0x15, 0xFF>>), [Outer])

  assert value == 42
  assert reader.get_offset(final_reader) == 1
}

pub fn try_with_start_offset_receives_the_field_start_and_advanced_reader_test() {
  let source_reader = reader.new(<<0x00, 0x15, 0xFF>>)
  let assert Ok(#(advanced_reader, _)) = reader.read_u8(source_reader)

  let checked =
    parser.try_with_start_offset(
      byte_parser(),
      fn(value, start_offset, next_reader, context) {
        case context, start_offset, reader.get_offset(next_reader) {
          [Outer], 1, 2 -> Ok(value * 2)
          _, _, offset -> Error(WrongOffset(offset))
        }
      },
    )

  let assert Ok(#(final_reader, value)) =
    parser.run(checked, advanced_reader, [Outer])

  assert value == 42
  assert reader.get_offset(final_reader) == 2
}

pub fn end_of_input_accepts_an_exhausted_reader_and_reports_remaining_input_test() {
  let end =
    parser.end_of_input(fn(remaining, current_reader, context) {
      InputRemaining(
        remaining:,
        offset: reader.get_offset(current_reader),
        context:,
      )
    })

  let exhausted_reader = reader.new(<<>>)
  assert parser.run(end, exhausted_reader, [Outer])
    == Ok(#(exhausted_reader, Nil))

  let source_reader = reader.new(<<0x00, 0x01>>)
  let assert Ok(#(advanced_reader, _)) = reader.read_u8(source_reader)

  assert parser.run(end, advanced_reader, [Outer])
    == Error(InputRemaining(remaining: 1, offset: 1, context: [Outer]))
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
