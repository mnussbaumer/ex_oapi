defmodule ExOAPI.Parser.V3.Context.Info.Contact do
  use TypedEctoSchema
  import Ecto.Changeset

  @list_of_fields [
    :name,
    :url,
    :email
  ]

  @primary_key false

  typed_embedded_schema do
    field(:name, :string)
    field(:url, :string)
    field(:email, :string)
  end

  def map_cast(struct \\ %__MODULE__{}, params) do
    struct
    |> cast(params, @list_of_fields)
  end
end
