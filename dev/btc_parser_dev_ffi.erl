-module(btc_parser_dev_ffi).
-export([exit_failure/0]).

exit_failure() -> erlang:halt(1).
