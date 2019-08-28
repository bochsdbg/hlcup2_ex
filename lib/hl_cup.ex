defmodule HlCup do
  use Application
  use GenServer

  def parse_until_nil(parser, result) do
    case :hlcup_nifs.parser_parse(parser) do
        nil -> :ok
        item -> parse_until_nil(parser, nil)
    end
  end

  def get_mem() do
    Keyword.get(:erlang.memory, :total, 0)
  end

  def init(_) do
    IO.puts "hello"
    mb = :hlcup_nifs.mutbin_create()
    {:ok, zh} = :hlcup_nifs.open_file('/home/me/prj/hlcup2/rating/data/data.zip')
    num_files = :hlcup_nifs.num_files(zh)
    IO.inspect {:num_files, num_files}
    :ok = :hlcup_nifs.read_file(zh, 0, mb)

    p = :hlcup_nifs.parser_create()
    :hlcup_nifs.parser_set_bin_multi(p, mb)

    mem = get_mem()
    IO.inspect :timer.tc(fn -> parse_until_nil(p, []) end)
    IO.inspect {:memory, (get_mem() - mem) / 1024 / 1024}

    :hlcup_nifs.parser_free(p)

    :hlcup_nifs.mutbin_free(mb)

    {:ok, nil}
  end

  def start(_type, _args), do: GenServer.start(__MODULE__, [])
end