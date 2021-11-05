defmodule ExOAPI.Parser.V3.Context.Security do
  use TypedEctoSchema
  import Ecto.Changeset

  import ExOAPI.Helpers.Casting, only: [translate: 2]

  @list_of_fields [
    :type,
    :description,
    :name,
    :arg_form,
    :in,
    :scheme,
    :bearer_format,
    :flows,
    :open_id_connect_url
  ]

  @translations [
    {"bearerFormat", "bearer_format"},
    {"openIdConnectUrl", "open_id_connect_url"},
    {"name", "arg_form"}
  ]

  @primary_key false

  typed_embedded_schema do
    field(:type, ExOAPI.EctoTypes.Security, null: false)
    field(:description, :string)
    field(:name, :string)
    field(:in, ExOAPI.EctoTypes.ParameterIn)
    field(:scheme, :string)
    field(:bearer_format, :string)
    field(:flows, :map)
    field(:open_id_connect_url, :string)
    field(:arg_form, ExOAPI.EctoTypes.SafeUL)
  end

  def map_cast(struct \\ %__MODULE__{}, params) do
    with {:ok, translated} <- translate(params, @translations) do
      struct
      |> cast(translated, @list_of_fields)
    end
  end
end
