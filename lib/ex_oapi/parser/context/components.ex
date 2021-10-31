defmodule ExOAPI.Parser.V3.Context.Components do
  use TypedEctoSchema

  import Ecto.Changeset
  import ExOAPI.Helpers.Casting, only: [translate: 2]

  alias ExOAPI.Parser.V3.Context

  @list_of_fields [
    :responses,
    :parameters,
    :examples,
    :request_bodies,
    :headers,
    :security_schemes,
    :links,
    :callbacks
  ]

  @translations [
    {"requestBodies", "request_bodies"},
    {"securitySchemes", "security_schemes"}
  ]

  @primary_key false

  typed_embedded_schema do
    field(:schemas, Context.Schema.Map)
    field(:responses, Context.Response.Map)
    field(:parameters, Context.Parameters.Map)
    field(:examples, Context.Example.Map)
    field(:request_bodies, Context.RequestBody.Map)
    field(:headers, Context.Header.Map)
    field(:security_schemes, Context.Security.Map)
    field(:links, Context.Link.Map)
    field(:callbacks, Context.Callback.Map)
  end

  def map_cast(struct \\ %__MODULE__{}, params) do
    with {:ok, translated} <- translate(params, @translations) do
      struct
      |> cast(translated, @list_of_fields)
      |> Context.toggle_schema_culling(true)
      |> cast(translated, [:schemas])
      |> Context.toggle_schema_culling(false)
    end
  end

  def add_to_schemas(
        k,
        schema,
        %Context{components: %__MODULE__{schemas: schemas} = components} = context
      ) do
    %Context{
      context
      | components: %__MODULE__{
          components
          | schemas: Map.put(schemas, k, schema)
        }
    }
  end
end
