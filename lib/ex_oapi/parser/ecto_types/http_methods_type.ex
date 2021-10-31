defmodule ExOAPI.EctoTypes.HTTPMethods do
  @moduledoc """
  """
  use ExOAPI.EctoTypes.TypedEnum,
    values: [
      :get,
      :put,
      :post,
      :delete,
      :options,
      :head,
      :patch
    ]
end
