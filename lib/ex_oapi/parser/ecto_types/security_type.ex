defmodule ExOAPI.EctoTypes.Security do
  @moduledoc """
  """
  use ExOAPI.EctoTypes.TypedEnum, values: [:apiKey, :http, :oauth2, :openIdConnect]
end
