defmodule ExOAPI.EctoTypes.ParameterIn do
  @moduledoc """
  """
  use ExOAPI.EctoTypes.TypedEnum,
    values: [
      :query,
      :header,
      :path,
      :cookie
    ]
end
