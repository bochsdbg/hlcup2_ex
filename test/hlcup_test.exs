defmodule HlcupTest do
  use ExUnit.Case

  test "db simple" do
    IO.inspect HlCup.Database.id_to_name(:cities, 123)
  end
end
