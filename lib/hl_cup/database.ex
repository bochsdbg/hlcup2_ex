defmodule HlCup.Database do
  require Record
  Record.defrecord(:account, [
    sex: nil,
    birth: nil,
    joined: nil,
    premium: nil,
    city: nil,
    country: nil,
    fname: nil,
    sname: nil,
    phone: nil,
    email: nil,
    interests: nil,
  ])

  @bit_size_birth         32 # 32
  @bit_size_joined        32 # 64
  @bit_size_premium_start 32 # 96
  @bit_size_premium_end   32 # 128

  @bit_size_sex           1  # 1
  @bit_size_city          10 # 11
  @bit_size_country       7  # 18
  @bit_size_fname         7  # 25
  @bit_size_sname         11 # 36
  @bit_size_phone_code    7  # 43
  @bit_size_phone_num     27 # 70
  @bit_size_email_domain  4  # 74
  @bit_size_email_acc_len 5  # 79
  @bit_size_interests_len 4  # 83

  @bit_size_total  (@bit_size_birth +
                    @bit_size_joined +
                    @bit_size_premium_start + 
                    @bit_size_premium_end +
                    @bit_size_sex + 
                    @bit_size_city + 
                    @bit_size_country + 
                    @bit_size_fname + 
                    @bit_size_sname + 
                    @bit_size_phone_code + 
                    @bit_size_phone_num + 
                    @bit_size_email_domain + 
                    @bit_size_email_acc_len + 
                    @bit_size_interests_len)

  @bit_size_padding ( ceil(@bit_size_total / 8) * 8 )


  def add_account({ id, sex, birth, joined, {premium_start, premium_end}, city, country, fname, sname, phone_bin, email_bin, interests, likes }) do
    city_id = dict_get_id_or_put(:city, city)
    country_id = dict_get_id_or_put(:country, country)
    fname_id = dict_get_id_or_put(:fname, fname)
    sname_id = dict_get_id_or_put(:sname, sname)
    phone = parse_phone(phone_bin)
    {email_acc, email_domain} = parse_email(email_bin)

    interests = Enum.map(interests, fn(x) -> 
      dict_get_id_or_put(:interest, x)
    end)

    if length(interests) > 16 do
      IO.inspect {interests, length(interests)}
      System.halt
    end
    email_domain_id = dict_get_id_or_put(:email_domain, email_domain)

    :ets.insert(:accounts, {id, encode_account({ id, sex, birth, joined, {premium_start, premium_end}, city_id, country_id, fname_id, sname_id, phone, {email_domain_id, email_acc}, interests, likes }) })
  end

  defp parse_phone(nil), do: {0, 0}
  defp parse_phone(<<"8(", code :: binary-size(3), ")", rest :: binary-size(7)>>) do
    {String.to_integer(code), String.to_integer(rest)}
  end
  defp parse_phone(<<"8(", code :: binary-size(3), ")", rest :: binary-size(8)>>) do
    {String.to_integer(code), String.to_integer(rest)}
  end

  defp parse_email(nil), do: {"", ""}
  defp parse_email(email) do
    [acc, domain] = String.split(email, "@")
    {acc, domain}
  end

  defp encode_timestamp(nil), do: 0
  defp encode_timestamp(x), do: x

  defp decode_timestamp(0), do: nil
  defp decode_timestamp(x), do: x

  defp phone_to_string({code, num}) when code >= 1000, do: nil
  defp phone_to_string({code, num}), do: "8(" <> Integer.to_string(code) <> ")" <> Integer.to_string(num)

  def encode_interests(interests), do: for x <- interests, into: "", do: << x :: 8 >>

  def encode_account({ _id, sex, birth, joined, {premium_start, premium_end}, city_id, country_id, fname_id, sname_id, {phone_code, phone_num}, {email_domain_id, email_acc}, interests, _ }) do
    <<
      birth  :: signed-size(@bit_size_birth),
      joined :: signed-size(@bit_size_joined),
      encode_timestamp(premium_start) :: signed-size(@bit_size_premium_start),
      encode_timestamp(premium_end)   :: signed-size(@bit_size_premium_end),

      sex        :: unsigned-size(@bit_size_sex),
      city_id    :: unsigned-size(@bit_size_city),
      country_id :: unsigned-size(@bit_size_country),
      fname_id   :: unsigned-size(@bit_size_fname),
      sname_id   :: unsigned-size(@bit_size_sname),

      (phone_code - 900 + 1) :: unsigned-size(@bit_size_phone_code),
      phone_num  :: unsigned-size(@bit_size_phone_num),

      email_domain_id      :: unsigned-size(@bit_size_email_domain),
      byte_size(email_acc) :: unsigned-size(@bit_size_email_acc_len),
      length(interests)    :: unsigned-size(@bit_size_interests_len),

      0 :: unsigned-size(@bit_size_padding),

      email_acc :: binary,
      encode_interests(interests) :: binary
      >>
  end

  def decode_account(<<
        birth :: signed-size(@bit_size_birth),
        joined :: signed-size(@bit_size_joined),
        premium_start :: signed-size(@bit_size_premium_start),
        premium_end   :: signed-size(@bit_size_premium_end),

        sex        :: unsigned-size(@bit_size_sex),
        city_id    :: unsigned-size(@bit_size_city),
        country_id :: unsigned-size(@bit_size_country),
        fname_id   :: unsigned-size(@bit_size_fname),
        sname_id   :: unsigned-size(@bit_size_sname),

        phone_code :: unsigned-size(@bit_size_phone_code),
        phone_num  :: unsigned-size(@bit_size_phone_num),

        email_domain_id  :: unsigned-size(@bit_size_email_domain),
        email_acc_len    :: unsigned-size(@bit_size_email_acc_len),
        interests_len    :: unsigned-size(@bit_size_interests_len),

        0 :: unsigned-size(@bit_size_padding), 
        rest :: binary>>) 
  do
    <<email_acc :: binary-size(email_acc_len), interests_bin :: binary-size(interests_len)>> = rest
    account(
      birth: birth,
      joined: joined,
      premium: { decode_timestamp(premium_start), decode_timestamp(premium_end) },
      sex: sex,
      city: city_id,
      country: country_id,
      fname: fname_id,
      sname: sname_id,
      phone: { phone_code + 900 - 1, phone_num },
      email: { email_domain_id, email_acc },
      interests: String.to_charlist(interests_bin)
      )
  end

  def account_load_strings(account() = acc) do
    {email_domain_id, email_acc} = account(acc, :email)
    interests = account(acc, :interests)
    account(acc, 
            city: dict_lookup_id(:city, account(acc, :city)),
            country: dict_lookup_id(:country, account(acc, :country)),
            sname: dict_lookup_id(:sname, account(acc, :sname)),
            fname: dict_lookup_id(:fname, account(acc, :fname)),
            phone: phone_to_string(account(acc, :phone)),
            email: email_acc <> dict_lookup_id(:email_domain, email_domain_id),
            interests: Enum.map(interests, fn(x) -> dict_lookup_id(:interest, x)  end)
            )
  end

  def get_account(id, decode_full \\ false) do
    case :ets.lookup(:accounts, id) do
      [{id, acc_bin}] -> 
        acc = decode_account(acc_bin)
        if decode_full do
          account_load_strings(acc)
        else
          acc
        end
      _ -> nil
    end
  end

  defmacro tabname_name_to_id(dictname) do
    quote do
      List.to_existing_atom(Atom.to_charlist(unquote(dictname)) ++ '_name_to_id')
    end
  end

  defmacro tabname_id_to_name(dictname) do
    quote do
      List.to_existing_atom(Atom.to_charlist(unquote(dictname)) ++ '_id_to_name')
    end
  end

  def dict_create(dictname) do
    tab1 = List.to_atom(Atom.to_charlist(dictname) ++ '_id_to_name')
    tab2 = List.to_atom(Atom.to_charlist(dictname) ++ '_name_to_id')
    :ets.new(tab1, [:ordered_set, :named_table])
    :ets.new(tab2, [:set, :named_table])
  end

  def dict_put_new(dictname, name) do
    tab_name_to_id = tabname_name_to_id(dictname)
    tab_id_to_name = tabname_id_to_name(dictname)

    id = case :ets.last(tab_id_to_name) do
      :'$end_of_table' -> 1
      id -> id + 1
    end

    _r1 = :ets.insert_new(tab_id_to_name, {id, name})
    _r2 = :ets.insert_new(tab_name_to_id, {name, id})

    # if (dictname === :country) do
    #   IO.inspect {tab_id_to_name, id, name, r1, r2}
    # end

    id
  end

  def dict_lookup_name(dictname, name) do
    tab_name = tabname_name_to_id(dictname)
    case :ets.lookup(tab_name, name) do
      [{^name, id}] -> id
      _ -> nil
    end
  end

  def dict_lookup_id(dictname, id) do
    tab_name = tabname_id_to_name(dictname)
    case :ets.lookup(tab_name, id) do
      [{^id, name}] -> name
      _ -> nil
    end
  end

  def dict_get_id_or_put(dictname, name) when name !== nil do
    case dict_lookup_name(dictname, name) do
      nil -> dict_put_new(dictname, name)
      id -> id
    end
  end
  def dict_get_id_or_put(_dictname, _name), do: 0

  def create_db() do
    IO.puts("create_db() start")
    :ets.new(:accounts, [:set, :named_table])
    for tab <- [:country, :city, :fname, :sname, :interest, :phone_code, :email_domain] do
      IO.puts("create " <> Atom.to_string(tab))
      dict_create(tab)
    end
    IO.puts("create_db() end")
  end
end