defmodule ExOAPI.Parser.V3.Context.Discriminator do
  use TypedEctoSchema
  import Ecto.Changeset

  import ExOAPI.Helpers.Casting, only: [translate: 2]

  @list_of_fields [
    :property_name,
    :mapping
  ]

  @translations [
    {"propertyName", "property_name"}
  ]

  @primary_key false

  typed_embedded_schema do
    field(:property_name, :string)
    field(:mapping, :map)
  end

  def map_cast(struct \\ %__MODULE__{}, params) do
    with {:ok, translated} <- translate(params, @translations) do
      struct
      |> cast(translated, @list_of_fields)
    end
  end
end
