defmodule ExOAPI.Parser.V3.Context.Info do
  use TypedEctoSchema
  import Ecto.Changeset

  import ExOAPI.Helpers.Casting, only: [translate: 2]

  @list_of_fields [
    :title,
    :description,
    :terms_of_service,
    :license,
    :version
  ]

  @translations [
    {"termsOfService", "terms_of_service"}
  ]

  @primary_key false

  typed_embedded_schema do
    field(:title, :string)
    field(:description, :string)
    field(:terms_of_service, :string)
    field(:version, :string)
    field(:license, :map)
    embeds_one(:contact, __MODULE__.Contact)
  end

  def map_cast(struct \\ %__MODULE__{}, params) do
    with {:ok, translated} <- translate(params, @translations) do
      struct
      |> cast(translated, @list_of_fields)
      |> cast_embed(:contact, with: &__MODULE__.Contact.map_cast/2)
    end
  end
end
