defmodule ExOAPI.Parser.V3.Context do
  use TypedEctoSchema
  import Ecto.Changeset

  @list_of_fields [
    :openapi,
    :paths,
    :security
  ]

  @ex_oapi_paths ExOAPI.Parser.ex_oapi_paths()
  @ex_oapi_schemas ExOAPI.Parser.ex_oapi_schemas()
  @ex_oapi_cull_schemas? ExOAPI.Parser.ex_oapi_cull_schemas()
  @ex_oapi_skipped_schemas ExOAPI.Parser.ex_oapi_skipped_schemas()
  @ex_oapi_reinsert_schemas ExOAPI.Parser.ex_oapi_reinsert_schemas()

  @primary_key false

  typed_embedded_schema do
    field(:openapi, :string)
    field(:paths, __MODULE__.Paths.Map)
    field(:security, {:array, ExOAPI.EctoTypes.SecurityEntry}, default: [])

    embeds_one(:info, __MODULE__.Info)
    embeds_one(:components, __MODULE__.Components)
    embeds_many(:servers, __MODULE__.Server)
  end

  def new(opts \\ %{}) do
    only_paths = Map.get(opts, :paths, false)

    Process.put(@ex_oapi_paths, only_paths)
    Process.put(@ex_oapi_schemas, nil)
    Process.put(@ex_oapi_cull_schemas?, false)
    Process.put(@ex_oapi_skipped_schemas, %{})
    Process.put(@ex_oapi_reinsert_schemas, [])
    %__MODULE__{}
  end

  def get_schema_culling(), do: Process.get(@ex_oapi_cull_schemas?)

  def get_and_set_schema_culling(value),
    do: Process.put(@ex_oapi_cull_schemas?, value)

  def toggle_schema_culling(pass_through) do
    Process.put(@ex_oapi_cull_schemas?, !Process.get(@ex_oapi_cull_schemas?))
    pass_through
  end

  def toggle_schema_culling(pass_through, new_value) do
    Process.put(@ex_oapi_cull_schemas?, new_value)
    pass_through
  end

  def skipped_schema(k, v) do
    @ex_oapi_skipped_schemas
    |> Process.put(Map.put(Process.get(@ex_oapi_skipped_schemas, k), k, v))
  end

  def put_ref(k, ref) do
    make_ref = process_ref(ref)

    new_schemas =
      case Process.get(@ex_oapi_schemas, nil) do
        nil -> %{}
        base when is_map(base) -> base
      end
      |> Map.update(make_ref, [k], fn acc -> [k | acc] end)

    Process.put(@ex_oapi_schemas, new_schemas)
  end

  def maybe_add_skipped_schemas({:ok, %__MODULE__{} = context}),
    do: maybe_add_skipped_schemas(context)

  def maybe_add_skipped_schemas(
        %__MODULE__{} = context,
        {p_schemas, p_skipped, count} \\ {%{}, %{}, 0}
      ) do
    schemas = Process.put(@ex_oapi_schemas, %{})
    skipped = Process.put(@ex_oapi_skipped_schemas, %{})

    case p_schemas == schemas and p_skipped == skipped and count > 0 do
      true ->
        {:ok, context}

      _ ->
        case {map_size(schemas), map_size(skipped)} do
          {0, 0} ->
            {:ok, context}

          _ ->
            Enum.reduce(skipped, context, fn {skipped, schema}, acc ->
              if Map.get(schemas, skipped) do
                case __MODULE__.Schema.maybe_schema(schema, nil, skipped) do
                  {:ok, schema} ->
                    __MODULE__.Components.add_to_schemas(skipped, schema, acc)

                  _ ->
                    acc
                end
              else
                skipped_schema(skipped, schema)
                acc
              end
            end)
            |> maybe_add_skipped_schemas({schemas, skipped, count + 1})
        end
    end
  end

  def map_cast(struct \\ %__MODULE__{}, map_body) when is_map(map_body) do
    struct
    |> cast(map_body, @list_of_fields)
    |> cast_embed(:info, with: &__MODULE__.Info.map_cast/2)
    |> cast_embed(:servers, with: &__MODULE__.Server.map_cast/2)
    |> cast_embed(:components, with: &__MODULE__.Components.map_cast/2)
    |> validate_required(@list_of_fields)
    |> apply_action(:insert)
  end

  def normalize_schemas({:ok, %__MODULE__{} = ctx}),
    do: normalize_schemas(ctx)

  def normalize_schemas(
        %__MODULE__{
          components:
            %__MODULE__.Components{
              schemas: schemas
            } = components
        } = ctx
      ) do
    {:ok,
     %__MODULE__{
       ctx
       | components: %__MODULE__.Components{
           components
           | schemas:
               Enum.reduce(schemas, schemas, fn {identifier, schema}, acc ->
                 normalized = normalize_schema(schema, ctx, add_identifier(identifier))
                 Map.put(acc, identifier, normalized)
               end)
         }
     }}
  end

  def normalize_schema(%__MODULE__.Schema{ref: nil} = schema, ctx, identifiers),
    do: maybe_normalize_properties(schema, ctx, identifiers)

  def normalize_schema(%__MODULE__.Schema{ref: ref}, ctx, identifiers) do
    case ExOAPI.Generator.Helpers.extract_ref(ref, ctx, identifiers) do
      %__MODULE__.Schema{ref: ^ref} = schema ->
        schema

      schema ->
        normalize_schema(schema, ctx, identifiers)
    end
  end

  def maybe_normalize_properties(%__MODULE__.Schema{properties: nil} = schema, ctx, identifiers),
    do: maybe_normalize_items(schema, ctx, identifiers)

  def maybe_normalize_properties(%__MODULE__.Schema{properties: props} = schema, ctx, identifiers) do
    {new_properties, new_identifiers} =
      Enum.reduce(props, {props, identifiers}, fn {identifier, schema}, {acc, new_identifiers} ->
        case Map.get(new_identifiers, identifier) do
          nil ->
            new_identifiers = add_identifier(identifier, new_identifiers)
            normalized = normalize_schema(schema, ctx, new_identifiers)
            {Map.put(acc, identifier, normalized), new_identifiers}

          _ ->
            {Map.put(acc, identifier, schema), new_identifiers}
        end
      end)

    %__MODULE__.Schema{schema | properties: new_properties}
    |> maybe_normalize_items(ctx, new_identifiers)
  end

  def maybe_normalize_items(%__MODULE__.Schema{items: nil} = schema, _, _),
    do: schema

  def maybe_normalize_items(
        %__MODULE__.Schema{items: %__MODULE__.Schema{ref: nil} = item} = schema,
        ctx,
        identifiers
      ) do
    %__MODULE__.Schema{
      schema
      | items: normalize_schema(item, ctx, identifiers)
    }
  end

  def maybe_normalize_items(
        %__MODULE__.Schema{items: %__MODULE__.Schema{ref: ref}} = schema,
        ctx,
        identifiers
      ) do
    case ExOAPI.Generator.Helpers.extract_ref(ref, ctx, identifiers) do
      %__MODULE__.Schema{ref: ^ref} = item ->
        %__MODULE__.Schema{
          schema
          | items: item
        }

      item ->
        %__MODULE__.Schema{
          schema
          | items: normalize_schema(item, ctx, identifiers)
        }
    end
  end

  defp process_ref("#/components/schemas/" <> ref), do: ref

  defp add_identifier(identifier), do: Map.put(%{}, identifier, true)

  defp add_identifier(identifier, identifiers),
    do: Map.put(identifiers, identifier, true)
end
