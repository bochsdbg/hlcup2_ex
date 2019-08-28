defmodule :hlcup_nifs do
  @on_load :load_nif

  def test(), do: load_error()
  def open_file(_filename), do: load_error()
  def close_file(_zip_h), do: load_error()
  def num_files(_zip_h), do: load_error()
  def read_file(_zip_h, _idx, _mb), do: load_error()

  def mutbin_create(), do: load_error()
  def mutbin_get(_mb), do: load_error()
  def mutbin_free(_mb), do: load_error()

  def parser_create(), do: load_error()
  def parser_free(_p), do: load_error()
  def parser_set_bin(_p, _mb), do: load_error()
  def parser_set_bin_multi(_p, _mb), do: load_error()
  def parser_parse(_p), do: load_error()

  defp load_error(), do: raise("Cannot load hlcup_nifs")

  def load_nif do
    ret = :erlang.load_nif(:code.priv_dir(:hlcup) ++ '/hlcup2_ex', [])
    IO.inspect {:nif_load, ret}
    ret
  end
end