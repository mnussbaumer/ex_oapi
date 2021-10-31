defmodule ExOAPI.Parser.V3.Context.Response do
  use TypedEctoSchema

  import Ecto.Changeset

  alias ExOAPI.Parser.V3.Context

  @list_of_fields [
    :description,
    :headers,
    :content,
    :links
  ]

  @primary_key false

  typed_embedded_schema do
    field(:description, :string)
    field(:headers, Context.Header.Map)
    field(:content, Context.Content.Map)
    field(:links, Context.Link.Map)
  end

  def map_cast(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, @list_of_fields)
  end
end
