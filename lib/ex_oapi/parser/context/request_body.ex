defmodule ExOAPI.Parser.V3.Context.RequestBody do
  use TypedEctoSchema
  import Ecto.Changeset

  alias ExOAPI.Parser.V3.Context

  @list_of_fields [
    :description,
    :content,
    :required
  ]

  @primary_key false

  typed_embedded_schema do
    field(:description, :string)
    field(:content, Context.Content.Map)
    field(:required, :boolean, default: false)
  end

  def map_cast(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, @list_of_fields)
  end
end
