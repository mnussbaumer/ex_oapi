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

  def fun_args(call, optional_args_type, first_arg \\ ["%ExOAPI.Client{} = client"])

  def fun_args(
        %Call{required_args: req, optional_args: opt},
        :positional,
        first_arg
      ) do
    first_arg
    |> maybe_add_arg(:required, req)
    |> maybe_add_arg(:optional, opt)
    |> Enum.join(", ")
  end

  def fun_args(
        %Call{required_args: req, optional_args: opt},
        :keyword,
        first_arg
      ) do
    first_arg
    |> maybe_add_arg(:required, req)
    |> maybe_add_opt_arg("[]", opt)
    |> Enum.join(", ")
  end

  def fun_args(
        %Call{required_args: req, optional_args: opt},
        :map,
        first_arg
      ) do
    first_arg
    |> maybe_add_arg(:required, req)
    |> maybe_add_opt_arg("%{}", opt)
    |> Enum.join(", ")
  end

  def maybe_add_opt_arg(args, _type_form, []), do: args

  def maybe_add_opt_arg(args, type_form, _),
    do: Enum.concat(args, ["opts \\\\ #{type_form}"])

  def build_specs(
        %Call{required_args: req, optional_args: opt},
        ctx,
        schemas_title,
        :positional,
        _,
        _
      ) do
    ["client :: ExOAPI.Client.t()"]
    |> maybe_add_arg_type(:required, req, ctx, schemas_title)
    |> maybe_add_arg_type(:optional, opt, ctx, schemas_title)
    |> Enum.join(", ")
  end

  def build_specs(
        %Call{required_args: req, optional_args: opt},
        ctx,
        schemas_title,
        optional_form,
        name
      ) do
    ["client :: ExOAPI.Client.t()"]
    |> maybe_add_arg_type(:required, req, ctx, schemas_title)
    |> maybe_add_opt_type(optional_form, name, opt)
    |> Enum.join(", ")
  end

  def maybe_add_arg_type(args, _, [], _, _), do: args

  def maybe_add_arg_type(args, type, to_add, ctx, title) do
    Enum.concat(
      args,
      Enum.map(to_add, fn arg -> add_type_param(arg, type, ctx, title) end)
    )
  end

  def maybe_add_opt_type(args, _, _, []), do: args

  def maybe_add_opt_type(args, :keyword, name, _),
    do: Enum.concat(args, ["list(#{name}_opts())"])

  def maybe_add_opt_type(args, :map, name, _),
    do: Enum.concat(args, ["#{name}_opts()"])

  def maybe_build_opts_type(_, :positional, _), do: ""
  def maybe_build_opts_type(%Call{optional_args: []}, _, _), do: ""

  def maybe_build_opts_type(%Call{optional_args: opt}, :keyword, name) do
    "@type #{name}_opts :: " <>
      (Enum.map(opt, fn %{arg_form: arg} ->
         "{:#{arg}, String.t()}"
       end)
       |> Enum.join(" | "))
  end

  def maybe_build_opts_type(%Call{optional_args: opt}, :map, name) do
    "@type #{name}_opts :: %{" <>
      (Enum.map(opt, fn %{arg_form: arg} ->
         "optional(:#{arg}) => String.t()"
       end)
       |> Enum.join(", ")) <> "}"
  end

  def build_response_spec(
        %Call{op: %Context.Operation{responses: responses}},
        ctx,
        base_title
      )
      when is_map(responses) and map_size(responses) >= 1 do
    all_types =
      Enum.reduce(responses, {[], false, false}, fn {_k, response}, acc ->
        case Map.get(response, :content) do
          %{} = content ->
            Enum.reduce(content, acc, fn
              {encoding, %Context.Media{schema: schema}}, inner_acc ->
                build_types_from_content_schemas([{encoding, schema}], ctx, base_title, inner_acc)

              _, inner_acc ->
                inner_acc
            end)

          nil ->
            acc
        end
      end)
      |> case do
        {[], _, _} ->
          "any()"

        {types, _, _} ->
          types
          |> Enum.uniq()
          |> Enum.join(" | ")
      end

    :erlang.garbage_collect()

    all_types
  end

  def build_response_spec(_, _, _), do: "any()"

  def build_types_from_content_schemas(schemas, ctx, base_title, outer_acc \\ {[], false, false}) do
    Enum.reduce(schemas, outer_acc, fn
      {"multipart/form-data", _schema}, {acc, has_map?, has_any?} ->
        {["Tesla.Multipart.t()" | acc], has_map?, has_any?}

      {encoding, schema}, {acc, has_map?, has_any?} ->
        with {_, true} <- {:is_map, is_map(schema)},
             schema_title when is_binary(schema_title) <- Map.get(schema, :title),
             %Context.Schema{} <- Map.get(ctx.components.schemas, schema_title) do
          {
            [
              "#{join(base_title, safe_mod_split(schema_title))}.t()#{if has_map?, do: "", else: " | map()"}"
              | acc
            ],
            true,
            has_any?
          }
        else
          {:is_map, _} when not has_any? ->
            {["any()" | acc], has_map?, true}

          _ ->
            spec =
              build_specification(encoding, schema, ctx.components.schemas, base_title)
              |> IO.iodata_to_binary()

            :erlang.garbage_collect()
            {[spec <> if(has_map?, do: "", else: " | map()") | acc], true, has_any?}
        end
    end)
  end

  def add_type_param(%{in: :body, body: schemas}, _, ctx, base_title) do
    type =
      build_types_from_content_schemas(schemas, ctx, base_title)
      |> elem(0)
      |> Enum.join(" | ")

    :erlang.garbage_collect()
    "body :: #{type}"
  end

  def add_type_param(%{arg_form: arg}, :optional, _, _),
    do: "#{arg} :: String.t() | default()"

  def add_type_param(%{arg_form: arg}, :required, _, _),
    do: "#{arg} :: String.t()"

  def maybe_add_arg(args, _, []), do: args

  def maybe_add_arg(args, type, to_add) do
    Enum.concat(
      args,
      Enum.map(to_add, fn arg ->
        case arg do
          %{in: :body, body: _body} -> "body"
          %{in: :header, arg_form: arg_form} -> arg_form
          %{in: :query, arg_form: arg_form} -> arg_form
          %{in: :path, arg_form: arg_form} -> arg_form
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

  def client_body_funs(%Call{required_args: req, optional_args: opt}, optional_type) do
    []
    |> maybe_add_client_fun(req)
    |> maybe_add_optional_fun(opt, optional_type)
    |> Enum.join("\n ")
  end

  def maybe_add_optional_fun(body_funs, [], _), do: body_funs

  def maybe_add_optional_fun(body_funs, to_add, :positional),
    do: maybe_add_client_fun(body_funs, to_add)

  def maybe_add_optional_fun(body_funs, to_add, optional_type) do
    Enum.concat(
      body_funs,
      Enum.group_by(to_add, fn %{in: in_type} -> in_type end)
      |> Enum.map(fn {in_type, args} ->
        "|> ExOAPI.Client.add_arg_opts(:#{optional_type}, :#{in_type}, opts, #{build_args(args)})"
      end)
    )
  end

  defp build_args(args) do
    "[" <>
      (Enum.map(args, fn
         %{name: name, arg_form: arg_form, style: style, explode: explode} ->
           ~s({:#{arg_form}, "#{name}", "#{style}", #{explode}})

         %{name: name, arg_form: arg_form} ->
           ~s({:#{arg_form}, "#{name}", "simple", false})
       end)
       |> Enum.join(", ")) <> "]"
  end

  def maybe_add_client_fun(body_funs, []), do: body_funs

  def maybe_add_client_fun(body_funs, to_add) do
    Enum.concat(
      body_funs,
      Enum.map(to_add, fn arg ->
        case arg do
          %{in: :body, body: _body} ->
            "|> ExOAPI.Client.add_body(body)"

          %{in: :header, name: name, arg_form: arg_form} ->
            "|> ExOAPI.Client.add_header(\"#{name}\", #{arg_form})"

          %{in: :query, name: name, arg_form: arg_form} ->
            "|> ExOAPI.Client.add_query(\"#{name}\", #{arg_form})"

          %{in: :path, name: name, arg_form: arg_form} ->
            "|> ExOAPI.Client.replace_in_path(\"#{name}\", #{arg_form})"
        end
      end)
    )
  end

  def build_cast_array(schema_properties, schemas, base_title) do
    Enum.reduce(schema_properties, [']'], fn
      {_, %{field_name: nil} = _schema}, acc ->
        acc

      {_, %Context.Schema{type: :object, title: title, field_name: name}}, acc ->
        case Map.get(schemas, title) do
          nil -> [", ", name | acc]
          _ -> acc
        end

      {_, %Context.Schema{type: :array, items: item, field_name: name}}, acc ->
        case type_of_schema(item, schemas, base_title) do
          {:array, :enum, _} ->
            [", ", name | acc]

          {:array, _type} ->
            [", ", name | acc]

          {:array, :any_of, _} ->
            [", ", name | acc]

          {:any_of, _} ->
            [", ", name | acc]

          {:type, _} ->
            [", ", name | acc]

          _ ->
            acc
        end

      {_, %Context.Schema{field_name: name, ref: nil}}, acc ->
        [", ", name | acc]

      {name, %Context.Schema{} = schema}, acc ->
        case type_of_schema(schema, schemas, base_title) do
          {:array, :enum, _} ->
            [", ", build_atom(name) | acc]

          {:array, _type} ->
            [", ", build_atom(name) | acc]

          {:enum, _} ->
            [", ", build_atom(name) | acc]

          {:type, _type} ->
            [", ", build_atom(name) | acc]

          {:array, :any_of, _} ->
            [", ", name | acc]

          {:any_of, _} ->
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

      {_, %Context.Schema{type: :object, title: title, field_name: field_name}}, acc ->
        case Map.get(schemas, title) do
          nil ->
            case is_required?(field_name, required) do
              true -> [", ", field_name | acc]
              _ -> acc
            end

          _ ->
            acc
        end

      {_, %Context.Schema{type: :array, items: item, field_name: field_name}}, acc ->
        case type_of_schema(item, schemas, base_title) do
          {:array, :enum, _} ->
            case is_required?(field_name, required) do
              true -> [", ", field_name | acc]
              _ -> acc
            end

          {:array, :any_of, _} ->
            case is_required?(field_name, required) do
              true -> [", ", field_name | acc]
              _ -> acc
            end

          {:array, _type} ->
            case is_required?(field_name, required) do
              true -> [", ", field_name | acc]
              _ -> acc
            end

          {:any_of, _type} ->
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
        field_name = build_atom(name)

        case is_required?(field_name, required) do
          true ->
            case type_of_schema(schema, schemas, base_title) do
              {:array, :enum, _} ->
                [", ", field_name | acc]

              {:array, :any_of, _} ->
                [", ", field_name | acc]

              {:array, _type} ->
                [", ", field_name | acc]

              {:enum, _} ->
                [", ", field_name | acc]

              {:type, _type} ->
                [", ", field_name | acc]

              {:any_of, _type} ->
                [", ", field_name | acc]

              _ ->
                acc
            end

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
      {_, %Context.Schema{type: :object, title: title, field_name: field_name}}, acc ->
        case Map.get(schemas, title) do
          nil ->
            acc

          _ ->
            [
              "|> cast_embed(#{field_name}#{maybe_required_embed(field_name, required)})"
              | acc
            ]
        end

      {_, %Context.Schema{type: :array, items: item, field_name: field_name}}, acc ->
        case type_of_schema(item, schemas, base_title) do
          {:array, :enum, _} ->
            acc

          {:array, _type} ->
            acc

          {:any_of, _} ->
            acc

          {:type, _} ->
            acc

          _ ->
            [
              "|> cast_embed(#{field_name}#{maybe_required_embed(field_name, required)})"
              | acc
            ]
        end

      {_name, %Context.Schema{ref: ref, field_name: field_name} = schema}, acc
      when not is_nil(ref) ->
        case type_of_schema(schema, schemas, base_title) do
          {:array, :enum, _} ->
            acc

          {:array, _type} ->
            acc

          {:any_of, _} ->
            acc

          {embeds, _type} when embeds in [:embeds_one, :embeds_many] ->
            [
              "|> cast_embed(#{field_name}#{maybe_required_embed(field_name, required)})"
              | acc
            ]

          {:enum, _enum} ->
            acc

          _error ->
            acc
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

  def maybe_additional_props(
        _encoding,
        _props,
        _schemas,
        _base_title
      ) do
    ""
  end

  def build_specification(
        encoding,
        %Context.Schema{any_of: [_ | _] = any_of},
        schemas,
        base_title
      ) do
    Enum.reduce(any_of, [], fn entry, acc ->
      [build_specification(encoding, entry, schemas, base_title) | acc]
    end)
    |> Enum.uniq()
    |> Enum.reject(fn x -> x == ~s(:"") end)
    |> Enum.join(" | ")
  end

  def build_specification(
        _encoding,
        %Context.Schema{ref: ref},
        schemas,
        base_title
      )
      when is_binary(ref) do
    case Map.get(schemas, extract_schema_ref(ref)) do
      %Context.Schema{} = schema ->
        with schema_title when is_binary(schema_title) <- Map.get(schema, :title),
             %Context.Schema{} <- Map.get(schemas, schema_title) do
          "#{join(base_title, safe_mod_split(schema_title))}.t()"
        else
          _ ->
            "map()"
        end

      nil ->
        "map()"
    end
  end

  def build_specification(
        encoding,
        %Context.Schema{type: :object, properties: %{} = props, additional_properties: add_props},
        schemas,
        base_title
      ) do
    [
      "%{",
      maybe_additional_props(encoding, add_props, schemas, base_title),
      Enum.reduce(props, [], fn {_, v}, acc ->
        [
          ", ",
          v.field_name,
          " => ",
          build_specification(encoding, v, schemas, base_title),
          "" | acc
        ]
      end)
      |> case do
        [", " | t] -> t
        t -> t
      end
      | "}"
    ]
  end

  def build_specification(
        _encoding,
        %Context.Schema{type: :object, properties: nil, additional_properties: _add_props},
        _schemas,
        _base_title
      ) do
    "map()"
  end

  def build_specification(
        encoding,
        %Context.Schema{type: :array, items: item},
        schemas,
        base_title
      ) do
    ["[", build_specification(encoding, item, schemas, base_title), "]"]
  end

  def build_specification(
        _encoding,
        %Context.Schema{enum: [_ | _] = enum, type: :string},
        _,
        _
      ) do
    ["String.t()" | Enum.map(enum, fn entry -> ":#{inspect(entry)}" end)]
    |> Enum.uniq()
    |> Enum.reject(fn x -> x == ~s(:"") end)
    |> Enum.join(" | ")
  end

  def build_specification(
        _encoding,
        %Context.Schema{type: :string},
        _,
        _
      ),
      do: "String.t()"

  def build_specification(
        _encoding,
        %Context.Schema{type: :number},
        _,
        _
      ),
      do: "number()"

  def build_specification(
        _encoding,
        %Context.Schema{type: :integer},
        _,
        _
      ),
      do: "integer()"

  def build_specification(
        _encoding,
        %Context.Schema{type: :boolean},
        _,
        _
      ),
      do: "boolean()"

  def build_schema_field(
        %Context.Schema{type: :string, enum: nil, format: "date-time", field_name: field_name},
        _,
        _,
        _
      ),
      do: "field #{field_name}, :utc_datetime"

  def build_schema_field(
        %Context.Schema{type: :string, enum: nil, format: "date", field_name: field_name},
        _,
        _,
        _
      ),
      do: "field #{field_name}, :date"

  def build_schema_field(
        %Context.Schema{type: :string, enum: [_ | _] = enum, field_name: field_name},
        _,
        _,
        _
      ),
      do: "field #{field_name}, Ecto.Enum, values: #{make_enum(enum)}"

  def build_schema_field(
        %Context.Schema{type: :string, enum: nil, field_name: field_name},
        _,
        _,
        _
      ),
      do: "field #{field_name}, :string"

  def build_schema_field(
        %Context.Schema{type: :number, enum: nil, field_name: field_name},
        _,
        _,
        _
      ),
      do: "field #{field_name}, :float"

  def build_schema_field(
        %Context.Schema{type: :integer, enum: nil, field_name: field_name},
        _,
        _,
        _
      ),
      do: "field #{field_name}, :integer"

  def build_schema_field(%Context.Schema{type: :boolean, field_name: field_name}, _, _, _),
    do: "field #{field_name}, :boolean"

  def build_schema_field(
        %Context.Schema{type: :object, title: title, field_name: _field_name},
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
        %Context.Schema{type: :array, items: item, field_name: field_name},
        _,
        schemas,
        base_title
      ) do
    case type_of_schema(item, schemas, base_title) do
      {:array, :enum, enum} ->
        "field #{field_name}, {:array, Ecto.Enum}, values: #{enum}"

      {:type, type} ->
        "field #{field_name}, {:array, #{type}}"

      {:array, type} ->
        "field #{field_name}, {:array, #{type}}"

      {embeds, type} when embeds in [:embeds_one, :embeds_many] ->
        "embeds_many #{field_name}, #{type}"

      {:enum, enum} ->
        "field #{field_name}, Ecto.Enum, values: #{enum}"

      {:any_of, types} ->
        "field #{field_name}, {:array, ExOAPI.EctoTypes.AnyOf}, types: #{inspect(types)}"

      _error ->
        ""
    end
  end

  def build_schema_field(
        %Context.Schema{any_of: [_ | _] = any_of, field_name: field_name},
        name,
        schemas,
        base_title
      ) do
    final_name = field_name || name

    final_types =
      Enum.reduce(any_of, [], fn any, acc ->
        [
          case type_of_schema(any, schemas, base_title) do
            {:array, :enum, enum} ->
              {:enum, enum}

            {:enum, enum} ->
              {:enum, enum}

            {:array, ":" <> type} ->
              String.to_atom(type)

            {:embeds_many, type} ->
              Module.concat([type])

            {:embeds_one, type} ->
              Module.concat([type])

            {:type, ":" <> type} ->
              String.to_existing_atom(type)
          end
          | acc
        ]
      end)
      |> Enum.uniq()
      |> Enum.reverse()

    "field #{final_name}, ExOAPI.EctoTypes.AnyOf, types: #{inspect(final_types)}"
  end

  def build_schema_field(
        %Context.Schema{type: nil, ref: ref} = schema,
        name,
        schemas,
        base_title
      )
      when not is_nil(ref) do
    case type_of_schema(schema, schemas, base_title) do
      {:array, :enum, enum} ->
        "field :#{name}, {:array, Ecto.Enum}, values: #{enum}"

      {:array, type} ->
        "field :#{name}, {:array, #{type}}"

      {:embeds_many, type} ->
        "embeds_many :#{name}, #{type}"

      {:embeds_one, type} ->
        "embeds_one :#{name}, #{type}"

      {:enum, enum} ->
        "field :#{name}, Ecto.Enum, values: #{enum}"

      {:type, type} ->
        "field :#{name}, #{type}"

      _error ->
        ""
    end
  end

  def type_of_schema(
        %Context.Schema{type: :array, items: %Context.Schema{} = schema},
        schemas,
        base_title
      ) do
    case type_of_schema(schema, schemas, base_title) do
      {:embeds_one, embed} -> {:embeds_many, embed}
      {:array, _} = type -> {:array, type}
      {:type, type} -> {:array, type}
      {:enum, enum} -> {:array, :enum, enum}
      {:any_of, types} -> {:array, :any_of, types}
    end
  end

  def type_of_schema(
        %Context.Schema{any_of: [_ | _] = any_of},
        schemas,
        base_title
      ) do
    final_schemas =
      Enum.reduce(any_of, [], fn any, acc ->
        [
          case type_of_schema(any, schemas, base_title) do
            {:array, :enum, enum} ->
              {:enum, enum}

            {:enum, enum} ->
              {:enum, enum}

            {:array, ":" <> type} ->
              String.to_atom(type)

            {:embeds_many, type} ->
              Module.concat([type])

            {:embeds_one, type} ->
              Module.concat([type])

            {:type, ":" <> type} ->
              String.to_existing_atom(type)
          end
          | acc
        ]
      end)
      |> Enum.uniq()

    {:any_of, final_schemas}
  end

  def type_of_schema(
        %Context.Schema{title: title, type: type, format: format, ref: nil},
        schemas,
        base_title
      ) do
    case Map.get(schemas, title) do
      nil ->
        case get_type(type, format) do
          :error -> :error
          type -> {:type, type}
        end

      %Context.Schema{type: :array} ->
        {:embeds_many, "#{join(base_title, safe_mod_split(title))}"}

      %Context.Schema{type: :object, properties: properties}
      when properties == %{} or is_nil(properties) ->
        {:array, ":map"}

      %Context.Schema{type: :object} ->
        {:embeds_one, "#{join(base_title, safe_mod_split(title))}"}
    end
  end

  def type_of_schema(
        %Context.Schema{ref: ref},
        schemas,
        base_title
      )
      when is_binary(ref) do
    case Map.get(schemas, extract_schema_ref(ref)) do
      nil ->
        :error

      %Context.Schema{type: :array, items: %{ref: ref} = schema} when is_binary(ref) ->
        case type_of_schema(schema, schemas, base_title) do
          {:embeds_one, embed} -> {:embeds_many, embed}
          {:array, _} = type -> type
          {:type, type} -> {:array, type}
          {:enum, enum} -> {:array, :enum, enum}
          {:any_of, types} -> {:array, :any_of, types}
        end

      %Context.Schema{type: :object, properties: properties}
      when properties == %{} or is_nil(properties) ->
        {:array, ":map"}

      %Context.Schema{title: title, type: :object} ->
        {:embeds_one, "#{join(base_title, safe_mod_split(title))}"}

      %Context.Schema{enum: [_ | _] = enum} ->
        {:enum, make_enum(enum)}

      %Context.Schema{
        ref: nil,
        enum: nil,
        any_of: [],
        all_of: [],
        one_of: [],
        properties: nil,
        xml: nil,
        multiple_of: nil,
        items: nil,
        type: type
      } ->
        {:type, build_atom(type)}

      %Context.Schema{} ->
        {:array, ":map"}
    end
  end

  def join(base, split, joiner \\ "."),
    do: Enum.join([base | split], joiner)

  Enum.each(
    [
      {:object, nil, "map"},
      {:string, "date", "date"},
      {:string, "date-time", "utc_datetime"}
    ],
    fn {type, format, elixir_type} ->
      def get_type(unquote(type), unquote(format)), do: ":#{unquote(elixir_type)}"
    end
  )

  Enum.each([:string, :number, :integer, :boolean], fn type ->
    def get_type(unquote(type) = type, _), do: ":#{type}"
  end)

  def get_type(_, _), do: :error

  def make_enum(enum) do
    [_ | final] =
      Enum.reduce(enum, ["]"], fn e, acc ->
        case build_atom(e) do
          nil ->
            acc

          enum ->
            [", ", enum | acc]
        end
      end)

    ["[" | final]
  end

  defp build_atom(":" <> _ = already_atom), do: already_atom

  defp build_atom(e) when is_binary(e) do
    case Regex.match?(~r/^[a-zA-Z][a-zA-Z0-9\_]*(\??|\!?)$/, e) do
      true -> ":#{e}"
      _ -> ~s(:"#{e}")
    end
  end

  defp build_atom(nil), do: nil

  def build_docs_for_op(%Operation{} = op) do
    op
    |> Map.take([:summary, :description, :external_docs, :deprecated])
    |> Enum.reduce([~s(\n""")], fn {k, v}, acc ->
      if v do
        ["\n", "**#{k}**: #{v}\n" | acc]
      else
        acc
      end
    end)
    |> case do
      [_] -> []
      acc -> ["@doc \"\"\"" | acc]
    end
  end

  def build_docs_for_schema(
        schema,
        schemas,
        title,
        initial_string \\ "@moduledoc \"\"\"",
        end_string \\ ~s(\n""")
      )

  def build_docs_for_schema(
        %Context.Schema{} = schema,
        schemas,
        title,
        initial_string,
        end_string
      ) do
    schema
    |> Map.take([:description, :external_docs, :deprecated])
    |> Enum.reduce([build_schema_props_docs(schema, schemas, title), end_string], fn {k, v},
                                                                                     acc ->
      if v do
        ["\n", "**#{k}**: #{v}\n" | acc]
      else
        acc
      end
    end)
    |> List.flatten()
    |> case do
      [_] ->
        []

      acc ->
        [initial_string | acc]
    end
  end

  def build_docs_for_schema(_, _, _, _, _), do: ""

  def build_schema_props_docs(schema, schemas, title, field_name \\ nil)

  def build_schema_props_docs(%Context.Schema{properties: props} = _schema, schemas, title, _)
      when is_map(props) do
    Enum.map(props, fn {k, v} -> build_schema_props_docs(v, schemas, title, ":#{k}") end)
  end

  def build_schema_props_docs(
        %Context.Schema{field_name: name, items: item} = _schema,
        schemas,
        title,
        _
      )
      when is_map(item),
      do: build_schema_props_docs(item, schemas, title, ":#{name}")

  def build_schema_props_docs(
        %Context.Schema{
          field_name: name,
          description: description,
          external_docs: docs,
          deprecated: deprecated
        } = schema,
        schemas,
        title,
        prop_name
      ) do
    type =
      case type_of_schema(schema, schemas, title) do
        {:array, :enum, enum} ->
          "list(#{enum})"

        {:array, :any_of, types} ->
          stringed =
            types
            |> Enum.map(&"#{inspect(&1)}")
            |> Enum.join(" | ")

          "list(#{stringed})"

        {:array, type} ->
          "list(#{type})"

        {:embeds_one, type} ->
          type

        {:embeds_many, type} ->
          "list(#{type})"

        {:enum, enum} ->
          enum

        {:type, type} ->
          type

        {:any_of, types} ->
          types
          |> Enum.map(&"#{inspect(&1)}")
          |> Enum.join(" | ")

        :error ->
          "unknown - not defined on the open api spec"
      end

    [
      "\n**#{if(prop_name, do: prop_name, else: name)}** :: *#{type}*\n",
      maybe_empty_text(description),
      maybe_empty_text(docs),
      if(deprecated, do: "DEPRECATED"),
      "\n"
    ]
    |> Enum.filter(& &1)
  end

  defp maybe_empty_text(nil), do: nil
  defp maybe_empty_text(""), do: nil
  defp maybe_empty_text(text), do: "\n#{text}\n"

  def schemas_title(title, default \\ ["ExOAPI", "Schemas"]) do
    Enum.join([title | default], ".")
  end
end
