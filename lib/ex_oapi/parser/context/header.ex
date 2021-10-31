defmodule ExOAPI.Parser.V3.Context.Header do
  use TypedEctoSchema

  import Ecto.Changeset
  import ExOAPI.Helpers.Casting, only: [translate: 2]

  alias ExOAPI.Parser.V3.Context

  @list_of_fields [
    :name,
    :description,
    :required,
    :deprecated,
    :style,
    :explode,
    :allow_empty_value,
    :allow_reserved,
    :example,
    :examples,
    :content
  ]

  @translations [
    {"allowEmptyValue", "allow_empty_value", false},
    {"allowReserved", "allow_reserved", false}
  ]

  @primary_key false

  typed_embedded_schema do
    field(:name, :string)
    field(:in, :string, default: "header")
    field(:description, :string)
    field(:required, :boolean, default: false)
    field(:deprecated, :boolean, default: false)
    field(:style, ExOAPI.EctoTypes.Style)
    field(:explode, :boolean, default: false)
    field(:allow_empty_value, :boolean, default: false)
    field(:allow_reserved, :boolean, default: false)
    field(:example, :string)
    field(:examples, :map)
    field(:content, Context.Content.Map)
    embeds_one(:schema, Context.Schema)
  end

  def map_cast(struct \\ %__MODULE__{}, params) do
    with {:ok, translated} <- translate(params, @translations) do
      struct
      |> cast(translated, @list_of_fields)
      |> cast_embed(:schema, with: &Context.Schema.map_cast/2)
    end
  end
end
