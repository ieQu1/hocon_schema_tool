-module(hocon_schema_tool).

%% API exports
-export([main/1]).

%%====================================================================
%% API functions
%%====================================================================

%% escript Entry point
main(["--diff", A, B]) ->
  diff(A, B);
main(_) ->
  die(usage()).

%%====================================================================
%% Internal functions
%%====================================================================

diff(FileA, FileB) ->
  A = read_schema_json(FileA),
  B = read_schema_json(FileB),
  io:format("Paths:~n~p~n~n~nRecords:~n~p~n", [diff_paths(A, B), diff_records(A, B)]),
  ok.

read_schema_json(Filename) ->
  case file:read_file(Filename) of
    {ok, Bin} ->
      try jsone:decode(Bin, [{object_format, map}, {keys, atom}])
      catch
        _:Err ->
          die("Malformed JSON ~p; ~p", [Filename, Err])
      end;
    _ ->
      die("Cannot read file " ++ Filename)
  end.

die(Fmt) ->
  die(Fmt, []).

die(Fmt, Args) ->
  io:format(Fmt, Args),
  io:put_chars("\n"),
  erlang:halt(1).

diff_fields(FieldsA, FieldsB) ->
  diff_maps(fun(A, B) ->
                case diff_maps(A, B) of
                  #{changed := [], new := [], removed := []} ->
                    same;
                  #{changed := C, new := N, removed := R} ->
                    ChangedKeys = [K || {K, _} <- C],
                    {maps:with(R ++ ChangedKeys, A),
                     maps:with(N ++ ChangedKeys, B)}
                end
            end,
            fields(FieldsA),
            fields(FieldsB)).

diff_records(RecA, RecB) ->
  diff_maps(fun(A, B) ->
                case diff_fields(A, B) of
                  #{changed := [], removed := [], new := []} ->
                    same;
                  Diff ->
                    Diff
                end
            end,
            records(RecA),
            records(RecB)).

diff_paths(RecA, RecB) ->
  diff_maps(paths(RecA), paths(RecB)).

paths(Records) ->
  maps:from_list([{Path, Rec} || #{full_name := Rec, paths := Paths} <- Records, Path <- Paths]).

records(Records) ->
  maps:from_list([{Name, Fields} || #{full_name := Name, fields := Fields} <- Records]).

fields(Fields) ->
  maps:from_list([{Name, maps:without([name, desc], Field)} || Field = #{name := Name} <- Fields]).

diff_maps(MA, MB) ->
  diff_maps(fun(A, A) ->
                same;
               (A, B) ->
                {A, B}
            end,
            MA,
            MB).

diff_maps(DiffFun, A, B) ->
  NewKeys = maps:keys(B) -- maps:keys(A),
  {Changed, Removed} =
    maps:fold(fun(Key, Val, {Changed0, Removed0}) ->
                  case B of
                    #{Key := ValB} ->
                              case DiffFun(Val, ValB) of
                                same ->
                                  {Changed0, Removed0};
                                Diff ->
                                  {[{Key, Diff}|Changed0], Removed0}
                              end;
                    _ ->
                      {Changed0, [Key|Removed0]}
                  end
              end,
              {[], []},
              A),
  #{changed => Changed, removed => Removed, new => NewKeys}.

usage() ->
  "Usage:

  hocon_schema_tool --diff schema_a.json schema_b.json
".
