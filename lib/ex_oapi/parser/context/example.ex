defmodule ExOAPI.Parser.V3.Context.Example do
  use TypedEctoSchema
  import Ecto.Changeset

  import ExOAPI.Helpers.Casting, only: [translate: 2]

  @list_of_fields [
    :summary,
    :description,
    :value,
    :external_value
  ]

  @translations [
    {"externalValue", "external_value"}
  ]

  @primary_key false

  typed_embedded_schema do
    field(:summary, :string)
    field(:description, :string)
    field(:value, :string)
    field(:external_value, :string)
  end

  def map_cast(struct \\ %__MODULE__{}, params) do
    with {:ok, translated} <- translate(params, @translations) do
      struct
      |> cast(translated, @list_of_fields)
    end
  end
end
