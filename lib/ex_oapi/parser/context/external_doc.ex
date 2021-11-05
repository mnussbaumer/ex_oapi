defmodule ExOAPI.Parser.V3.Context.ExternalDoc do
  use TypedEctoSchema
  import Ecto.Changeset

  @list_of_fields [
    :description,
    :url
  ]

  @primary_key false

  typed_embedded_schema do
    field(:description, :string)
    field(:url, :string)
  end

  def map_cast(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, @list_of_fields)
  end
end

defimpl String.Chars, for: ExOAPI.Parser.V3.Context.ExternalDoc do
  def to_string(%{description: description, url: url}) do
    description = if(description, do: description, else: url)

    "[#{description}](#{url})"
  end
end
