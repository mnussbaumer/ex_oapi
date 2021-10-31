defmodule ExOAPI.Parser.V3.Context.Link do
  use TypedEctoSchema

  import Ecto.Changeset
  import ExOAPI.Helpers.Casting, only: [translate: 2]

  alias ExOAPI.Parser.V3.Context

  @list_of_fields [
    :operation_ref,
    :operation_id,
    :parameters,
    :request_body,
    :description
  ]

  @translations [
    {"operationRef", "operation_ref"},
    {"operationId", "operation_id"},
    {"requestBody", "request_body"}
  ]

  @primary_key false

  typed_embedded_schema do
    field(:operation_ref, :string)
    field(:operation_id, :string)
    field(:parameters, :map)
    field(:request_body, :map)
    field(:description, :string)
    embeds_one(:server, Context.Server)
  end

  def map_cast(struct \\ %__MODULE__{}, params) do
    with {:ok, translated} <- translate(params, @translations) do
      struct
      |> cast(translated, @list_of_fields)
      |> cast_embed(:server, with: &Context.Server.map_cast/2)
    end
  end
end
