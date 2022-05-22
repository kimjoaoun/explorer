defmodule Explorer.DataFrame do
  @moduledoc """
  The DataFrame struct and API.

  Dataframes are two-dimensional tabular data structures similar to a spreadsheet.
  For example, the Iris dataset:

      iex> Explorer.Datasets.iris()
      #Explorer.DataFrame<
        [rows: 150, columns: 5]
        sepal_length float [5.1, 4.9, 4.7, 4.6, 5.0, ...]
        sepal_width float [3.5, 3.0, 3.2, 3.1, 3.6, ...]
        petal_length float [1.4, 1.4, 1.3, 1.5, 1.4, ...]
        petal_width float [0.2, 0.2, 0.2, 0.2, 0.2, ...]
        species string ["Iris-setosa", "Iris-setosa", "Iris-setosa", "Iris-setosa", "Iris-setosa", ...]
      >

  This dataframe has 150 rows and five columns. Each column is an `Explorer.Series`
  of the same size (150):

      iex> df = Explorer.Datasets.iris()
      iex> df["sepal_length"]
      #Explorer.Series<
        float[150]
        [5.1, 4.9, 4.7, 4.6, 5.0, 5.4, 4.6, 5.0, 4.4, 4.9, 5.4, 4.8, 4.8, 4.3, 5.8, 5.7, 5.4, 5.1, 5.7, 5.1, 5.4, 5.1, 4.6, 5.1, 4.8, 5.0, 5.0, 5.2, 5.2, 4.7, 4.8, 5.4, 5.2, 5.5, 4.9, 5.0, 5.5, 4.9, 4.4, 5.1, 5.0, 4.5, 4.4, 5.0, 5.1, 4.8, 5.1, 4.6, 5.3, 5.0, ...]
      >

  ## Creating dataframes

  Dataframes can be created from normal Elixir objects. The main ways you might do this are
  `from_columns/1` and `from_rows/1`. For example:

      iex> Explorer.DataFrame.new(a: ["a", "b"], b: [1, 2])
      #Explorer.DataFrame<
        [rows: 2, columns: 2]
        a string ["a", "b"]
        b integer [1, 2]
      >

  ## Verbs

  Explorer uses the idea of a consistent set of SQL-like `verbs` like [`dplyr`](https://dplyr.tidyverse.org)
  which can help solve common data manipulation challenges. These are split into single table verbs and multiple table verbs.

  ### Single table verbs

  Single table verbs are (unsurprisingly) used for manipulating a single dataframe. These are:

  - `select/3` for picking variables
  - `filter/2` for picking rows based on predicates
  - `mutate/2` for adding or replacing columns that are functions of existing columns
  - `arrange/2` for changing the ordering of rows
  - `distinct/2` for picking unique rows
  - `summarise/2` for reducing multiple rows down to a single summary
  - `pivot_longer/3` and `pivot_wider/4` for massaging dataframes into longer or wider forms, respectively

  Each of these combine with `Explorer.DataFrame.group_by/2` for operating by group.

  ### Multiple table verbs

  Multiple table verbs are used for combining tables. These are:

  - `join/3` for performing SQL-like joins
  - `concat_rows/1` for vertically "stacking" dataframes

  ## IO

  Explorer supports reading and writing of:

  - delimited files (such as CSV)
  - [Parquet](https://databricks.com/glossary/what-is-parquet)
  - [Arrow IPC](https://arrow.apache.org/docs/format/Columnar.html#ipc-file-format)
  - [Newline Delimited JSON](http://ndjson.org)

  The convention Explorer uses is to have `from_*` and `to_*` functions to read and write
  to files in the formats above. `load_*` and `dump_*` versions are also available to read
  and write those formats directly in memory.

  ## Access

  In addition to this "grammar" of data manipulation, you'll find useful functions for
  slicing and dicing dataframes such as `pull/2`, `head/2`, `sample/3`, `slice/3`, and
  `take/2`.

  `Explorer.DataFrame` also implements the `Access` behaviour (also known as the brackets
  syntax). This should be familiar for users coming from other language with dataframes
  such as R or Python. For example:

      iex> df = Explorer.Datasets.wine()
      iex> df["class"]
      #Explorer.Series<
        integer[178]
        [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, ...]
      >
  """

  alias __MODULE__, as: DataFrame
  alias Explorer.Series

  import Explorer.Shared, only: [impl!: 1]
  @valid_dtypes Explorer.Shared.dtypes()

  @type data :: Explorer.Backend.DataFrame.t() | Explorer.Backend.LazyDataFrame.t()
  @type t :: %DataFrame{data: data, groups: [String.t()]}
  @enforce_keys [:data, :groups]
  defstruct [:data, :groups]

  @type column_name :: atom() | String.t()
  @type column :: column_name() | non_neg_integer()
  @type columns :: [column] | Range.t()
  @type column_names :: [column_name]
  @type column_pairs(other) :: [{column(), other}] | %{column() => other}

  @default_infer_schema_length 1000

  # Guards and helpers for columns

  defguard is_column(column) when is_binary(column) or is_atom(column) or is_integer(column)
  defguard is_column_name(column) when is_binary(column) or is_atom(column)
  defguard is_column_pairs(columns) when is_list(columns) or is_map(columns)

  # Normalize a column name to string
  defp to_column_name(column) when is_binary(column), do: column
  defp to_column_name(column) when is_atom(column), do: Atom.to_string(column)

  # Normalize pairs of `{column, value}` where value can be anything.
  # The `column` is only validated if it's an integer. We check that the index is present.
  defp to_column_pairs(df, pairs), do: to_column_pairs(df, pairs, & &1)

  # The function allows to change the `value` for each pair.
  defp to_column_pairs(df, pairs, value_fun)
       when is_column_pairs(pairs) and is_function(value_fun, 1) do
    existing_columns = names(df)

    pairs
    |> Enum.map_reduce(nil, fn
      {column, value}, maybe_map when is_integer(column) ->
        map = maybe_map || column_index_map(existing_columns)

        existing_column = fetch_column_at!(map, column)

        {{existing_column, value_fun.(value)}, map}

      {column, value}, maybe_map when is_atom(column) ->
        column = Atom.to_string(column)

        {{column, value_fun.(value)}, maybe_map}

      {column, value}, maybe_map when is_binary(column) ->
        {{column, value_fun.(value)}, maybe_map}
    end)
    |> then(fn {pairs, _} -> pairs end)
  end

  defp fetch_column_at!(map, index) do
    normalized = if index < 0, do: index + map_size(map), else: index

    case map do
      %{^normalized => column} -> column
      %{} -> raise ArgumentError, "no column exists at index #{index}"
    end
  end

  defp column_index_map(names),
    do: for({name, idx} <- Enum.with_index(names), into: %{}, do: {idx, name})

  # Normalize column names without verifying if they exist.
  defp to_column_names(names) when is_list(names),
    do: Enum.map(names, &to_column_name/1)

  # Normalize column names and raise if column does not exist.
  defp to_existing_columns(df, columns) when is_list(columns) do
    existing_columns = names(df)

    columns
    |> Enum.map_reduce(nil, fn
      column, maybe_map when is_integer(column) ->
        map = maybe_map || column_index_map(existing_columns)

        existing_column = fetch_column_at!(map, column)

        {existing_column, map}

      column, maybe_map when is_atom(column) ->
        column = Atom.to_string(column)
        maybe_raise_column_not_found(existing_columns, column)
        {column, maybe_map}

      column, maybe_map when is_binary(column) ->
        maybe_raise_column_not_found(existing_columns, column)
        {column, maybe_map}
    end)
    |> then(fn {columns, _} -> columns end)
  end

  defp to_existing_columns(df, %Range{} = columns) do
    Enum.slice(names(df), columns)
  end

  defp check_dtypes!(dtypes) do
    Enum.map(dtypes, fn
      {key, value} when is_atom(key) ->
        {Atom.to_string(key), check_dtype!(key, value)}

      {key, value} when is_binary(key) ->
        {key, check_dtype!(key, value)}

      _ ->
        raise ArgumentError,
              "dtypes must be a list/map of column names as keys and types as values, " <>
                "where the keys are atoms or binaries. Got: #{inspect(dtypes)}"
    end)
  end

  defp check_dtype!(_key, value) when value in @valid_dtypes, do: value

  defp check_dtype!(key, value) do
    raise ArgumentError,
          "invalid dtype #{inspect(value)} for #{inspect(key)} (expected one of #{inspect(@valid_dtypes)})"
  end

  # Access

  @behaviour Access

  @impl true
  def fetch(df, column) when is_column(column) do
    {:ok, pull(df, column)}
  end

  def fetch(df, columns) do
    columns = to_existing_columns(df, columns)

    {:ok, select(df, columns)}
  end

  @impl true
  def pop(df, column) when is_column(column) do
    [column] = to_existing_columns(df, [column])

    {pull(df, column), select(df, [column], :drop)}
  end

  def pop(df, columns) do
    columns = to_existing_columns(df, columns)

    {select(df, columns), select(df, columns, :drop)}
  end

  @impl true
  def get_and_update(df, column, fun) when is_column(column) do
    [column] = to_existing_columns(df, [column])

    value = pull(df, column)
    {current_value, new_value} = fun.(value)

    new_data = mutate(df, %{column => new_value})
    {current_value, new_data}
  end

  # IO

  @doc """
  Reads a delimited file into a dataframe.

  If the CSV is compressed, it is automatically decompressed.

  ## Options

    * `delimiter` - A single character used to separate fields within a record. (default: `","`)
    * `dtypes` - A list/map of `{"column_name", dtype}` tuples. Any non-specified column has its type
      imputed from the first 1000 rows. (default: `[]`)
    * `header` - Does the file have a header of column names as the first row or not? (default: `true`)
    * `max_rows` - Maximum number of lines to read. (default: `nil`)
    * `null_character` - The string that should be interpreted as a nil value. (default: `"NA"`)
    * `skip_rows` - The number of lines to skip at the beginning of the file. (default: `0`)
    * `columns` - A list of column names or indexes to keep. If present, only these columns are read into the dataframe. (default: `nil`)
    * `infer_schema_length` Maximum number of rows read for schema inference. Setting this to nil will do a full table scan and will be slow (default: `1000`).
    * `parse_dates` - Automatically try to parse dates/ datetimes and time. If parsing fails, columns remain of dtype `string`
  """
  @doc type: :io
  @spec from_csv(filename :: String.t(), opts :: Keyword.t()) ::
          {:ok, DataFrame.t()} | {:error, term()}
  def from_csv(filename, opts \\ []) do
    opts =
      Keyword.validate!(opts,
        delimiter: ",",
        dtypes: [],
        encoding: "utf8",
        header: true,
        max_rows: nil,
        null_character: "NA",
        skip_rows: 0,
        columns: nil,
        infer_schema_length: @default_infer_schema_length,
        parse_dates: false
      )

    backend = backend_from_options!(opts)

    backend.from_csv(
      filename,
      check_dtypes!(opts[:dtypes]),
      opts[:delimiter],
      opts[:null_character],
      opts[:skip_rows],
      opts[:header],
      opts[:encoding],
      opts[:max_rows],
      opts[:columns],
      opts[:infer_schema_length],
      opts[:parse_dates]
    )
  end

  @doc """
  Similar to `from_csv/2` but raises if there is a problem reading the CSV.
  """
  @doc type: :io
  @spec from_csv!(filename :: String.t(), opts :: Keyword.t()) :: DataFrame.t()
  def from_csv!(filename, opts \\ []) do
    case from_csv(filename, opts) do
      {:ok, df} -> df
      {:error, error} -> raise "#{error}"
    end
  end

  @doc """
  Reads a parquet file into a dataframe.
  """
  @doc type: :io
  @spec from_parquet(filename :: String.t(), opts :: Keyword.t()) ::
          {:ok, DataFrame.t()} | {:error, term()}
  def from_parquet(filename, opts \\ []) do
    backend = backend_from_options!(opts)
    backend.from_parquet(filename)
  end

  @doc """
  Writes a dataframe to a parquet file.
  """
  @doc type: :io
  @spec to_parquet(df :: DataFrame.t(), filename :: String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def to_parquet(df, filename) do
    apply_impl(df, :to_parquet, [filename])
  end

  @doc """
  Reads an IPC file into a dataframe.

  ## Options

    * `columns` - List with the name or index of columns to be selected. Defaults to all columns.
  """
  @doc type: :io
  @spec from_ipc(filename :: String.t()) :: {:ok, DataFrame.t()} | {:error, term()}
  def from_ipc(filename, opts \\ []) do
    opts =
      Keyword.validate!(opts,
        columns: nil
      )

    backend = backend_from_options!(opts)

    backend.from_ipc(
      filename,
      opts[:columns]
    )
  end

  @doc """
  Similar to `from_ipc/2` but raises if there is a problem reading the IPC file.
  """
  @doc type: :io
  @spec from_ipc!(filename :: String.t(), opts :: Keyword.t()) :: DataFrame.t()
  def from_ipc!(filename, opts \\ []) do
    case from_ipc(filename, opts) do
      {:ok, df} -> df
      {:error, error} -> raise "#{error}"
    end
  end

  @doc """
  Writes a dataframe to a IPC file.

  Apache IPC is a language-agnostic columnar data structure that can be used to store data frames.
  It excels as a format for quickly exchange data between different programming languages.

  ## Options

    * `compression` - Sets the algorithm used to compress the IPC file.
      It accepts `"ZSTD"` or `"LZ4"` compression. (default: `nil`)
  """
  @doc type: :io
  @spec to_ipc(df :: DataFrame.t(), filename :: String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def to_ipc(df, filename, opts \\ []) do
    opts =
      Keyword.validate!(opts,
        compression: nil
      )

    backend = backend_from_options!(opts)

    backend.to_ipc(
      df,
      filename,
      opts[:compression]
    )
  end

  @doc """
  Writes a dataframe to a delimited file.

  ## Options

    * `header` - Should the column names be written as the first line of the file? (default: `true`)
    * `delimiter` - A single character used to separate fields within a record. (default: `","`)
  """
  @doc type: :io
  @spec to_csv(df :: DataFrame.t(), filename :: String.t(), opts :: Keyword.t()) ::
          {:ok, String.t()} | {:error, term()}
  def to_csv(df, filename, opts \\ []) do
    opts = Keyword.validate!(opts, header: true, delimiter: ",")
    apply_impl(df, :to_csv, [filename, opts[:header], opts[:delimiter]])
  end

  @doc """
  Similar to `to_csv/3` but raises if there is a problem writing the CSV.
  """
  @doc type: :io
  @spec to_csv!(df :: DataFrame.t(), filename :: String.t(), opts :: Keyword.t()) :: String.t()
  def to_csv!(df, filename, opts \\ []) do
    case to_csv(df, filename, opts) do
      {:ok, filename} -> filename
      {:error, error} -> raise "#{error}"
    end
  end

  @doc """
  Read a file of JSON objects or lists separated by new lines

  ## Options

    * `batch_size` - Sets the batch size for reading rows.
    This value may have significant impact in performance, so adjust it for your needs (default: `1000`).

    * `infer_schema_length` - Maximum number of rows read for schema inference.
    Setting this to nil will do a full table scan and will be slow (default: `1000`).
  """
  @doc type: :io
  @spec from_ndjson(filename :: String.t(), opts :: Keyword.t()) ::
          {:ok, DataFrame.t()} | {:error, term()}
  def from_ndjson(filename, opts \\ []) do
    opts =
      Keyword.validate!(opts,
        batch_size: 1000,
        infer_schema_length: @default_infer_schema_length
      )

    backend = backend_from_options!(opts)

    backend.from_ndjson(
      filename,
      opts[:infer_schema_length],
      opts[:batch_size]
    )
  end

  @doc """
  Writes a dataframe to a ndjson file.
  """
  @doc type: :io
  @spec to_ndjson(df :: DataFrame.t(), filename :: String.t()) ::
          {:ok, String.t()} | {:error, term()}
  def to_ndjson(df, filename) do
    apply_impl(df, :to_ndjson, [filename])
  end

  @doc """
  Writes a dataframe to a binary representation of a delimited file.

  ## Options

    * `header` - Should the column names be written as the first line of the file? (default: `true`)
    * `delimiter` - A single character used to separate fields within a record. (default: `","`)

  ## Examples

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> df |> Explorer.DataFrame.head(2) |> Explorer.DataFrame.dump_csv()
      {:ok, "year,country,total,solid_fuel,liquid_fuel,gas_fuel,cement,gas_flaring,per_capita,bunker_fuels\\n2010,AFGHANISTAN,2308,627,1601,74,5,0,0.08,9\\n2010,ALBANIA,1254,117,953,7,177,0,0.43,7\\n"}
  """
  @doc type: :io
  @spec dump_csv(df :: DataFrame.t(), opts :: Keyword.t()) :: {Atom.t(), String.t()} | {:error, term()}
  def dump_csv(df, opts \\ []) do
    opts = Keyword.validate!(opts, header: true, delimiter: ",")
    apply_impl(df, :dump_csv, [opts[:header], opts[:delimiter]])
  end

  @doc """
  Similar to `dump_csv/2` but raises if there is a problem parsing the CSV.

  ## Examples

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> df |> Explorer.DataFrame.head(2) |> Explorer.DataFrame.dump_csv!()
      "year,country,total,solid_fuel,liquid_fuel,gas_fuel,cement,gas_flaring,per_capita,bunker_fuels\\n2010,AFGHANISTAN,2308,627,1601,74,5,0,0.08,9\\n2010,ALBANIA,1254,117,953,7,177,0,0.43,7\\n"
  """
  @doc type: :io
  @spec dump_csv!(df :: DataFrame.t(), opts :: Keyword.t()) :: String.t()
  def dump_csv!(df, opts \\ []) do
    case dump_csv(df, opts) do
      {:ok, df} -> df
      {:error, error} -> raise "#{error}"
    end
  end

  @doc """
  Read a CSV binary from memory.
  """
  @doc type: :io
  @spec load_csv(binary :: String.t(), opts :: Keyword.t()) :: {Atom.t(), DataFrame.t()} | {:error, term()}
  def load_csv(binary, opts \\ []) do
    opts =
      Keyword.validate!(opts,
        header: true,
        max_rows: nil,
        skip_rows: 0,
        projection: nil,
        delimiter: ",",
        columns: nil,
        encoding: "utf8",
        null_character: "NA",
        parse_dates: false
      )

    backend = backend_from_options!(opts)

    backend.load_csv(
      binary,
      opts[:header],
      opts[:max_rows],
      opts[:skip_rows],
      opts[:projection],
      opts[:delimiter],
      opts[:columns],
      opts[:encoding],
      opts[:null_character],
      opts[:parse_dates]
    )
  end

  @doc """
  Similar to `load_csv/2` but raises if there is a problem parsing the binary.
  """
  @doc type: :io
  @spec load_csv!(binary :: String.t(), opts :: Keyword.t()) :: DataFrame.t()
  def load_csv!(binary, opts \\ []) do
    case load_csv(binary, opts) do
      {:ok, df} -> df
      {:error, error} -> raise "#{error}"
    end
  end

  ## Conversion

  @doc """
  Creates a new dataframe.

  Accepts any tabular data adhering to the `Table.Reader` protocol, as well as a map or a keyword list with series.

  ## Options

    * `backend` - The Explorer backend to use. Defaults to the value returned by `Explorer.Backend.get/0`.

  ## Examples

  From series:

      iex> Explorer.DataFrame.new(%{floats: Explorer.Series.from_list([1.0, 2.0]), ints: Explorer.Series.from_list([1, nil])})
      #Explorer.DataFrame<
        [rows: 2, columns: 2]
        floats float [1.0, 2.0]
        ints integer [1, nil]
      >

  From columnar data:

      iex> Explorer.DataFrame.new(%{floats: [1.0, 2.0], ints: [1, nil]})
      #Explorer.DataFrame<
        [rows: 2, columns: 2]
        floats float [1.0, 2.0]
        ints integer [1, nil]
      >

      iex> Explorer.DataFrame.new(floats: [1.0, 2.0], ints: [1, nil])
      #Explorer.DataFrame<
        [rows: 2, columns: 2]
        floats float [1.0, 2.0]
        ints integer [1, nil]
      >

      iex> Explorer.DataFrame.new(%{floats: [1.0, 2.0], ints: [1, "wrong"]})
      ** (ArgumentError) cannot create series "ints": the value "wrong" does not match the inferred series dtype :integer

  From row data:

      iex> rows = [%{id: 1, name: "José"}, %{id: 2, name: "Christopher"}, %{id: 3, name: "Cristine"}]
      iex> Explorer.DataFrame.new(rows)
      #Explorer.DataFrame<
        [rows: 3, columns: 2]
        id integer [1, 2, 3]
        name string ["José", "Christopher", "Cristine"]
      >

      iex> rows = [[id: 1, name: "José"], [id: 2, name: "Christopher"], [id: 3, name: "Cristine"]]
      iex> Explorer.DataFrame.new(rows)
      #Explorer.DataFrame<
        [rows: 3, columns: 2]
        id integer [1, 2, 3]
        name string ["José", "Christopher", "Cristine"]
      >
  """
  @doc type: :single
  @spec new(
          Table.Reader.t() | series_pairs,
          opts :: Keyword.t()
        ) :: DataFrame.t()
        when series_pairs: %{column_name() => Series.t()} | [{column_name(), Series.t()}]
  def new(data, opts \\ []) do
    backend = backend_from_options!(opts)

    case data do
      %DataFrame{data: %^backend{}} ->
        data

      data ->
        case classify_data(data) do
          {:series, series} -> backend.from_series(series)
          {:other, tabular} -> backend.from_tabular(tabular)
        end
    end
  end

  defp classify_data([{_, %Series{}} | _] = data), do: {:series, data}

  defp classify_data(%_{} = data), do: {:other, data}

  defp classify_data(data) when is_map(data) do
    case :maps.next(:maps.iterator(data)) do
      {_key, %Series{}, _} -> {:series, data}
      _ -> {:other, data}
    end
  end

  defp classify_data(data), do: {:other, data}

  @doc """
  Converts a dataframe to a list of columns with lists as values.

  See `to_series/2` if you want a list of columns with series as values.

  ## Options

    * `:atom_keys` - Configure if the resultant map should have atom keys. (default: `false`)

  ## Examples

      iex> df = Explorer.DataFrame.new(ints: [1, nil], floats: [1.0, 2.0])
      iex> Explorer.DataFrame.to_columns(df)
      %{"floats" => [1.0, 2.0], "ints" => [1, nil]}

      iex> df = Explorer.DataFrame.new(floats: [1.0, 2.0], ints: [1, nil])
      iex> Explorer.DataFrame.to_columns(df, atom_keys: true)
      %{floats: [1.0, 2.0], ints: [1, nil]}

  """
  @doc type: :single
  @spec to_columns(df :: DataFrame.t(), Keyword.t()) :: map()
  def to_columns(df, opts \\ []) do
    opts = Keyword.validate!(opts, atom_keys: false)
    atom_keys = opts[:atom_keys]

    for name <- names(df), into: %{} do
      series = apply_impl(df, :pull, [name])
      key = if atom_keys, do: String.to_atom(name), else: name
      {key, Series.to_list(series)}
    end
  end

  @doc """
  Converts a dataframe to a list of columns with series as values.

  See `to_columns/2` if you want a list of columns with lists as values.

  ## Options

    * `:atom_keys` - Configure if the resultant map should have atom keys. (default: `false`)

  ## Examples

      iex> df = Explorer.DataFrame.new(ints: [1, nil], floats: [1.0, 2.0])
      iex> map = Explorer.DataFrame.to_series(df)
      iex> Explorer.Series.to_list(map["floats"])
      [1.0, 2.0]
      iex> Explorer.Series.to_list(map["ints"])
      [1, nil]

  """
  @doc type: :single
  @spec to_series(df :: DataFrame.t(), Keyword.t()) :: map()
  def to_series(df, opts \\ []) do
    opts = Keyword.validate!(opts, atom_keys: false)
    atom_keys = opts[:atom_keys]

    for name <- names(df), into: %{} do
      key = if atom_keys, do: String.to_atom(name), else: name
      {key, apply_impl(df, :pull, [name])}
    end
  end

  @doc """
  Converts a dataframe to a list of maps (rows).

  > #### Warning {: .warning}
  >
  > This may be an expensive operation because `polars` stores data in columnar format.

  ## Options

    * `:atom_keys` - Configure if the resultant maps should have atom keys. (default: `false`)

  ## Examples

      iex> df = Explorer.DataFrame.new(floats: [1.0, 2.0], ints: [1, nil])
      iex> Explorer.DataFrame.to_rows(df)
      [%{"floats" => 1.0, "ints" => 1}, %{"floats" => 2.0 ,"ints" => nil}]

      iex> df = Explorer.DataFrame.new(floats: [1.0, 2.0], ints: [1, nil])
      iex> Explorer.DataFrame.to_rows(df, atom_keys: true)
      [%{floats: 1.0, ints: 1}, %{floats: 2.0, ints: nil}]
  """
  @doc type: :single
  @spec to_rows(df :: DataFrame.t(), Keyword.t()) :: [map()]
  def to_rows(df, opts \\ []) do
    opts = Keyword.validate!(opts, atom_keys: false)

    apply_impl(df, :to_rows, [opts[:atom_keys]])
  end

  # Introspection

  @doc """
  Gets the names of the dataframe columns.

  ## Examples

      iex> df = Explorer.DataFrame.new(floats: [1.0, 2.0], ints: [1, 2])
      iex> Explorer.DataFrame.names(df)
      ["floats", "ints"]
  """
  @doc type: :introspection
  @spec names(df :: DataFrame.t()) :: [String.t()]
  def names(df), do: apply_impl(df, :names)

  @doc """
  Gets the dtypes of the dataframe columns.

  ## Examples

      iex> df = Explorer.DataFrame.new(floats: [1.0, 2.0], ints: [1, 2])
      iex> Explorer.DataFrame.dtypes(df)
      [:float, :integer]
  """
  @doc type: :introspection
  @spec dtypes(df :: DataFrame.t()) :: [atom()]
  def dtypes(df), do: apply_impl(df, :dtypes)

  @doc """
  Gets the shape of the dataframe as a `{height, width}` tuple.

  ## Examples

      iex> df = Explorer.DataFrame.new(floats: [1.0, 2.0, 3.0], ints: [1, 2, 3])
      iex> Explorer.DataFrame.shape(df)
      {3, 2}
  """
  @doc type: :introspection
  @spec shape(df :: DataFrame.t()) :: {integer(), integer()}
  def shape(df), do: apply_impl(df, :shape)

  @doc """
  Returns the number of rows in the dataframe.

  ## Examples

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.n_rows(df)
      1094
  """
  @doc type: :introspection
  @spec n_rows(df :: DataFrame.t()) :: integer()
  def n_rows(df), do: apply_impl(df, :n_rows)

  @doc """
  Returns the number of columns in the dataframe.

  ## Examples

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.n_columns(df)
      10
  """
  @doc type: :introspection
  @spec n_columns(df :: DataFrame.t()) :: integer()
  def n_columns(df), do: apply_impl(df, :n_columns)

  @doc """
  Returns the groups of a dataframe.

  ## Examples

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> df = Explorer.DataFrame.group_by(df, "country")
      iex> Explorer.DataFrame.groups(df)
      ["country"]
  """
  @doc type: :introspection
  @spec groups(df :: DataFrame.t()) :: list(String.t())
  def groups(%DataFrame{groups: groups}), do: groups

  # Single table verbs

  @doc """
  Returns the first *n* rows of the dataframe.

  ## Examples

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.head(df)
      #Explorer.DataFrame<
        [rows: 5, columns: 10]
        year integer [2010, 2010, 2010, 2010, 2010]
        country string ["AFGHANISTAN", "ALBANIA", "ALGERIA", "ANDORRA", "ANGOLA"]
        total integer [2308, 1254, 32500, 141, 7924]
        solid_fuel integer [627, 117, 332, 0, 0]
        liquid_fuel integer [1601, 953, 12381, 141, 3649]
        gas_fuel integer [74, 7, 14565, 0, 374]
        cement integer [5, 177, 2598, 0, 204]
        gas_flaring integer [0, 0, 2623, 0, 3697]
        per_capita float [0.08, 0.43, 0.9, 1.68, 0.37]
        bunker_fuels integer [9, 7, 663, 0, 321]
      >
  """
  @doc type: :single
  @spec head(df :: DataFrame.t(), nrows :: integer()) :: DataFrame.t()
  def head(df, nrows \\ 5), do: apply_impl(df, :head, [nrows])

  @doc """
  Returns the last *n* rows of the dataframe.

  ## Examples

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.tail(df)
      #Explorer.DataFrame<
        [rows: 5, columns: 10]
        year integer [2014, 2014, 2014, 2014, 2014]
        country string ["VIET NAM", "WALLIS AND FUTUNA ISLANDS", "YEMEN", "ZAMBIA", "ZIMBABWE"]
        total integer [45517, 6, 6190, 1228, 3278]
        solid_fuel integer [19246, 0, 137, 132, 2097]
        liquid_fuel integer [12694, 6, 5090, 797, 1005]
        gas_fuel integer [5349, 0, 581, 0, 0]
        cement integer [8229, 0, 381, 299, 177]
        gas_flaring integer [0, 0, 0, 0, 0]
        per_capita float [0.49, 0.44, 0.24, 0.08, 0.22]
        bunker_fuels integer [761, 1, 153, 33, 9]
      >
  """
  @doc type: :single
  @spec tail(df :: DataFrame.t(), nrows :: integer()) :: DataFrame.t()
  def tail(df, nrows \\ 5), do: apply_impl(df, :tail, [nrows])

  @doc """
  Selects a subset of columns by name.

  Can optionally return all *but* the named columns if `:drop` is passed as the last argument.

  ## Examples

  You can select columns with a list of names:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3])
      iex> Explorer.DataFrame.select(df, ["a"])
      #Explorer.DataFrame<
        [rows: 3, columns: 1]
        a string ["a", "b", "c"]
      >


  You can also use a range or a list of integers:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3], c: [4, 5, 6])
      iex> Explorer.DataFrame.select(df, [0, 1])
      #Explorer.DataFrame<
        [rows: 3, columns: 2]
        a string ["a", "b", "c"]
        b integer [1, 2, 3]
      >

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3], c: [4, 5, 6])
      iex> Explorer.DataFrame.select(df, 0..1)
      #Explorer.DataFrame<
        [rows: 3, columns: 2]
        a string ["a", "b", "c"]
        b integer [1, 2, 3]
      >

  Or you can use a callback function that takes the dataframe's names as its first argument:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3])
      iex> Explorer.DataFrame.select(df, &String.starts_with?(&1, "b"))
      #Explorer.DataFrame<
        [rows: 3, columns: 1]
        b integer [1, 2, 3]
      >

  If you pass `:drop` as the third argument, it will return all but the named columns:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3])
      iex> Explorer.DataFrame.select(df, ["b"], :drop)
      #Explorer.DataFrame<
        [rows: 3, columns: 1]
        a string ["a", "b", "c"]
      >

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3], c: [4, 5, 6])
      iex> Explorer.DataFrame.select(df, ["a", "b"], :drop)
      #Explorer.DataFrame<
        [rows: 3, columns: 1]
        c integer [4, 5, 6]
      >

  """
  @doc type: :single
  @spec select(
          df :: DataFrame.t(),
          columns_or_callback :: columns() | function(),
          keep_or_drop ::
            :keep | :drop
        ) :: DataFrame.t()
  def select(df, columns_or_callback, keep_or_drop \\ :keep)

  def select(df, callback, keep_or_drop) when is_function(callback),
    do: df |> names() |> Enum.filter(callback) |> then(&select(df, &1, keep_or_drop))

  def select(df, columns, keep_or_drop) do
    columns = to_existing_columns(df, columns)

    apply_impl(df, :select, [columns, keep_or_drop])
  end

  @doc """
  Subset rows using column values.

  ## Examples

  You can pass a mask directly:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3])
      iex> Explorer.DataFrame.filter(df, Explorer.Series.greater(df["b"], 1))
      #Explorer.DataFrame<
        [rows: 2, columns: 2]
        a string ["b", "c"]
        b integer [2, 3]
      >

  You can combine masks using `Explorer.Series.and/2` or `Explorer.Series.or/2`:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3])
      iex> b_gt = Explorer.Series.greater(df["b"], 1)
      iex> a_eq = Explorer.Series.equal(df["a"], "b")
      iex> Explorer.DataFrame.filter(df, Explorer.Series.and(a_eq, b_gt))
      #Explorer.DataFrame<
        [rows: 1, columns: 2]
        a string ["b"]
        b integer [2]
      >

  Including a list:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3])
      iex> Explorer.DataFrame.filter(df, [false, true, false])
      #Explorer.DataFrame<
        [rows: 1, columns: 2]
        a string ["b"]
        b integer [2]
      >

  Or you can invoke a callback on the dataframe:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3])
      iex> Explorer.DataFrame.filter(df, &Explorer.Series.greater(&1["b"], 1))
      #Explorer.DataFrame<
        [rows: 2, columns: 2]
        a string ["b", "c"]
        b integer [2, 3]
      >
  """
  @doc type: :single
  @spec filter(df :: DataFrame.t(), mask :: Series.t() | [boolean()]) :: DataFrame.t()
  def filter(df, %Series{} = mask) do
    s_len = Series.size(mask)
    df_len = n_rows(df)

    case s_len == df_len do
      false ->
        raise(
          ArgumentError,
          "size of the mask (#{s_len}) must match number of rows in the dataframe (#{df_len})"
        )

      true ->
        apply_impl(df, :filter, [mask])
    end
  end

  def filter(df, mask) when is_list(mask), do: mask |> Series.from_list() |> then(&filter(df, &1))

  @spec filter(df :: DataFrame.t(), callback :: function()) :: DataFrame.t()
  def filter(df, callback) when is_function(callback),
    do:
      df
      |> callback.()
      |> then(
        &filter(
          df,
          &1
        )
      )

  @doc """
  Creates and modifies columns.

  Columns are added with keyword list or maps. New variables overwrite existing variables of the
  same name. Column names are coerced from atoms to strings.

  ## Examples

  You can pass in a list directly as a new column:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3])
      iex> Explorer.DataFrame.mutate(df, c: [4, 5, 6])
      #Explorer.DataFrame<
        [rows: 3, columns: 3]
        a string ["a", "b", "c"]
        b integer [1, 2, 3]
        c integer [4, 5, 6]
      >

  Or you can pass in a series:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3])
      iex> s = Explorer.Series.from_list([4, 5, 6])
      iex> Explorer.DataFrame.mutate(df, c: s)
      #Explorer.DataFrame<
        [rows: 3, columns: 3]
        a string ["a", "b", "c"]
        b integer [1, 2, 3]
        c integer [4, 5, 6]
      >

  Or you can invoke a callback on the dataframe:

      iex> df = Explorer.DataFrame.new(a: [4, 5, 6], b: [1, 2, 3])
      iex> Explorer.DataFrame.mutate(df, c: &Explorer.Series.add(&1["a"], &1["b"]))
      #Explorer.DataFrame<
        [rows: 3, columns: 3]
        a integer [4, 5, 6]
        b integer [1, 2, 3]
        c integer [5, 7, 9]
      >

  You can overwrite existing columns:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3])
      iex> Explorer.DataFrame.mutate(df, a: [4, 5, 6])
      #Explorer.DataFrame<
        [rows: 3, columns: 2]
        a integer [4, 5, 6]
        b integer [1, 2, 3]
      >

  Scalar values are repeated to fill the series:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3])
      iex> Explorer.DataFrame.mutate(df, a: 4)
      #Explorer.DataFrame<
        [rows: 3, columns: 2]
        a integer [4, 4, 4]
        b integer [1, 2, 3]
      >

  Including when a callback returns a scalar:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3])
      iex> Explorer.DataFrame.mutate(df, a: &Explorer.Series.max(&1["b"]))
      #Explorer.DataFrame<
        [rows: 3, columns: 2]
        a integer [3, 3, 3]
        b integer [1, 2, 3]
      >

  Alternatively, all of the above works with a map instead of a keyword list:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "c"], b: [1, 2, 3])
      iex> Explorer.DataFrame.mutate(df, %{"c" => [4, 5, 6]})
      #Explorer.DataFrame<
        [rows: 3, columns: 3]
        a string ["a", "b", "c"]
        b integer [1, 2, 3]
        c integer [4, 5, 6]
      >
  """
  @doc type: :single
  @spec mutate(df :: DataFrame.t(), columns :: column_pairs(any())) ::
          DataFrame.t()
  def mutate(df, columns) when is_column_pairs(columns) do
    pairs = to_column_pairs(df, columns)

    apply_impl(df, :mutate, [Map.new(pairs)])
  end

  @doc """
  Arranges/sorts rows by columns.

  ## Examples

  A single column name will sort ascending by that column:

      iex> df = Explorer.DataFrame.new(a: ["b", "c", "a"], b: [1, 2, 3])
      iex> Explorer.DataFrame.arrange(df, "a")
      #Explorer.DataFrame<
        [rows: 3, columns: 2]
        a string ["a", "b", "c"]
        b integer [3, 1, 2]
      >

  You can also sort descending:

      iex> df = Explorer.DataFrame.new(a: ["b", "c", "a"], b: [1, 2, 3])
      iex> Explorer.DataFrame.arrange(df, desc: "a")
      #Explorer.DataFrame<
        [rows: 3, columns: 2]
        a string ["c", "b", "a"]
        b integer [2, 1, 3]
      >

  Sorting by more than one column sorts them in the order they are entered:

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.arrange(df, asc: "total", desc: "country")
      #Explorer.DataFrame<
        [rows: 1094, columns: 10]
        year integer [2010, 2012, 2011, 2013, 2014, ...]
        country string ["ZIMBABWE", "ZIMBABWE", "ZIMBABWE", "ZIMBABWE", "ZIMBABWE", ...]
        total integer [2121, 2125, 2608, 3184, 3278, ...]
        solid_fuel integer [1531, 917, 1584, 1902, 2097, ...]
        liquid_fuel integer [481, 1006, 888, 1119, 1005, ...]
        gas_fuel integer [0, 0, 0, 0, 0, ...]
        cement integer [109, 201, 136, 162, 177, ...]
        gas_flaring integer [0, 0, 0, 0, 0, ...]
        per_capita float [0.15, 0.15, 0.18, 0.21, 0.22, ...]
        bunker_fuels integer [7, 9, 8, 9, 9, ...]
      >
  """
  @doc type: :single
  @spec arrange(
          df :: DataFrame.t(),
          columns ::
            column() | [column() | {:asc | :desc, column()}]
        ) :: DataFrame.t()
  def arrange(df, columns) when is_list(columns) do
    {dirs, columns} =
      Enum.map(columns, fn
        {dir, column} when dir in [:asc, :desc] and is_column(column) ->
          {dir, column}

        column when is_column(column) ->
          {:asc, column}

        other ->
          raise ArgumentError, "not a valid column or arrange instruction: #{inspect(other)}"
      end)
      |> Enum.unzip()

    columns = to_existing_columns(df, columns)

    apply_impl(df, :arrange, [Enum.zip(dirs, columns)])
  end

  def arrange(df, column) when is_column(column), do: arrange(df, [column])

  @doc """
  Takes distinct rows by a selection of columns.

  ## Examples

  By default will return unique values of the requested columns:

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.distinct(df, columns: ["year", "country"])
      #Explorer.DataFrame<
        [rows: 1094, columns: 2]
        year integer [2010, 2010, 2010, 2010, 2010, ...]
        country string ["AFGHANISTAN", "ALBANIA", "ALGERIA", "ANDORRA", "ANGOLA", ...]
      >

  If `keep_all?` is set to `true`, then the first value of each column not in the requested
  columns will be returned:

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.distinct(df, columns: ["year", "country"], keep_all?: true)
      #Explorer.DataFrame<
        [rows: 1094, columns: 10]
        year integer [2010, 2010, 2010, 2010, 2010, ...]
        country string ["AFGHANISTAN", "ALBANIA", "ALGERIA", "ANDORRA", "ANGOLA", ...]
        total integer [2308, 1254, 32500, 141, 7924, ...]
        solid_fuel integer [627, 117, 332, 0, 0, ...]
        liquid_fuel integer [1601, 953, 12381, 141, 3649, ...]
        gas_fuel integer [74, 7, 14565, 0, 374, ...]
        cement integer [5, 177, 2598, 0, 204, ...]
        gas_flaring integer [0, 0, 2623, 0, 3697, ...]
        per_capita float [0.08, 0.43, 0.9, 1.68, 0.37, ...]
        bunker_fuels integer [9, 7, 663, 0, 321, ...]
      >

  A callback on the dataframe's names can be passed instead of a list (like `select/3`):

      iex> df = Explorer.DataFrame.new(x1: [1, 3, 3], x2: ["a", "c", "c"], y1: [1, 2, 3])
      iex> Explorer.DataFrame.distinct(df, columns: &String.starts_with?(&1, "x"))
      #Explorer.DataFrame<
        [rows: 2, columns: 2]
        x1 integer [1, 3]
        x2 string ["a", "c"]
      >
  """
  @doc type: :single
  @spec distinct(df :: DataFrame.t(), opts :: Keyword.t()) :: DataFrame.t()
  def distinct(df, opts \\ [])

  def distinct(df, opts) do
    opts = Keyword.validate!(opts, columns: nil, keep_all?: false)

    columns =
      case opts[:columns] do
        nil ->
          names(df)

        callback when is_function(callback) ->
          Enum.filter(names(df), callback)

        columns ->
          to_existing_columns(df, columns)
      end

    if columns != [] do
      apply_impl(df, :distinct, [columns, opts[:keep_all?]])
    else
      df
    end
  end

  @doc """
  Drop nil values.

  Optionally accepts a subset of columns.

  ## Examples

      iex> df = Explorer.DataFrame.new(a: [1, 2, nil], b: [1, nil, 3])
      iex> Explorer.DataFrame.drop_nil(df)
      #Explorer.DataFrame<
        [rows: 1, columns: 2]
        a integer [1]
        b integer [1]
      >

      iex> df = Explorer.DataFrame.new(a: [1, 2, nil], b: [1, nil, 3], c: [nil, 5, 6])
      iex> Explorer.DataFrame.drop_nil(df, [:a, :c])
      #Explorer.DataFrame<
        [rows: 1, columns: 3]
        a integer [2]
        b integer [nil]
        c integer [5]
      >

      iex> df = Explorer.DataFrame.new(a: [1, 2, nil], b: [1, nil, 3], c: [nil, 5, 6])
      iex> Explorer.DataFrame.drop_nil(df, 0..1)
      #Explorer.DataFrame<
        [rows: 1, columns: 3]
        a integer [1]
        b integer [1]
        c integer [nil]
      >
  """
  @doc type: :single
  @spec drop_nil(df :: DataFrame.t(), columns_or_column :: column() | columns()) ::
          DataFrame.t()
  def drop_nil(df, columns_or_column \\ 0..-1)

  def drop_nil(df, column) when is_column(column), do: drop_nil(df, [column])

  def drop_nil(df, columns) do
    columns = to_existing_columns(df, columns)

    apply_impl(df, :drop_nil, [columns])
  end

  @doc """
  Renames columns.

  To apply a function to a subset of columns, see `rename_with/3`.

  ## Examples

  You can pass in a list of new names:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "a"], b: [1, 3, 1])
      iex> Explorer.DataFrame.rename(df, ["c", "d"])
      #Explorer.DataFrame<
        [rows: 3, columns: 2]
        c string ["a", "b", "a"]
        d integer [1, 3, 1]
      >

  Or you can rename individual columns using keyword args:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "a"], b: [1, 3, 1])
      iex> Explorer.DataFrame.rename(df, a: "first")
      #Explorer.DataFrame<
        [rows: 3, columns: 2]
        first string ["a", "b", "a"]
        b integer [1, 3, 1]
      >

  Or you can rename individual columns using a map:

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "a"], b: [1, 3, 1])
      iex> Explorer.DataFrame.rename(df, %{"a" => "first"})
      #Explorer.DataFrame<
        [rows: 3, columns: 2]
        first string ["a", "b", "a"]
        b integer [1, 3, 1]
      >

  """
  @doc type: :single
  @spec rename(
          df :: DataFrame.t(),
          names :: column_names() | column_pairs(column_name())
        ) ::
          DataFrame.t()
  def rename(df, [name | _] = names) when is_column_name(name) do
    new_names = to_column_names(names)
    check_new_names_length!(df, new_names)
    apply_impl(df, :rename, [new_names])
  end

  def rename(df, names) when is_column_pairs(names) do
    pairs = to_column_pairs(df, names, &to_column_name(&1))
    old_names = names(df)

    for {name, _} <- pairs do
      maybe_raise_column_not_found(old_names, name)
    end

    pairs_map = Map.new(pairs)

    old_names
    |> Enum.map(fn name -> Map.get(pairs_map, name, name) end)
    |> then(&rename(df, &1))
  end

  defp check_new_names_length!(df, names) do
    width = n_columns(df)
    n_new_names = length(names)

    if width != n_new_names,
      do:
        raise(
          ArgumentError,
          "list of new names must match the number of columns in the dataframe; found " <>
            "#{n_new_names} new name(s), but the supplied dataframe has #{width} column(s)"
        )
  end

  @doc """
  Renames columns with a function.

  ## Examples

  If no columns are specified, it will apply the function to all column names:

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.rename_with(df, &String.upcase/1)
      #Explorer.DataFrame<
        [rows: 1094, columns: 10]
        YEAR integer [2010, 2010, 2010, 2010, 2010, ...]
        COUNTRY string ["AFGHANISTAN", "ALBANIA", "ALGERIA", "ANDORRA", "ANGOLA", ...]
        TOTAL integer [2308, 1254, 32500, 141, 7924, ...]
        SOLID_FUEL integer [627, 117, 332, 0, 0, ...]
        LIQUID_FUEL integer [1601, 953, 12381, 141, 3649, ...]
        GAS_FUEL integer [74, 7, 14565, 0, 374, ...]
        CEMENT integer [5, 177, 2598, 0, 204, ...]
        GAS_FLARING integer [0, 0, 2623, 0, 3697, ...]
        PER_CAPITA float [0.08, 0.43, 0.9, 1.68, 0.37, ...]
        BUNKER_FUELS integer [9, 7, 663, 0, 321, ...]
      >

  A callback can be used to filter the column names that will be renamed, similarly to `select/3`:

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.rename_with(df, &String.ends_with?(&1, "_fuel"), &String.trim_trailing(&1, "_fuel"))
      #Explorer.DataFrame<
        [rows: 1094, columns: 10]
        year integer [2010, 2010, 2010, 2010, 2010, ...]
        country string ["AFGHANISTAN", "ALBANIA", "ALGERIA", "ANDORRA", "ANGOLA", ...]
        total integer [2308, 1254, 32500, 141, 7924, ...]
        solid integer [627, 117, 332, 0, 0, ...]
        liquid integer [1601, 953, 12381, 141, 3649, ...]
        gas integer [74, 7, 14565, 0, 374, ...]
        cement integer [5, 177, 2598, 0, 204, ...]
        gas_flaring integer [0, 0, 2623, 0, 3697, ...]
        per_capita float [0.08, 0.43, 0.9, 1.68, 0.37, ...]
        bunker_fuels integer [9, 7, 663, 0, 321, ...]
      >

  Or you can just pass in the list of column names you'd like to apply the function to:

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.rename_with(df, ["total", "cement"], &String.upcase/1)
      #Explorer.DataFrame<
        [rows: 1094, columns: 10]
        year integer [2010, 2010, 2010, 2010, 2010, ...]
        country string ["AFGHANISTAN", "ALBANIA", "ALGERIA", "ANDORRA", "ANGOLA", ...]
        TOTAL integer [2308, 1254, 32500, 141, 7924, ...]
        solid_fuel integer [627, 117, 332, 0, 0, ...]
        liquid_fuel integer [1601, 953, 12381, 141, 3649, ...]
        gas_fuel integer [74, 7, 14565, 0, 374, ...]
        CEMENT integer [5, 177, 2598, 0, 204, ...]
        gas_flaring integer [0, 0, 2623, 0, 3697, ...]
        per_capita float [0.08, 0.43, 0.9, 1.68, 0.37, ...]
        bunker_fuels integer [9, 7, 663, 0, 321, ...]
      >
  """
  @doc type: :single
  @spec rename_with(
          df :: DataFrame.t(),
          columns :: columns() | function(),
          callback :: function()
        ) ::
          DataFrame.t()
  def rename_with(df, columns \\ 0..-1, callback)

  def rename_with(df, columns, callback) when is_function(callback) and is_function(columns) do
    case df |> names() |> Enum.filter(columns) do
      [column | _] = columns when is_column(column) ->
        rename_with(df, columns, callback)

      [] ->
        df
    end
  end

  def rename_with(df, 0..-1//1, callback) when is_function(callback) do
    df
    |> names()
    |> Enum.map(callback)
    |> then(&rename(df, &1))
  end

  def rename_with(df, columns, callback) when is_function(callback) do
    columns = to_existing_columns(df, columns)

    df
    |> names()
    |> Enum.map(fn name -> if name in columns, do: callback.(name), else: name end)
    |> then(&rename(df, &1))
  end

  @doc """
  Turns a set of columns to dummy variables.

  ## Examples

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "a", "c"], b: ["b", "a", "b", "d"])
      iex> Explorer.DataFrame.dummies(df, ["a"])
      #Explorer.DataFrame<
        [rows: 4, columns: 3]
        a_a integer [1, 0, 1, 0]
        a_b integer [0, 1, 0, 0]
        a_c integer [0, 0, 0, 1]
      >

      iex> df = Explorer.DataFrame.new(a: ["a", "b", "a", "c"], b: ["b", "a", "b", "d"])
      iex> Explorer.DataFrame.dummies(df, ["a", "b"])
      #Explorer.DataFrame<
        [rows: 4, columns: 6]
        a_a integer [1, 0, 1, 0]
        a_b integer [0, 1, 0, 0]
        a_c integer [0, 0, 0, 1]
        b_a integer [0, 1, 0, 0]
        b_b integer [1, 0, 1, 0]
        b_d integer [0, 0, 0, 1]
      >
  """
  @doc type: :single
  def dummies(df, columns),
    do: apply_impl(df, :dummies, [to_existing_columns(df, columns)])

  @doc """
  Extracts a single column as a series.

  ## Examples

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.pull(df, "total")
      #Explorer.Series<
        integer[1094]
        [2308, 1254, 32500, 141, 7924, 41, 143, 51246, 1150, 684, 106589, 18408, 8366, 451, 7981, 16345, 403, 17192, 30222, 147, 1388, 166, 133, 5802, 1278, 114468, 47, 2237, 12030, 535, 58, 1367, 145806, 152, 152, 72, 141, 19703, 2393248, 20773, 44, 540, 19, 2064, 1900, 5501, 10465, 2102, 30428, 18122, ...]
      >

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.pull(df, 2)
      #Explorer.Series<
        integer[1094]
        [2308, 1254, 32500, 141, 7924, 41, 143, 51246, 1150, 684, 106589, 18408, 8366, 451, 7981, 16345, 403, 17192, 30222, 147, 1388, 166, 133, 5802, 1278, 114468, 47, 2237, 12030, 535, 58, 1367, 145806, 152, 152, 72, 141, 19703, 2393248, 20773, 44, 540, 19, 2064, 1900, 5501, 10465, 2102, 30428, 18122, ...]
      >
  """
  @doc type: :single
  @spec pull(df :: DataFrame.t(), column :: column()) :: Series.t()
  def pull(df, column) when is_column(column) do
    [column] = to_existing_columns(df, [column])

    apply_impl(df, :pull, [column])
  end

  @doc """
  Subset a continuous set of rows.

  ## Examples

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.slice(df, 1, 2)
      #Explorer.DataFrame<
        [rows: 2, columns: 10]
        year integer [2010, 2010]
        country string ["ALBANIA", "ALGERIA"]
        total integer [1254, 32500]
        solid_fuel integer [117, 332]
        liquid_fuel integer [953, 12381]
        gas_fuel integer [7, 14565]
        cement integer [177, 2598]
        gas_flaring integer [0, 2623]
        per_capita float [0.43, 0.9]
        bunker_fuels integer [7, 663]
      >

  Negative offsets count from the end of the series:

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.slice(df, -10, 2)
      #Explorer.DataFrame<
        [rows: 2, columns: 10]
        year integer [2014, 2014]
        country string ["UNITED STATES OF AMERICA", "URUGUAY"]
        total integer [1432855, 1840]
        solid_fuel integer [450047, 2]
        liquid_fuel integer [576531, 1700]
        gas_fuel integer [390719, 25]
        cement integer [11314, 112]
        gas_flaring integer [4244, 0]
        per_capita float [4.43, 0.54]
        bunker_fuels integer [30722, 251]
      >

  If the length would run past the end of the dataframe, the result may be shorter than the length:

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.slice(df, -10, 20)
      #Explorer.DataFrame<
        [rows: 10, columns: 10]
        year integer [2014, 2014, 2014, 2014, 2014, ...]
        country string ["UNITED STATES OF AMERICA", "URUGUAY", "UZBEKISTAN", "VANUATU", "VENEZUELA", ...]
        total integer [1432855, 1840, 28692, 42, 50510, ...]
        solid_fuel integer [450047, 2, 1677, 0, 204, ...]
        liquid_fuel integer [576531, 1700, 2086, 42, 28445, ...]
        gas_fuel integer [390719, 25, 23929, 0, 12731, ...]
        cement integer [11314, 112, 1000, 0, 1088, ...]
        gas_flaring integer [4244, 0, 0, 0, 8042, ...]
        per_capita float [4.43, 0.54, 0.97, 0.16, 1.65, ...]
        bunker_fuels integer [30722, 251, 0, 10, 1256, ...]
      >
  """
  @doc type: :single
  def slice(df, offset, length), do: apply_impl(df, :slice, [offset, length])

  @doc """
  Subset rows with a list of indices.

  ## Examples

      iex> df = Explorer.DataFrame.new(a: [1, 2, 3], b: ["a", "b", "c"])
      iex> Explorer.DataFrame.take(df, [0, 2])
      #Explorer.DataFrame<
        [rows: 2, columns: 2]
        a integer [1, 3]
        b string ["a", "c"]
      >
  """
  @doc type: :single
  def take(df, row_indices) when is_list(row_indices) do
    n_rows = n_rows(df)

    Enum.each(row_indices, fn idx ->
      if idx > n_rows or idx < -n_rows,
        do:
          raise(
            ArgumentError,
            "requested row index (#{idx}) out of bounds (-#{n_rows}:#{n_rows})"
          )
    end)

    apply_impl(df, :take, [row_indices])
  end

  @doc """
  Sample rows from a dataframe.

  If given an integer as the second argument, it will return N samples. If given a float, it will
  return that proportion of the series.

  Can sample with or without replacement.

  ## Options

    * `replacement` - If set to `true`, each sample will be independent and therefore values may repeat.
      Required to be `true` for `n` greater then the number of rows in the dataframe or `frac` > 1.0. (default: `false`)
    * `seed` - An integer to be used as a random seed. If nil, a random value between 1 and 1e12 will be used. (default: nil)

  ## Examples

  You can sample N rows:

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.sample(df, 3, seed: 100)
      #Explorer.DataFrame<
        [rows: 3, columns: 10]
        year integer [2012, 2012, 2013]
        country string ["ZIMBABWE", "NICARAGUA", "NIGER"]
        total integer [2125, 1260, 529]
        solid_fuel integer [917, 0, 93]
        liquid_fuel integer [1006, 1176, 432]
        gas_fuel integer [0, 0, 0]
        cement integer [201, 84, 4]
        gas_flaring integer [0, 0, 0]
        per_capita float [0.15, 0.21, 0.03]
        bunker_fuels integer [9, 18, 19]
      >

  Or you can sample a proportion of rows:

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.sample(df, 0.03, seed: 100)
      #Explorer.DataFrame<
        [rows: 33, columns: 10]
        year integer [2013, 2012, 2013, 2012, 2010, ...]
        country string ["BAHAMAS", "POLAND", "SLOVAKIA", "MOZAMBIQUE", "OMAN", ...]
        total integer [764, 81792, 9024, 851, 12931, ...]
        solid_fuel integer [1, 53724, 3657, 11, 0, ...]
        liquid_fuel integer [763, 17353, 2090, 632, 2331, ...]
        gas_fuel integer [0, 8544, 2847, 47, 9309, ...]
        cement integer [0, 2165, 424, 161, 612, ...]
        gas_flaring integer [0, 6, 7, 0, 679, ...]
        per_capita float [2.02, 2.12, 1.67, 0.03, 4.39, ...]
        bunker_fuels integer [167, 573, 34, 56, 1342, ...]
      >

  """
  @doc type: :single
  @spec sample(df :: DataFrame.t(), n_or_frac :: number(), opts :: Keyword.t()) :: DataFrame.t()
  def sample(df, n_or_frac, opts \\ [])

  def sample(df, n, opts) when is_integer(n) do
    opts = Keyword.validate!(opts, replacement: false, seed: Enum.random(1..1_000_000_000_000))

    n_rows = n_rows(df)

    case {n > n_rows, opts[:replacement]} do
      {true, false} ->
        raise ArgumentError,
              "in order to sample more rows than are in the dataframe (#{n_rows}), sampling " <>
                "`replacement` must be true"

      _ ->
        :ok
    end

    apply_impl(df, :sample, [n, opts[:replacement], opts[:seed]])
  end

  def sample(df, frac, opts) when is_float(frac) do
    n_rows = n_rows(df)
    n = round(frac * n_rows)
    sample(df, n, opts)
  end

  @doc """
  Pivot data from wide to long.

  `Explorer.DataFrame.pivot_longer/3` "lengthens" data, increasing the number of rows and
  decreasing the number of columns. The inverse transformation is
  `Explorer.DataFrame.pivot_wider/4`.

  The second argument (`columns`) can be either an array of column names to use or a filter callback on
  the dataframe's names.

  `value_columns` must all have the same dtype.

  ## Options

    * `value_columns` - Columns to use for values. May be a filter callback on the dataframe's column names. Defaults to an empty list, using all variables except the columns to pivot.
    * `names_to` - A string specifying the name of the column to create from the data stored in the column names of the dataframe. Defaults to `"variable"`.
    * `values_to` - A string specifying the name of the column to create from the data stored in series element values. Defaults to `"value"`.

  ## Examples

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.pivot_longer(df, ["year", "country"], value_columns: &String.ends_with?(&1, "fuel"))
      #Explorer.DataFrame<
        [rows: 3282, columns: 4]
        year integer [2010, 2010, 2010, 2010, 2010, ...]
        country string ["AFGHANISTAN", "ALBANIA", "ALGERIA", "ANDORRA", "ANGOLA", ...]
        variable string ["solid_fuel", "solid_fuel", "solid_fuel", "solid_fuel", "solid_fuel", ...]
        value integer [627, 117, 332, 0, 0, ...]
      >

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.pivot_longer(df, ["year", "country"], value_columns: ["total"])
      #Explorer.DataFrame<
        [rows: 1094, columns: 4]
        year integer [2010, 2010, 2010, 2010, 2010, ...]
        country string ["AFGHANISTAN", "ALBANIA", "ALGERIA", "ANDORRA", "ANGOLA", ...]
        variable string ["total", "total", "total", "total", "total", ...]
        value integer [2308, 1254, 32500, 141, 7924, ...]
      >
  """
  @doc type: :single
  @spec pivot_longer(
          df :: DataFrame.t(),
          columns :: columns() | function(),
          opts :: Keyword.t()
        ) :: DataFrame.t()
  def pivot_longer(df, columns, opts \\ [])

  def pivot_longer(df, columns, opts) when is_function(columns),
    do:
      df
      |> names()
      |> Enum.filter(columns)
      |> then(&pivot_longer(df, &1, opts))

  def pivot_longer(df, columns, opts) do
    opts = Keyword.validate!(opts, value_columns: [], names_to: "variable", values_to: "value")
    existing_columns = to_existing_columns(df, columns)

    names = names(df)
    dtypes = names |> Enum.zip(dtypes(df)) |> Enum.into(%{})

    value_columns =
      case opts[:value_columns] do
        [] ->
          Enum.filter(names, fn name -> name not in columns end)

        [_ | _] = columns ->
          Enum.each(columns, fn column ->
            if column in existing_columns,
              do:
                raise(
                  ArgumentError,
                  "value columns may not also be ID columns but found #{column} in both"
                )
          end)

          columns

        callback when is_function(callback) ->
          Enum.filter(names, fn name -> name not in columns && callback.(name) end)
      end

    value_columns = to_existing_columns(df, value_columns)

    dtypes
    |> Map.take(value_columns)
    |> Map.values()
    |> Enum.uniq()
    |> length()
    |> case do
      1 ->
        :ok

      _ ->
        raise ArgumentError,
              "value columns may only include one dtype but found multiple dtypes"
    end

    apply_impl(df, :pivot_longer, [columns, value_columns, opts[:names_to], opts[:values_to]])
  end

  @doc """
  Pivot data from long to wide.

  `Explorer.DataFrame.pivot_wider/4` "widens" data, increasing the number of columns and
  decreasing the number of rows. The inverse transformation is
  `Explorer.DataFrame.pivot_longer/3`.

  Due to a restriction upstream, `values_from` must be a numeric type.

  ## Options

  * `id_columns` - A set of columns that uniquely identifies each observation.
    Defaults to all columns in data except for the columns specified in `names_from` and `values_from`.
    Typically used when you have redundant variables, i.e. variables whose values are perfectly correlated
    with existing variables. May accept a filter callback, a list or a range of column names.
    Default value is `0..-1`. If an empty list is passed, or a range that results in a empty list of
    column names, it raises an error.

  * `names_prefix` - String added to the start of every variable name.
    This is particularly useful if `names_from` is a numeric vector and you want to create syntactic variable names.

  ## Examples

      iex> df = Explorer.DataFrame.new(id: [1, 1], variable: ["a", "b"], value: [1, 2])
      iex> Explorer.DataFrame.pivot_wider(df, "variable", "value")
      #Explorer.DataFrame<
        [rows: 1, columns: 3]
        id integer [1]
        a integer [1]
        b integer [2]
      >
  """
  @doc type: :single
  @spec pivot_wider(
          df :: DataFrame.t(),
          names_from :: column(),
          values_from :: column(),
          opts ::
            Keyword.t()
        ) :: DataFrame.t()
  def pivot_wider(df, names_from, values_from, opts \\ []) do
    opts = Keyword.validate!(opts, id_columns: 0..-1, names_prefix: "")

    [values_from, names_from] = to_existing_columns(df, [values_from, names_from])

    names = names(df)
    dtypes = names |> Enum.zip(dtypes(df)) |> Enum.into(%{})

    case Map.get(dtypes, values_from) do
      dtype when dtype in [:integer, :float, :date, :datetime] ->
        :ok

      dtype ->
        raise ArgumentError, "the values_from column must be numeric, but found #{dtype}"
    end

    id_columns =
      case opts[:id_columns] do
        fun when is_function(fun) ->
          Enum.filter(names, fn name -> fun.(name) && name not in [names_from, values_from] end)

        names ->
          names = to_existing_columns(df, names)

          Enum.filter(names, &(&1 not in [names_from, values_from]))
      end

    if id_columns == [] do
      raise ArgumentError,
            "id_columns must select at least one existing column, but #{inspect(opts[:id_columns])} selects none"
    end

    apply_impl(df, :pivot_wider, [id_columns, names_from, values_from, opts[:names_prefix]])
  end

  # Two table verbs

  @doc """
  Join two tables.

  ## Join types

    * `inner` - Returns all rows from `left` where there are matching values in `right`, and all columns from `left` and `right`.
    * `left` - Returns all rows from `left` and all columns from `left` and `right`. Rows in `left` with no match in `right` will have `nil` values in the new columns.
    * `right` - Returns all rows from `right` and all columns from `left` and `right`. Rows in `right` with no match in `left` will have `nil` values in the new columns.
    * `outer` - Returns all rows and all columns from both `left` and `right`. Where there are not matching values, returns `nil` for the one missing.
    * `cross` - Also known as a cartesian join. Returns all combinations of `left` and `right`. Can be very computationally expensive.

  ## Options

    * `on` - The columns to join on. Defaults to overlapping columns. Does not apply to cross join.
    * `how` - One of the join types (as an atom) described above. Defaults to `:inner`.

  ## Examples

  Inner join:

      iex> left = Explorer.DataFrame.new(a: [1, 2, 3], b: ["a", "b", "c"])
      iex> right = Explorer.DataFrame.new(a: [1, 2, 2], c: ["d", "e", "f"])
      iex> Explorer.DataFrame.join(left, right)
      #Explorer.DataFrame<
        [rows: 3, columns: 3]
        a integer [1, 2, 2]
        b string ["a", "b", "b"]
        c string ["d", "e", "f"]
      >

  Left join:

      iex> left = Explorer.DataFrame.new(a: [1, 2, 3], b: ["a", "b", "c"])
      iex> right = Explorer.DataFrame.new(a: [1, 2, 2], c: ["d", "e", "f"])
      iex> Explorer.DataFrame.join(left, right, how: :left)
      #Explorer.DataFrame<
        [rows: 4, columns: 3]
        a integer [1, 2, 2, 3]
        b string ["a", "b", "b", "c"]
        c string ["d", "e", "f", nil]
      >

  Right join:

      iex> left = Explorer.DataFrame.new(a: [1, 2, 3], b: ["a", "b", "c"])
      iex> right = Explorer.DataFrame.new(a: [1, 2, 4], c: ["d", "e", "f"])
      iex> Explorer.DataFrame.join(left, right, how: :right)
      #Explorer.DataFrame<
        [rows: 3, columns: 3]
        a integer [1, 2, 4]
        c string ["d", "e", "f"]
        b string ["a", "b", nil]
      >

  Outer join:

      iex> left = Explorer.DataFrame.new(a: [1, 2, 3], b: ["a", "b", "c"])
      iex> right = Explorer.DataFrame.new(a: [1, 2, 4], c: ["d", "e", "f"])
      iex> Explorer.DataFrame.join(left, right, how: :outer)
      #Explorer.DataFrame<
        [rows: 4, columns: 3]
        a integer [1, 2, 4, 3]
        b string ["a", "b", nil, "c"]
        c string ["d", "e", "f", nil]
      >

  Cross join:

      iex> left = Explorer.DataFrame.new(a: [1, 2, 3], b: ["a", "b", "c"])
      iex> right = Explorer.DataFrame.new(a: [1, 2, 4], c: ["d", "e", "f"])
      iex> Explorer.DataFrame.join(left, right, how: :cross)
      #Explorer.DataFrame<
        [rows: 9, columns: 4]
        a integer [1, 1, 1, 2, 2, ...]
        b string ["a", "a", "a", "b", "b", ...]
        a_right integer [1, 2, 4, 1, 2, ...]
        c string ["d", "e", "f", "d", "e", ...]
      >

  Inner join with different names:

      iex> left = Explorer.DataFrame.new(a: [1, 2, 3], b: ["a", "b", "c"])
      iex> right = Explorer.DataFrame.new(d: [1, 2, 2], c: ["d", "e", "f"])
      iex> Explorer.DataFrame.join(left, right, on: [{"a", "d"}])
      #Explorer.DataFrame<
        [rows: 3, columns: 3]
        a integer [1, 2, 2]
        b string ["a", "b", "b"]
        c string ["d", "e", "f"]
      >

  """
  @doc type: :multi
  @spec join(left :: DataFrame.t(), right :: DataFrame.t(), opts :: Keyword.t()) :: DataFrame.t()
  def join(%DataFrame{} = left, %DataFrame{} = right, opts \\ []) do
    left_columns = names(left)
    right_columns = names(right)

    opts =
      Keyword.validate!(opts,
        on: find_overlapping_columns(left_columns, right_columns),
        how: :inner
      )

    {on, how} =
      case {opts[:on], opts[:how]} do
        {on, :cross} ->
          {on, :cross}

        {[], _} ->
          raise(ArgumentError, "could not find any overlapping columns")

        {[_ | _] = on, how} ->
          on =
            Enum.map(on, fn
              {l_name, r_name} ->
                [l_column] = to_existing_columns(left, [l_name])
                [r_column] = to_existing_columns(right, [r_name])
                {l_column, r_column}

              name ->
                [l_column] = to_existing_columns(left, [name])
                [r_column] = to_existing_columns(right, [name])

                # This is an edge case for when an index is passed as column selection
                if l_column != r_column do
                  raise ArgumentError,
                        "the column given to option `:on` is not the same for both dataframes"
                end

                l_column
            end)

          {on, how}

        other ->
          other
      end

    apply_impl(left, :join, [right, on, how])
  end

  defp find_overlapping_columns(left_columns, right_columns) do
    left_columns = MapSet.new(left_columns)
    right_columns = MapSet.new(right_columns)
    left_columns |> MapSet.intersection(right_columns) |> MapSet.to_list()
  end

  @doc """
  Combine two or more dataframes row-wise (stack).

  Column names and dtypes must match. The only exception is for numeric
  columns that can be mixed together, and casted automatically to float columns.

  ## Examples

      iex> df1 = Explorer.DataFrame.new(x: [1, 2, 3], y: ["a", "b", "c"])
      iex> df2 = Explorer.DataFrame.new(x: [4, 5, 6], y: ["d", "e", "f"])
      iex> Explorer.DataFrame.concat_rows([df1, df2])
      #Explorer.DataFrame<
        [rows: 6, columns: 2]
        x integer [1, 2, 3, 4, 5, ...]
        y string ["a", "b", "c", "d", "e", ...]
      >

      iex> df1 = Explorer.DataFrame.new(x: [1, 2, 3], y: ["a", "b", "c"])
      iex> df2 = Explorer.DataFrame.new(x: [4.2, 5.3, 6.4], y: ["d", "e", "f"])
      iex> Explorer.DataFrame.concat_rows([df1, df2])
      #Explorer.DataFrame<
        [rows: 6, columns: 2]
        x float [1.0, 2.0, 3.0, 4.2, 5.3, ...]
        y string ["a", "b", "c", "d", "e", ...]
      >
  """
  @doc type: :multi
  def concat_rows([%DataFrame{} | _t] = dfs) do
    changed_types = compute_changed_types_concat_rows(dfs)

    if Enum.empty?(changed_types) do
      apply_impl(dfs, :concat_rows)
    else
      dfs
      |> cast_numeric_columns_to_float(changed_types)
      |> apply_impl(:concat_rows)
    end
  end

  defp compute_changed_types_concat_rows([head | tail]) do
    types = Map.new(Enum.zip(names(head), dtypes(head)))

    Enum.reduce(tail, %{}, fn df, changed_types ->
      if n_columns(df) != map_size(types) do
        raise ArgumentError,
              "dataframes must have the same columns"
      end

      Enum.reduce(Enum.zip(names(df), dtypes(df)), changed_types, fn {name, type},
                                                                     changed_types ->
        cond do
          not Map.has_key?(types, name) ->
            raise ArgumentError,
                  "dataframes must have the same columns"

          types[name] == type ->
            changed_types

          types_are_numeric_compatible?(types, name, type) ->
            Map.put(changed_types, name, :float)

          true ->
            raise ArgumentError,
                  "columns and dtypes must be identical for all dataframes"
        end
      end)
    end)
  end

  defp types_are_numeric_compatible?(types, name, type) do
    numeric_types = [:float, :integer]
    types[name] != type and types[name] in numeric_types and type in numeric_types
  end

  defp cast_numeric_columns_to_float(dfs, changed_types) do
    for df <- dfs do
      columns =
        for {name, :integer} <- Enum.zip(names(df), dtypes(df)),
            changed_types[name] == :float,
            do: name

      if Enum.empty?(columns) do
        df
      else
        changes = for column <- columns, into: %{}, do: {column, Series.cast(df[column], :float)}

        mutate(df, changes)
      end
    end
  end

  @doc """
  Combine two dataframes row-wise.

  `concat_rows(df1, df2)` is equivalent to `concat_rows([df1, df2])`.
  """
  @doc type: :multi
  def concat_rows(%DataFrame{} = df1, %DataFrame{} = df2), do: concat_rows([df1, df2])
  def concat_rows(%DataFrame{} = df, [%DataFrame{} | _] = dfs), do: concat_rows([df | dfs])

  # Groups

  @doc """
  Group the dataframe by one or more variables.

  When the dataframe has grouping variables, operations are performed per group.
  `Explorer.DataFrame.ungroup/2` removes grouping.

  ## Examples

  You can group by a single variable:

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.group_by(df, "country")
      #Explorer.DataFrame<
        [rows: 1094, columns: 10, groups: ["country"]]
        year integer [2010, 2010, 2010, 2010, 2010, ...]
        country string ["AFGHANISTAN", "ALBANIA", "ALGERIA", "ANDORRA", "ANGOLA", ...]
        total integer [2308, 1254, 32500, 141, 7924, ...]
        solid_fuel integer [627, 117, 332, 0, 0, ...]
        liquid_fuel integer [1601, 953, 12381, 141, 3649, ...]
        gas_fuel integer [74, 7, 14565, 0, 374, ...]
        cement integer [5, 177, 2598, 0, 204, ...]
        gas_flaring integer [0, 0, 2623, 0, 3697, ...]
        per_capita float [0.08, 0.43, 0.9, 1.68, 0.37, ...]
        bunker_fuels integer [9, 7, 663, 0, 321, ...]
      >

  Or you can group by multiple:

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> Explorer.DataFrame.group_by(df, ["country", "year"])
      #Explorer.DataFrame<
        [rows: 1094, columns: 10, groups: ["country", "year"]]
        year integer [2010, 2010, 2010, 2010, 2010, ...]
        country string ["AFGHANISTAN", "ALBANIA", "ALGERIA", "ANDORRA", "ANGOLA", ...]
        total integer [2308, 1254, 32500, 141, 7924, ...]
        solid_fuel integer [627, 117, 332, 0, 0, ...]
        liquid_fuel integer [1601, 953, 12381, 141, 3649, ...]
        gas_fuel integer [74, 7, 14565, 0, 374, ...]
        cement integer [5, 177, 2598, 0, 204, ...]
        gas_flaring integer [0, 0, 2623, 0, 3697, ...]
        per_capita float [0.08, 0.43, 0.9, 1.68, 0.37, ...]
        bunker_fuels integer [9, 7, 663, 0, 321, ...]
      >
  """
  @doc type: :single
  @spec group_by(df :: DataFrame.t(), groups_or_group :: [String.t()] | String.t()) ::
          DataFrame.t()
  def group_by(df, groups) when is_list(groups) do
    names = names(df)
    Enum.each(groups, fn name -> maybe_raise_column_not_found(names, name) end)

    apply_impl(df, :group_by, [groups])
  end

  def group_by(df, group) when is_binary(group), do: group_by(df, [group])

  @doc """
  Removes grouping variables.

  ## Examples

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> df = Explorer.DataFrame.group_by(df, ["country", "year"])
      iex> Explorer.DataFrame.ungroup(df, ["country"])
      #Explorer.DataFrame<
        [rows: 1094, columns: 10, groups: ["year"]]
        year integer [2010, 2010, 2010, 2010, 2010, ...]
        country string ["AFGHANISTAN", "ALBANIA", "ALGERIA", "ANDORRA", "ANGOLA", ...]
        total integer [2308, 1254, 32500, 141, 7924, ...]
        solid_fuel integer [627, 117, 332, 0, 0, ...]
        liquid_fuel integer [1601, 953, 12381, 141, 3649, ...]
        gas_fuel integer [74, 7, 14565, 0, 374, ...]
        cement integer [5, 177, 2598, 0, 204, ...]
        gas_flaring integer [0, 0, 2623, 0, 3697, ...]
        per_capita float [0.08, 0.43, 0.9, 1.68, 0.37, ...]
        bunker_fuels integer [9, 7, 663, 0, 321, ...]
      >
  """
  @doc type: :single
  @spec ungroup(df :: DataFrame.t(), groups_or_group :: [String.t()] | String.t()) ::
          DataFrame.t()
  def ungroup(df, groups \\ [])

  def ungroup(df, groups) when is_list(groups) do
    current_groups = groups(df)

    Enum.each(groups, fn group ->
      if group not in current_groups,
        do:
          raise(
            ArgumentError,
            "could not find #{group} in current groups (#{current_groups})"
          )
    end)

    apply_impl(df, :ungroup, [groups])
  end

  def ungroup(df, group) when is_binary(group), do: ungroup(df, [group])

  @supported_aggs ~w[min max sum mean median first last count n_unique]a

  @doc """
  Summarise each group to a single row.

  Implicitly ungroups.

  ## Supported operations

  The following aggregations may be performed:

    * `:min` - Take the minimum value within the group. See `Explorer.Series.min/1`.
    * `:max` - Take the maximum value within the group. See `Explorer.Series.max/1`.
    * `:sum` - Take the sum of the series within the group. See `Explorer.Series.sum/1`.
    * `:mean` - Take the mean of the series within the group. See `Explorer.Series.mean/1`.
    * `:median` - Take the median of the series within the group. See `Explorer.Series.median/1`.
    * `:first` - Take the first value within the group. See `Explorer.Series.first/1`.
    * `:last` - Take the last value within the group. See `Explorer.Series.last/1`.
    * `:count` - Count the number of rows per group.
    * `:n_unique` - Count the number of unique rows per group.

  ## Examples

      iex> df = Explorer.Datasets.fossil_fuels()
      iex> df |> Explorer.DataFrame.group_by("year") |> Explorer.DataFrame.summarise(total: [:max, :min], country: [:n_unique])
      #Explorer.DataFrame<
        [rows: 5, columns: 4]
        year integer [2010, 2011, 2012, 2013, 2014]
        country_n_unique integer [217, 217, 220, 220, 220]
        total_max integer [2393248, 2654360, 2734817, 2797384, 2806634]
        total_min integer [1, 2, 2, 2, 3]
      >
  """
  @doc type: :single
  @spec summarise(df :: DataFrame.t(), columns :: Keyword.t() | map()) :: DataFrame.t()
  def summarise(%DataFrame{groups: []}, _),
    do:
      raise(
        ArgumentError,
        "dataframe must be grouped in order to perform summarisation"
      )

  def summarise(df, columns) when is_column_pairs(columns) do
    column_pairs =
      to_column_pairs(df, columns, fn values ->
        case values -- @supported_aggs do
          [] ->
            values

          unsupported ->
            raise ArgumentError, "found unsupported aggregations #{inspect(unsupported)}"
        end
      end)

    apply_impl(df, :summarise, [Map.new(column_pairs)])
  end

  @doc """
  Display the DataFrame in a tabular fashion.

  ## Examples

     df = Explorer.Datasets.iris()
     Explorer.DataFrame.table(df)
  """
  @doc type: :single
  def table(df, nrow \\ 5) when nrow >= 0 do
    {rows, columns} = shape(df)
    headers = names(df)

    df = slice(df, 0, nrow)

    types =
      df
      |> dtypes()
      |> Enum.map(&"\n<#{Atom.to_string(&1)}>")

    values =
      headers
      |> Enum.map(&Series.to_list(df[&1]))
      |> Enum.zip_with(& &1)

    name_type = Enum.zip_with(headers, types, fn x, y -> x <> y end)

    TableRex.Table.new()
    |> TableRex.Table.put_title("Explorer DataFrame: [rows: #{rows}, columns: #{columns}]")
    |> TableRex.Table.put_header(name_type)
    |> TableRex.Table.put_header_meta(0..columns, align: :center)
    |> TableRex.Table.add_rows(values)
    |> TableRex.Table.render!(
      header_separator_symbol: "=",
      horizontal_style: :all
    )
    |> IO.puts()
  end

  # Helpers

  defp backend_from_options!(opts) do
    backend = Explorer.Shared.backend_from_options!(opts) || Explorer.Backend.get()
    :"#{backend}.DataFrame"
  end

  defp apply_impl(df, fun, args \\ []) do
    impl = impl!(df)
    apply(impl, fun, [df | args])
  end

  defp maybe_raise_column_not_found(names, name) do
    if name not in names,
      do:
        raise(
          ArgumentError,
          List.to_string(["could not find column name \"#{name}\""] ++ did_you_mean(name, names))
        )
  end

  @threshold 0.77
  @max_suggestions 5
  defp did_you_mean(missing_key, available_keys) do
    suggestions =
      for key <- available_keys,
          distance = String.jaro_distance(missing_key, key),
          distance >= @threshold,
          do: {distance, key}

    case suggestions do
      [] -> []
      suggestions -> [". Did you mean:\n\n" | format_suggestions(suggestions)]
    end
  end

  defp format_suggestions(suggestions) do
    suggestions
    |> Enum.sort(&(elem(&1, 0) >= elem(&2, 0)))
    |> Enum.take(@max_suggestions)
    |> Enum.sort(&(elem(&1, 1) <= elem(&2, 1)))
    |> Enum.map(fn {_, key} -> ["      * ", inspect(key), ?\n] end)
  end
end

defimpl Table.Reader, for: Explorer.DataFrame do
  def init(df) do
    columns = Explorer.DataFrame.names(df)

    data =
      Enum.map(columns, fn column ->
        df
        |> Explorer.DataFrame.pull(column)
        |> Explorer.Series.to_enum()
      end)

    {:columns, %{columns: columns}, data}
  end
end
