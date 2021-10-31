defmodule ExOAPI.Parser.V3.Context.Media do
  use TypedEctoSchema

  import Ecto.Changeset

  alias ExOAPI.Parser.V3.Context

  @list_of_fields [
    :example,
    :examples,
    :encoding
  ]

  @primary_key false

  typed_embedded_schema do
    field(:example, :string)
    field(:examples, :map)
    field(:encoding, :map)
    embeds_one(:schema, Context.Schema)
  end

  def map_cast(map_body) when is_map(map_body) do
    %__MODULE__{}
    |> cast(map_body, @list_of_fields)
    |> cast_embed(:schema, with: &Context.Schema.map_cast/2)
  end
end
