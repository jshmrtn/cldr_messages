defmodule Cldr.Message do
  @moduledoc """
  Implements the [ICU Message Format](http://userguide.icu-project.org/formatparse/messages)
  with functions to parse and interpolate messages.

  """
  alias Cldr.Message.Parser

  @type message :: binary()
  @type arguments :: list() | map()
  @type options :: Keyword.t()

  @doc false
  def cldr_backend_provider(config) do
    Cldr.Message.Backend.define_message_module(config)
  end

  @doc false
  def message_format(format, backend) do
    Module.concat(backend, Message).message_format(format)
  end

  @doc """
  Formats an ICU message into a string.

  Returns `{:ok, message}` or `{:error, reason}`.

  """
  @spec to_string(message(), arguments(), options()) ::
          {:ok, binary()} | {:error, {module(), binary()}}
  def to_string(message, args, options \\ []) do
    case format(message, args, options) do
      {:error, reason} -> {:error, reason}
      {:ok, message} -> {:ok, :erlang.iolist_to_binary(message)}
    end
  end

  @doc """
  Formats an ICU message into a string.

  Returns a string or raises on error

  """
  @spec to_string!(message(), arguments(), options()) :: binary() | no_return()
  def to_string!(message, args, options \\ []) do
    case to_string(message, args, options) do
      {:ok, message} -> message
      {:error, {exception, reason}} -> raise exception, reason
    end
  end

  @doc """
  Formats an ICU messages into an IO list

  """
  @spec format(message() | list() | tuple(), arguments(), options()) ::
          list() | {:ok, list()} | {:error, {module(), binary()}}

  def format(message, args, options \\ [])

  def format(message, args, options) when is_binary(message) do
    options = Keyword.merge(default_options(), options)

    case Parser.parse(message) do
      {:ok, result} ->
        formatted =
          result
          |> remove_nested_whitespace
          |> format(args, options)

        {:ok, formatted}

      {:ok, _result, rest} ->
        {:error,
         {Cldr.Message.ParseError, "Couldn't parse message. Error detected at #{inspect(rest)}"}}

      other ->
        other
    end
  end

  def format([head], args, options) do
    [to_string(format(head, args, options))]
  end

  def format([head | rest], args, options) do
    [format_to_string(format(head, args, options)) | format(rest, args, options)]
  end

  def format({:literal, literal}, _args, _options) when is_binary(literal) do
    literal
  end

  def format({:pos_arg, arg}, args, _options) when is_map(args) do
    Map.fetch!(args, String.to_existing_atom(arg))
  end

  def format({:pos_arg, arg}, args, _options) when is_list(args) do
    Enum.at(args, arg)
  end

  def format({:named_arg, arg}, args, _options) when is_map(args) do
    Map.fetch!(args, String.to_existing_atom(arg))
  end

  def format({:named_arg, arg}, args, _options) when is_list(args) do
    Keyword.fetch!(args, String.to_existing_atom(arg))
  end

  def format(:value, _args, options) do
    Keyword.fetch!(options, :arg)
  end

  def format({:simple_format, arg, type}, args, options) do
    arg = format(arg, args, options)
    format({arg, type}, args, options)
  end

  def format({:simple_format, arg, type, style}, args, options) do
    arg = format(arg, args, options)
    format({arg, type, style}, args, options)
  end

  def format({number, :number}, _args, options) do
    Cldr.Number.to_string!(number, options)
  end

  @integer_format "#"
  def format({number, :number, :integer}, _args, options) do
    options = Keyword.put(options, :format, @integer_format)
    Cldr.Number.to_string!(number, options)
  end

  def format({number, :number, :short}, _args, options) do
    options = Keyword.put(options, :format, :short)
    Cldr.Number.to_string!(number, options)
  end

  def format({number, :number, :currency}, _args, options) do
    options = Keyword.put(options, :format, :currency)
    Cldr.Number.to_string!(number, options)
  end

  def format({number, :number, :percent}, _args, options) do
    options = Keyword.put(options, :format, :percent)
    Cldr.Number.to_string!(number, options)
  end

  def format({number, :number, :permille}, _args, options) do
    options = Keyword.put(options, :format, :permille)
    Cldr.Number.to_string!(number, options)
  end

  def format({number, :number, format}, _args, options) when is_binary(format) do
    options = Keyword.put(options, :format, format)
    Cldr.Number.to_string!(number, options)
  end

  def format({number, :number, format}, _args, options) when is_atom(format) do
    format_options = message_format(format, options[:backend])
    options = Keyword.merge(options, format_options)
    Cldr.Number.to_string!(number, options)
  end

  def format({number, :spellout}, _args, options) do
    options = Keyword.put(options, :format, :spellout)
    Cldr.Number.to_string!(number, options)
  end

  def format({number, :spellout, :verbose}, _args, options) do
    options = Keyword.put(options, :format, :spellout_verbose)
    Cldr.Number.to_string!(number, options)
  end

  def format({number, :spellout, :year}, _args, options) do
    options = Keyword.put(options, :format, :spellout_year)
    Cldr.Number.to_string!(number, options)
  end

  def format({number, :spellout, :ordinal}, _args, options) do
    options = Keyword.put(options, :format, :spellout_ordinal)
    Cldr.Number.to_string!(number, options)
  end

  def format({date, :date}, _args, options) do
    Cldr.Date.to_string!(date, options)
  end

  def format({date, :date, format}, _args, options) when is_binary(format) do
    options = Keyword.put(options, :format, format)
    Cldr.Time.to_string!(date, options)
  end

  def format({date, :date, format}, _args, options)
      when format in [:short, :medium, :long, :full] do
    options = Keyword.put(options, :format, format)
    Cldr.Date.to_string!(date, options)
  end

  def format({number, :date, format}, _args, options) when is_atom(format) do
    format_options = message_format(format, options[:backend])
    options = Keyword.merge(options, format_options)
    Cldr.Date.to_string!(number, options)
  end

  def format({time, :time}, _args, options) do
    Cldr.Time.to_string!(time, options)
  end

  def format({time, :time, format}, _args, options) when is_binary(format) do
    options = Keyword.put(options, :format, format)
    Cldr.Time.to_string!(time, options)
  end

  def format({time, :time, format}, _args, options)
      when format in [:short, :medium, :long, :full] do
    options = Keyword.put(options, :format, format)
    Cldr.Time.to_string!(time, options)
  end

  def format({number, :time, format}, _args, options) when is_atom(format) do
    format_options = message_format(format, options[:backend])
    options = Keyword.merge(options, format_options)
    Cldr.Time.to_string!(number, options)
  end

  def format({datetime, :datetime}, _args, options) do
    Cldr.DateTime.to_string!(datetime, options)
  end

  def format({datetime, :datetime, format}, _args, options) when is_binary(format) do
    options = Keyword.put(options, :format, format)
    Cldr.DateTime.to_string!(datetime, options)
  end

  def format({datetime, :datetime, format}, _args, options)
      when format in [:short, :medium, :long, :full] do
    options = Keyword.put(options, :format, format)
    Cldr.DateTime.to_string!(datetime, options)
  end

  def format({number, :datetime, format}, _args, options) when is_atom(format) do
    format_options = message_format(format, options[:backend])
    options = Keyword.merge(options, format_options)
    Cldr.DateTime.to_string!(number, options)
  end

  def format({money, :money, format}, _args, options) when format in [:short, :long] do
    options = Keyword.put(options, :format, format)
    Money.to_string!(money, options)
  end

  def format({number, :money, format}, _args, options) when is_atom(format) do
    format_options = message_format(format, options[:backend])
    options = Keyword.merge(options, format_options)
    Money.to_string!(number, options)
  end

  def format({list, :list}, _args, options) do
    Cldr.List.to_string!(list, options)
  end

  def format({list, :list, :and}, _args, options) do
    Cldr.List.to_string!(list, options)
  end

  def format({list, :list, format}, _args, options)
      when format in [
             :or,
             :or_narrow,
             :or_short,
             :standard,
             :standard_narrow,
             :standard_short,
             :unit,
             :unit_narrow,
             :unit_short
           ] do
    options = Keyword.put(options, :format, format)
    Cldr.List.to_string!(list, options)
  end

  def format({number, :list, format}, _args, options) when is_atom(format) do
    format_options = message_format(format, options[:backend])
    options = Keyword.merge(options, format_options)
    Cldr.List.to_string!(number, options)
  end

  def format({unit, :unit}, _args, options) do
    Cldr.Unit.to_string!(unit, options)
  end

  def format({unit, :unit, format}, _args, options)
      when format in [:long, :short, :narrow] do
    options = Keyword.put(options, :format, format)
    Cldr.Unit.to_string!(unit, options)
  end

  def format({number, :unit, format}, _args, options) when is_atom(format) do
    format_options = message_format(format, options[:backend])
    options = Keyword.merge(options, format_options)
    Cldr.Unit.to_string!(number, options)
  end

  def format({:select, arg, selections}, args, options) when is_map(selections) do
    arg =
      arg
      |> format!(args, options)
      |> to_maybe_integer

    message = Map.get(selections, arg) || other(selections, arg)
    format(message, args, options)
  end

  def format({:plural, arg, {:offset, offset}, plurals}, args, options) when is_map(plurals) do
    format_plural(arg, Cardinal, offset, plurals, args, options)
  end

  def format({:select_ordinal, arg, plurals}, args, options) when is_map(plurals) do
    format_plural(arg, Ordinal, 0, plurals, args, options)
  end

  @spec format!(message() | list() | tuple(), arguments(), options()) ::
          list() | String.t()

  def format!(arg, args, options) do
    case format(arg, args, options) do
      {:ok, any} -> any
      {:error, {exception, reason}} -> raise exception, reason
      any -> any
    end
  end

  defp format_to_string(value) when is_number(value) do
    Cldr.Number.to_string!(value)
  end

  defp format_to_string(%Decimal{} = value) do
    Cldr.Number.to_string!(value)
  end

  defp format_to_string(%Date{} = value) do
    Cldr.Date.to_string!(value)
  end

  defp format_to_string(%Time{} = value) do
    Cldr.Time.to_string!(value)
  end

  defp format_to_string(%DateTime{} = value) do
    Cldr.DateTime.to_string!(value)
  end

  defp format_to_string(value) do
    to_string(value)
  end

  defp format_plural(arg, type, offset, plurals, args, options) do
    arg =
      arg
      |> format!(args, options)
      |> to_maybe_integer

    formatted_arg = Cldr.Number.to_string!(arg - offset, options)

    options =
      options
      |> Keyword.put(:type, type)
      |> Keyword.put(:arg, formatted_arg)

    plural_type = Cldr.Number.PluralRule.plural_type(arg - offset, options)
    message = Map.get(plurals, arg) || Map.get(plurals, plural_type) || other(plurals, arg)
    format(message, args, options)
  end

  defp default_options do
    [locale: Cldr.get_locale(), backend: Cldr.default_backend()]
  end

  @spec other(map(), atom() | binary()) :: any()
  defp other(map, _arg) when is_map(map) do
    Map.fetch!(map, "other")
  end

  @spec to_maybe_integer(number | Decimal.t() | String.t() | list()) :: number() | String.t() | atom()
  defp to_maybe_integer(arg) when is_integer(arg) do
    arg
  end

  defp to_maybe_integer(arg) when is_float(arg) do
    trunc(arg)
  end

  defp to_maybe_integer(%Decimal{} = arg) do
    Decimal.to_integer(arg)
  end

  defp to_maybe_integer(other) do
    other
  end

  defp remove_nested_whitespace([maybe_complex]) do
    [remove_nested_whitespace(maybe_complex)]
  end

  defp remove_nested_whitespace([{complex_arg, _arg, _selects} = complex | rest])
       when complex_arg in [:plural, :select, :select_ordinal] do
    [remove_nested_whitespace(complex), remove_nested_whitespace(rest)]
  end

  defp remove_nested_whitespace([head | rest]) do
    [head | remove_nested_whitespace(rest)]
  end

  defp remove_nested_whitespace({complex_arg, arg, selects})
       when complex_arg in [:select, :plural, :select_ordinal] do
    selects =
      Enum.map(selects, fn
        {k, [{:literal, string} = literal, {:select, _, _} = select | other]} ->
          if is_whitespace?(string), do: {k, [select | other]}, else: [literal, select | other]

        {k, [{:literal, string} = literal, {:plural, _, _, _} = plural | other]} ->
          if is_whitespace?(string), do: {k, [plural | other]}, else: [literal, plural | other]

        {k, [{:literal, string} = literal, {:select_ordinal, _, _} = select | other]} ->
          if is_whitespace?(string), do: {k, [select | other]}, else: [literal, select | other]

        other ->
          other
      end)
      |> Map.new()

    {complex_arg, arg, selects}
  end

  defp remove_nested_whitespace(other) do
    other
  end

  defp is_whitespace?(<<" ", rest::binary>>) do
    is_whitespace?(rest)
  end

  defp is_whitespace?(<<"\n", rest::binary>>) do
    is_whitespace?(rest)
  end

  defp is_whitespace?(<<"\t", rest::binary>>) do
    is_whitespace?(rest)
  end

  defp is_whitespace?(<<_char::bytes-1, _rest::binary>>) do
    false
  end

  defp is_whitespace?("") do
    true
  end
end
