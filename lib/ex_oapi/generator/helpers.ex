defmodule ExOAPI.Generator.Helpers do
  @verbs [:get, :post, :put, :delete, :options, :head, :patch]

  alias ExOAPI.Parser.V3.Context
  alias Context.Operation
  alias ExOAPI.Generator.Paths.Call

  @doc """
  Returns all valid http verbs.
  """
  def http_verbs(), do: @verbs

  @doc """
  Extracts a definition according to a ref path in a `%ExOAPI.Parser.V3.Context.t()`.
  """
  Enum.each(
    [
      ["#", "components", "schemas"]
    ],
    fn ["#" | without_pointer] = pieces ->
      final_path = Enum.join(pieces, "/") <> "/"
      search_path = Enum.map(without_pointer, &String.to_atom(&1))

      def extract_schema_ref(unquote(final_path) <> schema), do: schema

      def extract_ref(unquote(final_path) <> schema = full_ref, ctx, identifiers \\ %{}) do
        pieces_with_schema = List.flatten([unquote(search_path) | [schema]])

        case Map.get(identifiers, schema) do
          nil ->
            Enum.reduce_while(pieces_with_schema, ctx, fn piece, acc ->
              case Map.get(acc, piece) do
                nil ->
                  {:halt, nil}

                got_piece ->
                  {:cont, got_piece}
              end
            end)

          _ ->
            %Context.Schema{ref: full_ref}
        end
      end
    end
  )

  def safe_mod_split(title) when is_binary(title) do
    title
    |> String.split()
    |> camelize_items()
  end

  def camelize_items(items) when is_list(items) do
    Enum.map(items, fn item ->
      item
      |> Macro.camelize()
      |> ExOAPI.EctoTypes.Underscore.cast!()
    end)
  end

  def fun_args_call(
        %Call{required_args: req, optional_args: opt},
        first_arg \\ ["ExOAPI.Client.base_new()"]
      ) do
    first_arg
    |> maybe_add_arg(:required, req)
    |> maybe_add_arg(:required, opt)
    |> Enum.join(", ")
  end

  def fun_args(
        %Call{required_args: req, optional_args: opt},
        first_arg \\ ["%ExOAPI.Client{} = client"]
      ) do
    first_arg
    |> maybe_add_arg(:required, req)
    |> maybe_add_arg(:optional, opt)
    |> Enum.join(", ")
  end

  def build_specs(%Call{required_args: req, optional_args: opt}) do
    ["client :: ExOAPI.Client.t()"]
    |> maybe_add_arg_type(:required, req)
    |> maybe_add_arg_type(:optional, opt)
    |> Enum.join(", ")
  end

  def maybe_add_arg_type(args, _, []), do: args

  def maybe_add_arg_type(args, type, to_add) do
    Enum.concat(
      args,
      Enum.map(to_add, fn arg -> add_type_param(arg, type) end)
    )
  end

  def add_type_param(%{in: :body, body: _body}, _) do
    "body :: any()"
  end

  def add_type_param(%{arg_form: arg}, :optional),
    do: "#{arg} :: String.t() | default()"

  def add_type_param(%{arg_form: arg}, :required),
    do: "#{arg} :: String.t()"

  def maybe_add_arg(args, _, []), do: args

  def maybe_add_arg(args, type, to_add) do
    Enum.concat(
      args,
      Enum.map(to_add, fn arg ->
        case arg do
          %{in: :body, body: _body} -> "body"
          %{in: "header", arg_form: arg_form} -> arg_form
          %{in: "query", arg_form: arg_form} -> arg_form
          %{in: "path", arg_form: arg_form} -> arg_form
        end
        |> maybe_add_optional(type)
      end)
    )
  end

  def maybe_add_body(%Call{required_args: req, optional_args: opt}) do
    Enum.reduce_while(req ++ opt, "", fn
      %{in: :body}, _ -> {:halt, "body: body,"}
      _, _ -> {:cont, ""}
    end)
  end

  def maybe_add_optional(arg, :optional), do: "#{arg} \\\\ nil"
  def maybe_add_optional(arg, :required), do: arg

  def client_body_funs(%Call{required_args: req, optional_args: opt}) do
    []
    |> maybe_add_client_fun(req)
    |> maybe_add_client_fun(opt)
    |> Enum.join("\n ")
  end

  def maybe_add_client_fun(body_funs, []), do: body_funs

  def maybe_add_client_fun(body_funs, to_add) do
    Enum.concat(
      body_funs,
      Enum.map(to_add, fn arg ->
        case arg do
          %{in: :body, body: _body} ->
            "|> ExOAPI.Client.add_body(body)"

          %{in: "header", name: name, arg_form: arg_form} ->
            "|> ExOAPI.Client.add_header(\"#{name}\", #{arg_form})"

          %{in: "query", name: name, arg_form: arg_form} ->
            "|> ExOAPI.Client.add_query(\"#{name}\", #{arg_form})"

          %{in: "path", name: name, arg_form: arg_form} ->
            "|> ExOAPI.Client.replace_in_path(\"#{name}\", #{arg_form})"
        end
      end)
    )
  end

  def build_cast_array(schema_properties, schemas, base_title) do
    Enum.reduce(schema_properties, [']'], fn
      {_, %{field_name: nil} = _schema}, acc ->
        acc

      {_, %Context.Schema{type: "object", title: title, field_name: name}}, acc ->
        case Map.get(schemas, title) do
          nil -> [", ", name | acc]
          _ -> acc
        end

      {_, %Context.Schema{type: "array", items: item, field_name: name}}, acc ->
        case type_of_schema(item, schemas, base_title) do
          {:array, _type} ->
            [", ", name | acc]

          _ ->
            acc
        end

      {_, %Context.Schema{field_name: name, ref: nil}}, acc ->
        [", ", name | acc]

      {name, %Context.Schema{} = schema}, acc ->
        case type_of_schema(schema, schemas, base_title) do
          {:array, _type} ->
            [", ", name | acc]

          _ ->
            acc
        end
    end)
    |> case do
      [_] ->
        ["[]"]

      [_ | final] ->
        ['[' | final]
    end
  end

  def build_validate_required(schema_properties, schemas, base_title, required) do
    Enum.reduce(schema_properties, [']'], fn
      {_, %{field_name: nil} = _schema}, acc ->
        acc

      {_, %Context.Schema{type: "object", title: title, field_name: field_name}}, acc ->
        case Map.get(schemas, title) do
          nil ->
            case is_required?(field_name, required) do
              true -> [", ", field_name | acc]
              _ -> acc
            end

          _ ->
            acc
        end

      {_, %Context.Schema{type: "array", items: item, field_name: field_name}}, acc ->
        case type_of_schema(item, schemas, base_title) do
          {:array, _type} ->
            case is_required?(field_name, required) do
              true -> [", ", field_name | acc]
              _ -> acc
            end

          _ ->
            acc
        end

      {_, %Context.Schema{field_name: field_name, ref: nil}}, acc ->
        case is_required?(field_name, required) do
          true -> [", ", field_name | acc]
          _ -> acc
        end

      {name, %Context.Schema{} = schema}, acc ->
        case type_of_schema(schema, schemas, base_title) do
          {:array, _type} ->
            [", ", name | acc]

          _ ->
            acc
        end
    end)
    |> case do
      [_] -> []
      [_ | final] -> ["|> validate_required([", final, ")"]
    end
  end

  def build_cast_embeds(schema_properties, schemas, base_title, required) do
    Enum.reduce(schema_properties, [], fn
      {_, %Context.Schema{type: "object", title: title, field_name: field_name}}, acc ->
        case Map.get(schemas, title) do
          nil ->
            acc

          _ ->
            [
              "|> cast_embed(#{field_name}#{maybe_required_embed(field_name, required)})"
              | acc
            ]
        end

      {_, %Context.Schema{type: "array", items: item, field_name: field_name}}, acc ->
        case type_of_schema(item, schemas, base_title) do
          {:array, _type} ->
            acc

          _ ->
            [
              "|> cast_embed(#{field_name}#{maybe_required_embed(field_name, required)})"
              | acc
            ]
        end

      {name, %Context.Schema{ref: ref, field_name: field_name} = schema}, acc
      when not is_nil(ref) ->
        case type_of_schema(schema, schemas, base_title) do
          {:array, _type} ->
            acc

          {:embeds, _type} ->
            [
              "|> cast_embed(#{field_name}#{maybe_required_embed(field_name, required)})"
              | acc
            ]

          error ->
            IO.inspect(error: error, name: name, schema: schema)
            ""
        end

      {_, _}, acc ->
        acc
    end)
  end

  def maybe_required_embed(_name, []), do: ""

  def maybe_required_embed(name, required) do
    case is_required?(name, required) do
      true -> ", required: true"
      _ -> ""
    end
  end

  def is_required?(_name, []), do: false
  def is_required?(_name, nil), do: false

  def is_required?(name, required),
    do: name in required

  def build_schema_field(
        %Context.Schema{type: "string", enum: nil, format: "date-time", field_name: field_name},
        _,
        _,
        _
      ),
      do: "field #{field_name}, :utc_datetime"

  def build_schema_field(
        %Context.Schema{type: "string", enum: nil, format: "date", field_name: field_name},
        _,
        _,
        _
      ),
      do: "field #{field_name}, :date"

  def build_schema_field(
        %Context.Schema{type: "string", enum: [_ | _] = enum, field_name: field_name},
        _,
        _,
        _
      ),
      do: "field #{field_name}, Ecto.Enum, values: #{make_enum(enum)}"

  def build_schema_field(
        %Context.Schema{type: "string", enum: nil, field_name: field_name},
        _,
        _,
        _
      ),
      do: "field #{field_name}, :string"

  def build_schema_field(
        %Context.Schema{type: "number", enum: nil, field_name: field_name},
        _,
        _,
        _
      ),
      do: "field #{field_name}, :float"

  def build_schema_field(
        %Context.Schema{type: "integer", enum: nil, field_name: field_name},
        _,
        _,
        _
      ),
      do: "field #{field_name}, :integer"

  def build_schema_field(%Context.Schema{type: "boolean", field_name: field_name}, _, _, _),
    do: "field #{field_name}, :boolean"

  def build_schema_field(
        %Context.Schema{type: "object", title: title, field_name: _field_name},
        name,
        schemas,
        base_title
      ) do
    case Map.get(schemas, title) do
      nil ->
        "field :#{name}, :map"

      _schema ->
        "embeds_one :#{name}, #{join(base_title, safe_mod_split(title))}"
    end
  end

  def build_schema_field(
        %Context.Schema{type: "array", items: item, field_name: field_name},
        _,
        schemas,
        base_title
      ) do
    case type_of_schema(item, schemas, base_title) do
      {:array, type} ->
        "field #{field_name}, {:array, #{type}}"

      {:embeds, type} ->
        "embeds_many #{field_name}, #{type}"

      error ->
        IO.inspect(error: error, name: field_name, schema: item)
        ""
    end
  end

  def build_schema_field(
        %Context.Schema{type: nil, ref: ref} = schema,
        name,
        schemas,
        base_title
      )
      when not is_nil(ref) do
    case type_of_schema(schema, schemas, base_title) do
      {:array, type} ->
        "field :#{name}, {:array, #{type}}"

      {:embeds, type} ->
        "embeds_many :#{name}, #{type}"

      error ->
        IO.inspect(error: error, name: name, schema: schema)
        ""
    end
  end

  def type_of_schema(
        %Context.Schema{title: title, type: type, format: format, ref: ref},
        schemas,
        base_title
      ) do
    case ref do
      nil ->
        case Map.get(schemas, title) do
          nil -> {:array, get_type(type, format)}
          _schema -> {:embeds, "#{join(base_title, safe_mod_split(title))}"}
        end

      ref ->
        case Map.get(schemas, extract_schema_ref(ref)) do
          nil ->
            :error

          %Context.Schema{title: title} ->
            {:embeds, "#{join(base_title, safe_mod_split(title))}"}
        end
    end
  end

  def join(base, split, joiner \\ "."),
    do: Enum.join([base | split], joiner)

  Enum.each(
    [
      {"object", nil, "map"},
      {"string", "date", "date"},
      {"string", "date-time", "utc_datetime"}
    ],
    fn {type, format, elixir_type} ->
      def get_type(unquote(type), unquote(format)), do: ":" <> unquote(elixir_type)
    end
  )

  Enum.each(["string", "number", "integer"], fn type ->
    def get_type(unquote(type) = type, _), do: ":" <> type
  end)

  def make_enum(enum) do
    [_ | final] = Enum.reduce(enum, ["]"], fn e, acc -> [", ", ":#{e}" | acc] end)
    ["[" | final]
  end

  def build_docs_for_op(%Operation{} = op) do
    op
    |> Map.take([:summary, :description, :external_docs, :deprecated])
    |> Enum.reduce([~s(\n""")], fn {k, v}, acc ->
      if v do
        ["\n", "#{k}: #{v}" | acc]
      else
        acc
      end
    end)
    |> case do
      [_] -> []
      acc -> ["@doc \"\"\"" | acc]
    end
  end
end
