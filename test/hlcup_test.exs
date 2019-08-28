defmodule HlcupTest do
  use ExUnit.Case

  test "db simple" do
    import HlCup.Database
    :ets.insert(:cities_id_to_name, {123, 456})
    IO.inspect HlCup.Database.id_to_name(:cities, 123)
  end
end
