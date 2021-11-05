defmodule ExOAPI.EctoTypes.SchemaType do
  @moduledoc """
  """
  use ExOAPI.EctoTypes.TypedEnum,
    values: [
      :string,
      :number,
      :integer,
      :boolean,
      :array,
      :object
    ]
end
