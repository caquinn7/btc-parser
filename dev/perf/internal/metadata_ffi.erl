-module(metadata_ffi).
-export([runtime_target/0, runtime_version/0, os_name/0, architecture_name/0]).

runtime_target() ->
    <<"erlang">>.

runtime_version() ->
    try
        OtpRelease = to_binary(erlang:system_info(otp_release)),
        ErtsVersion = to_binary(erlang:system_info(version)),
        <<"Erlang/OTP ", OtpRelease/binary, " (ERTS ", ErtsVersion/binary, ")">>
    catch
        _:_ -> <<"unknown">>
    end.

os_name() ->
    try
        case os:type() of
            {win32, _} -> <<"win32">>;
            {_, Name} when is_atom(Name) -> atom_to_binary(Name, utf8);
            _ -> <<"unknown">>
        end
    catch
        _:_ -> <<"unknown">>
    end.

architecture_name() ->
    try
        SystemArchitecture = to_binary(erlang:system_info(system_architecture)),
        case binary:split(SystemArchitecture, <<"-">>) of
            [Architecture | _] when byte_size(Architecture) > 0 -> Architecture;
            _ -> <<"unknown">>
        end
    catch
        _:_ -> <<"unknown">>
    end.

to_binary(Value) when is_binary(Value) ->
    Value;
to_binary(Value) when is_list(Value) ->
    unicode:characters_to_binary(Value);
to_binary(_) ->
    <<"unknown">>.
