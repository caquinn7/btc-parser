-module(double_sha256_ffi).
-export([hash/1]).

hash(Bytes) ->
    crypto:hash(sha256, crypto:hash(sha256, Bytes)).
