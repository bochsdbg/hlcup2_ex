defmodule HlCup do
  use Application
  use GenServer

  @test_account_id 120003

  def parse_until_nil(parser, result) do
    case :hlcup_nifs.parser_parse(parser) do
        nil -> result
        item ->
          if (elem(item, 0) === @test_account_id) do
            IO.inspect item
          end
          HlCup.Database.add_account(item)
          parse_until_nil(parser, [])
    end
  end

  def get_mem() do
    Keyword.get(:erlang.memory, :total, 0)
  end

  def format_mem(bytes), do: round(bytes / 1024) / 1024

  def init(_) do
    HlCup.Database.create_db()
    IO.puts "database created"
    mb = :hlcup_nifs.mutbin_create()
    {:ok, zh} = :hlcup_nifs.open_file('/home/me/prj/hlcup2/rating/data/data.zip')
    num_files = :hlcup_nifs.num_files(zh)
    IO.inspect {:num_files, num_files}

    p = :hlcup_nifs.parser_create()


    # num_files = 1
    for idx <- 0..(num_files-1) do
      :ok = :hlcup_nifs.read_file(zh, idx, mb)
      :hlcup_nifs.parser_set_bin_multi(p, mb)
      mem = get_mem()
      {time, _} = :timer.tc(fn -> parse_until_nil(p, []) end)
      IO.inspect {idx, :time, time, :mem_current, format_mem(get_mem() - mem), :mem_total, format_mem(get_mem()) }
    end

    IO.inspect(HlCup.Database.get_account(@test_account_id, true))
    IO.inspect {:dict_sizes, [
      city: :ets.last(:city_id_to_name),
      country: :ets.last(:country_id_to_name),
      fname: :ets.last(:fname_id_to_name), 
      sname: :ets.last(:sname_id_to_name),
      email_domain: :ets.last(:email_domain_id_to_name),
      interest: :ets.last(:interest_id_to_name),
    ]}

    :hlcup_nifs.parser_free(p)

    :hlcup_nifs.mutbin_free(mb)

    {:ok, nil}
  end

  def start(_type, _args), do: GenServer.start(__MODULE__, [])
end
