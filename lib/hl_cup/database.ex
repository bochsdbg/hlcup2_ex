defmodule HlCup.Database do
  require Record
  @on_load :create_db

  def add_account({ id, sex, birth, joined, {premium_start, premium_end}, city, country, fname, sname, phone, email, interests, _ }) do
    :ok
  end

  defmacro id_to_name(table, id) do
    tab_name = List.to_existing_atom(Atom.to_list(table) ++ "_id_to_name")
    quote do
      :ets.lookup(unquote(tab_name), unquote(id))
    end
  end

  def create_db() do
    :ets.new(:accounts, [:set, :named_table])
    :ets.new(:cities_id_to_name, [:set, :named_table])
  end
end