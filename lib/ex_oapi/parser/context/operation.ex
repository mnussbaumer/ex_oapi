defmodule ExOAPI.Parser.V3.Context.Operation do
  use TypedEctoSchema

  import Ecto.Changeset
  import ExOAPI.Helpers.Casting, only: [translate: 2]

  alias ExOAPI.Parser.V3.Context

  @list_of_fields [
    :tags,
    :summary,
    :description,
    :operation_id,
    :operation_id_original,
    :responses,
    :callbacks,
    :deprecated,
    :security
  ]

  @translations [
    {"externalDocs", "external_docs"},
    {"operationId", "operation_id"},
    {"operationId", "operation_id_original"},
    {"requestBody", "request_body"}
  ]

  @primary_key false

  typed_embedded_schema do
    field(:tags, {:array, :string}, default: [])
    field(:summary, :string)
    field(:description, :string)
    field(:operation_id, ExOAPI.EctoTypes.Underscore)
    field(:operation_id_original, ExOAPI.EctoTypes.Underscore)
    field(:module_path, {:array, :string})
    field(:fn_name, :string)
    field(:deprecated, :boolean, default: false)
    field(:security, {:array, ExOAPI.EctoTypes.SecurityEntry})

    field(:responses, Context.Response.Map)
    field(:callbacks, Context.Callback.Map)

    embeds_many(:parameters, Context.Parameters)
    embeds_many(:servers, Context.Server)
    embeds_one(:external_docs, Context.ExternalDoc)
    embeds_one(:request_body, Context.RequestBody)
  end

  def map_cast(struct \\ %__MODULE__{}, params) do
    with {:ok, translated} <- translate(params, @translations) do
      struct
      |> cast(translated, @list_of_fields)
      |> cast_embed(:servers, with: &Context.Server.map_cast/2)
      |> cast_embed(:parameters, with: &Context.Parameters.map_cast/2)
      |> cast_embed(:external_docs, with: &Context.ExternalDoc.map_cast/2)
      |> cast_embed(:request_body, with: &Context.RequestBody.map_cast/2)
      |> add_module_and_fun()
    end
  end

  defp add_module_and_fun(changeset) do
    case false do
      true -> do_user_transform(changeset, nil)
      false -> do_base_transform(changeset)
    end
  end

  defp do_user_transform(changeset, _transform), do: changeset

  defp do_base_transform(changeset) do
    op_id = get_change(changeset, :operation_id_original)
    tags = get_change(changeset, :tags)

    op_id =
      String.split(op_id)
      |> Enum.join("_")

    tags = Enum.sort(tags)

    fun_name =
      Enum.reduce(tags, op_id, fn tag, acc ->
        acc
        |> String.replace(~r/^#{tag}/i, "", global: false)
        |> String.replace_leading("_", "")
      end)
      |> Macro.underscore()

    changeset
    |> put_change(:fn_name, fun_name)
    |> put_change(:module_path, ExOAPI.Generator.Helpers.camelize_items(tags))
  end
end
