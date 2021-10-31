defmodule ExOAPI.Parser.V3.Context.Server do
  use TypedEctoSchema
  import Ecto.Changeset

  @list_of_fields [
    :url,
    :description,
    :variables
  ]

  @primary_key false

  typed_embedded_schema do
    field(:url, :string)
    field(:description, :string)
    field(:variables, :map)
  end

  def map_cast(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, @list_of_fields)
  end
end
