defmodule ExOAPI.Parser.V3.Context.Paths do
  use TypedEctoSchema

  import Ecto.Changeset
  import ExOAPI.Helpers.Casting, only: [translate: 2]

  alias ExOAPI.Parser.V3.Context

  @list_of_fields [
    :ref,
    :summary,
    :description
  ]

  @translations [
    {"$ref", "ref"}
  ]

  @primary_key false

  typed_embedded_schema do
    field(:ref, :string)
    field(:summary, :string)
    field(:description, :string)
    field(:resource_path, :string)
    embeds_one(:get, Context.Operation)
    embeds_one(:put, Context.Operation)
    embeds_one(:post, Context.Operation)
    embeds_one(:delete, Context.Operation)
    embeds_one(:options, Context.Operation)
    embeds_one(:head, Context.Operation)
    embeds_one(:patch, Context.Operation)
    embeds_one(:trace, Context.Operation)
    embeds_many(:servers, Context.Server)
    embeds_many(:parameters, Context.Parameters)
  end

  def map_cast(struct \\ %__MODULE__{}, params, {k, path_info}) do
    with {:ok, translated} <- translate(params, @translations) do
      struct
      |> cast(translated, @list_of_fields)
      |> put_change(:resource_path, k)
      |> maybe_add_operations(path_info)
      |> cast_embed(:trace, with: {Context.Operation, :map_cast, [k]})
      |> cast_embed(:servers, with: {Context.Operation, :map_cast, [k]})
      |> cast_embed(:parameters, with: &Context.Parameters.map_cast/2)
      |> Context.Schema.maybe_add_ref(k)
    end
  end

  defp maybe_add_operations(%Ecto.Changeset{valid?: true} = changeset, []) do
    resource_path = get_field(changeset, :resource_path)

    changeset
    |> cast_embed(:get, with: {Context.Operation, :map_cast, [resource_path]})
    |> cast_embed(:put, with: {Context.Operation, :map_cast, [resource_path]})
    |> cast_embed(:post, with: {Context.Operation, :map_cast, [resource_path]})
    |> cast_embed(:delete, with: {Context.Operation, :map_cast, [resource_path]})
    |> cast_embed(:options, with: {Context.Operation, :map_cast, [resource_path]})
    |> cast_embed(:head, with: {Context.Operation, :map_cast, [resource_path]})
    |> cast_embed(:patch, with: {Context.Operation, :map_cast, [resource_path]})
  end

  defp maybe_add_operations(%Ecto.Changeset{valid?: true} = changeset, ops) do
    resource_path = get_field(changeset, :resource_path)

    Enum.reduce(ops, changeset, fn op, acc ->
      cast_embed(acc, op, with: {Context.Operation, :map_cast, [resource_path]})
    end)
  end

  defp maybe_add_operations(changeset, _path_info), do: changeset

  def check_path(_, false), do: []
  def check_path(path, paths), do: is_map_key(paths, path) && Map.get(paths, path, [])
end
