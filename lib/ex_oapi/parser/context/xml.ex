defmodule ExOAPI.Parser.V3.Context.XML do
  use TypedEctoSchema
  import Ecto.Changeset

  @list_of_fields [
    :name,
    :namespace,
    :prefix,
    :attribute,
    :wrapped
  ]

  @primary_key false

  typed_embedded_schema do
    field(:name, :string)
    field(:namespace, :string)
    field(:prefix, :string)
    field(:attribute, :boolean, default: false)
    field(:wrapped, :boolean, default: false)
  end

  def map_cast(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, @list_of_fields)
  end
end
