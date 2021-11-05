defmodule ExOAPI.Parser.V3.Context.Parameters do
  use TypedEctoSchema

  import Ecto.Changeset
  import ExOAPI.Helpers.Casting, only: [translate: 2]

  alias ExOAPI.Parser.V3.Context

  @list_of_fields [
    :name,
    :in,
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
    field(:in, ExOAPI.EctoTypes.ParameterIn)
    field(:description, :string)
    field(:required, :boolean, default: false)
    field(:deprecated, :boolean, default: false)
    field(:style, ExOAPI.EctoTypes.Style)
    field(:explode, :boolean)
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
      |> set_style()
      |> set_explodes()
    end
  end

  def set_style(changeset) do
    case get_field(changeset, :style) do
      nil ->
        case get_field(changeset, :in) do
          :query -> put_change(changeset, :style, :form)
          :cookie -> put_change(changeset, :style, :form)
          :path -> put_change(changeset, :style, :simple)
          :header -> put_change(changeset, :style, :simple)
        end

      _ ->
        changeset
    end
  end

  def set_explodes(changeset) do
    case get_field(changeset, :explode) do
      nil ->
        case get_field(changeset, :style) do
          :form -> put_change(changeset, :explode, true)
          _ -> put_change(changeset, :explode, false)
        end

      _ ->
        changeset
    end
  end
end
