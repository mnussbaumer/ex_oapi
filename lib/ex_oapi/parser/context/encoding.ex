defmodule ExOAPI.Parser.V3.Context.Encoding do
  use TypedEctoSchema

  import Ecto.Changeset
  import ExOAPI.Helpers.Casting, only: [translate: 2]

  alias ExOAPI.Parser.V3.Context

  @list_of_fields [
    :content_type,
    :headers,
    :style,
    :explode,
    :allow_reserved
  ]

  @translations [
    {"contentType", "content_type", ""},
    {"allowReserved", "allow_reserved", false}
  ]

  @primary_key false

  typed_embedded_schema do
    field(:content_type, :string)
    field(:headers, Context.Header.Map)
    field(:style, ExOAPI.EctoTypes.Style)
    field(:explode, :boolean)
    field(:allow_reserved, :boolean, default: false)
  end

  def map_cast(struct \\ %__MODULE__{}, params) do
    with {:ok, translated} <- translate(params, @translations) do
      struct
      |> cast(translated, @list_of_fields)
      |> set_explodes()
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
