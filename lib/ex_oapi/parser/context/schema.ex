defmodule ExOAPI.Parser.V3.Context.Schema do
  use TypedEctoSchema

  import Ecto.Changeset
  import ExOAPI.Helpers.Casting, only: [translate: 2]

  alias ExOAPI.Parser.V3.Context

  @list_of_fields [
    :title,
    :field_name,
    :multiple_of,
    :maximum,
    :exclusive_maximum,
    :minimum,
    :exclusive_minimum,
    :max_length,
    :min_length,
    :pattern,
    :max_items,
    :min_items,
    :unique_items,
    :max_properties,
    :min_properties,
    :required,
    :enum,
    :type,
    :properties,
    :additional_properties,
    :description,
    :format,
    # default
    :nullable,
    :read_only,
    :write_only,
    :deprecated,
    :ref
  ]

  @translations [
    {"multipleOf", "multiple_of"},
    {"exclusiveMaximum", "exclusive_maximum"},
    {"exclusiveMinimum", "exclusive_minimum"},
    {"maxLength", "max_length"},
    {"minLength", "min_length"},
    {"maxItems", "max_items"},
    {"minItems", "min_items"},
    {"uniqueItems", "unique_items"},
    {"maxProperties", "max_properties"},
    {"minProperties", "min_properties"},
    {"allOf", "all_of", []},
    {"anyOf", "any_of", []},
    {"oneOf", "one_of", []},
    {"additionalProperties", "additional_properties"},
    {"readOnly", "read_only"},
    {"writeOnly", "write_only"},
    {"externalDocs", "external_docs"},
    {"$ref", "ref"}
  ]

  @primary_key false

  typed_embedded_schema do
    field(:title, :string)
    field(:field_name, ExOAPI.EctoTypes.FieldAtom)
    field(:multiple_of, :integer)
    field(:maximum, :integer)
    field(:exclusive_maximum, :boolean, default: false)
    field(:minimum, :integer)
    field(:exclusive_minimum, :boolean, default: false)
    field(:max_length, :integer)
    field(:min_length, :integer)
    field(:pattern, :string)
    field(:max_items, :integer)
    field(:min_items, :integer)
    field(:unique_items, :boolean, default: false)
    field(:max_properties, :integer)
    field(:min_properties, :integer)
    field(:required, {:array, ExOAPI.EctoTypes.FieldAtom})
    field(:enum, {:array, :string})
    field(:type, ExOAPI.EctoTypes.SchemaType)

    field(:properties, Context.Schema.Map)

    field(:additional_properties, ExOAPI.EctoTypes.Maybe,
      types: [
        {:boolean, &__MODULE__.maybe_boolean/2},
        {__MODULE__, &__MODULE__.maybe_schema/2}
      ]
    )

    embeds_many(:all_of, Context.Schema)
    embeds_many(:any_of, Context.Schema)
    embeds_many(:one_of, Context.Schema)

    embeds_one(:not, Context.Schema)
    embeds_one(:items, Context.Schema)

    embeds_one(:xml, Context.XML)
    embeds_one(:external_docs, Context.ExternalDoc)
    embeds_one(:discriminator, Context.Discriminator)

    field(:description, :string)
    field(:format, :string)
    # default
    field(:nullable, :boolean)
    field(:read_only, :boolean)
    field(:write_only, :boolean)
    field(:deprecated, :boolean)
    field(:ref, :string)
  end

  def map_cast(%__MODULE__{} = struct, params, k) do
    with {:ok, translated} <- translate(params, @translations) do
      previous_toggle = Context.get_and_set_schema_culling(false)

      struct
      |> cast(translated, @list_of_fields)
      |> cast_embed(:all_of, with: &__MODULE__.map_cast/2)
      |> cast_embed(:any_of, with: &__MODULE__.map_cast/2)
      |> cast_embed(:one_of, with: &__MODULE__.map_cast/2)
      |> cast_embed(:not, with: &__MODULE__.map_cast/2)
      |> cast_embed(:items, with: &__MODULE__.map_cast/2)
      |> cast_embed(:xml, with: &Context.XML.map_cast/2)
      |> cast_embed(:external_docs, with: &Context.ExternalDoc.map_cast/2)
      |> cast_embed(:discriminator, with: &Context.Discriminator.map_cast/2)
      |> maybe_add_ref(k)
      |> Context.toggle_schema_culling(previous_toggle)
    end
  end

  def map_cast(params), do: map_cast(%__MODULE__{}, params, nil)
  def map_cast(%__MODULE__{} = struct, params), do: map_cast(struct, params, nil)
  def map_cast(params, k), do: map_cast(%__MODULE__{}, params, k)

  def maybe_boolean(data, _params), do: Ecto.Type.cast(:boolean, data)

  def maybe_schema(data, _params, k \\ nil) do
    data
    |> map_cast(k)
    |> apply_action(:insert)
  end

  def maybe_add_ref(%Ecto.Changeset{} = changeset, k) do
    case get_field(changeset, :ref, nil) do
      nil ->
        changeset

      ref ->
        Context.put_ref(k, ref)
        changeset
    end
  end
end
